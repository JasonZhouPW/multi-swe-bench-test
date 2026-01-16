import re
from typing import Optional, Union

from multi_swe_bench.harness.image import Config, File, Image
from multi_swe_bench.harness.instance import Instance, TestResult
from multi_swe_bench.harness.pull_request import PullRequest


class ImageBase(Image):
    def __init__(self, pr: PullRequest, config: Config):
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    @property
    def config(self) -> Config:
        return self._config

    def dependency(self) -> Union[str, "Image"]:
        return "golang:latest"

    def image_tag(self) -> str:
        return "base"

    def workdir(self) -> str:
        return "base"

    def files(self) -> list[File]:
        return []

    def dockerfile(self) -> str:
        image_name = self.dependency()
        if isinstance(image_name, Image):
            image_name = image_name.image_full_name()

        if self.config.need_clone:
            code = f"RUN git clone https://github.com/{self.pr.org}/{self.pr.repo}.git /home/{self.pr.repo}"
        else:
            code = f"COPY {self.pr.repo} /home/{self.pr.repo}"

        return f"""FROM {image_name}

{self.global_env}

WORKDIR /home/

{code}

{self.clear_env}

"""


class ImageDefault(Image):
    def __init__(self, pr: PullRequest, config: Config):
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    @property
    def config(self) -> Config:
        return self._config

    def dependency(self) -> Image | None:
        return ImageBase(self.pr, self.config)

    def image_tag(self) -> str:
        return f"pr-{self.pr.number}"

    def workdir(self) -> str:
        return f"pr-{self.pr.number}"

    def files(self) -> list[File]:
        return [
            File(".", "fix.patch", f"{self.pr.fix_patch}"),
            File(".", "test.patch", f"{self.pr.test_patch}"),
            File(".", "run.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
go test -v -count=1 ./...
""".format(pr=self.pr)),
            File(".", "test-run.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
git apply /home/test.patch
go test -v -count=1 ./...
""".format(pr=self.pr)),
            File(".", "fix-run.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
git apply /home/test.patch /home/fix.patch
go test -v -count=1 ./...
""".format(pr=self.pr)),
            File(".", "check_git_changes.sh", """#!/bin/bash
set -e
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Not inside git repo"; exit 1;
fi
if [[ -n $(git status --porcelain) ]]; then
  echo "Uncommitted changes"; exit 1;
fi
echo "Clean"
"""),
            File(".", "resolve_go_file.sh", """#!/bin/bash
set -e
REPO_PATH="$1"
find "$REPO_PATH" -type f -name "*.go" | while read -r file; do
  if [[ $(cat "$file") =~ ^[./a-zA-Z0-9_\\-]+\\.go$ ]]; then
    target=$(cat "$file")
    abs=$(realpath -m "$(dirname "$file")/$target")
    if [ -f "$abs" ]; then
      cat "$abs" > "$file"
    fi
  fi
done
"""),
            File(".", "prepare.sh", """#!/bin/bash
set -e
cd /home/{pr.repo}
git reset --hard
bash /home/check_git_changes.sh
git checkout {pr.base.sha}
bash /home/check_git_changes.sh
bash /home/resolve_go_file.sh /home/{pr.repo}

# Injected setup commands


go test -v -count=1 ./... || true
""".format(pr=self.pr)),
        ]

    def dockerfile(self) -> str:
        parent = self.dependency()
        name = parent.image_name()
        tag = parent.image_tag()

        copy_cmds = "".join([f"COPY {f.name} /home/\n" for f in self.files()])

        return f"""FROM {name}:{tag}

{self.global_env}

{copy_cmds}
RUN chmod +x /home/prepare.sh /home/run.sh /home/test-run.sh /home/fix-run.sh /home/check_git_changes.sh /home/resolve_go_file.sh
RUN bash /home/prepare.sh

{self.clear_env}

"""


@Instance.register("gin-gonic", "gin")
class InstanceTemplate(Instance):
    def __init__(self, pr: PullRequest, config: Config, *args, **kwargs):
        super().__init__()
        self._pr = pr
        self._config = config

    @property
    def pr(self) -> PullRequest:
        return self._pr

    def dependency(self) -> Optional[Image]:
        return ImageDefault(self.pr, self._config)

    def run(self, cmd: str = "") -> str:
        return cmd or "bash /home/run.sh"

    def test_patch_run(self, cmd: str = "") -> str:
        return cmd or "bash /home/test-run.sh"

    def fix_patch_run(self, cmd: str = "") -> str:
        return cmd or "bash /home/fix-run.sh"

    def parse_log(self, test_log: str) -> TestResult:
        passed, failed, skipped = set(), set(), set()

        # Per-test lines
        re_pass = re.compile(r"--- PASS: (\S+)")
        re_fail = re.compile(r"--- FAIL: (\S+)")
        re_skip = re.compile(r"--- SKIP: (\S+)")
        # Package-level results (e.g. "ok  github.com/org/repo/pkg 0.003s" or "FAIL\tgithub.com/org/repo/pkg 0.003s")
        re_pkg_ok = re.compile(r"^ok\s+(\S+)\b")
        re_pkg_fail = re.compile(r"^FAIL\s+(\S+)\b")

        for line in test_log.splitlines():
            line = line.strip()
            if m := re_pass.match(line): passed.add(m.group(1))
            if m := re_fail.match(line): failed.add(m.group(1))
            if m := re_skip.match(line): skipped.add(m.group(1))
            if m := re_pkg_fail.match(line):
                pkg = m.group(1)
                failed.add(f"pkg::{pkg}")

        # Ensure disjoint sets: Fail > Pass > Skip

        passed -= failed

        skipped -= failed

        skipped -= passed


        return TestResult(
            passed_count=len(passed),
            failed_count=len(failed),
            skipped_count=len(skipped),
            passed_tests=passed,
            failed_tests=failed,
            skipped_tests=skipped,
        )
