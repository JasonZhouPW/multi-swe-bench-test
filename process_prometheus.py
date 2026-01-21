import json
import os

input_file = "data/datasets/prometheus__prometheus_dataset.jsonl"
base_dir = "sample_data/bug-fix"

with open(input_file, "r") as f:
    content = f.read().strip()

# Split on }{ to handle concatenated JSON
records = content.replace("}{", "}\n{").split("\n")

for line in records:
    line = line.strip()
    if not line:
        continue
    
    try:
        record = json.loads(line)
        org = record["org"]
        repo = record["repo"]
        pr_num = record["number"]
        sub_dir = f"{org}__{repo}-{pr_num}"
        full_dir = os.path.join(base_dir, sub_dir)
        os.makedirs(full_dir, exist_ok=True)
        
        # Copy dataset
        dataset_path = os.path.join(full_dir, 'dataset.json')
        with open(dataset_path, 'w') as out_f:
            json.dump(record, out_f, indent=2)
        
        # Create results and scripts
        os.makedirs(os.path.join(full_dir, 'results'), exist_ok=True)
        scripts_dir = os.path.join(full_dir, 'scripts')
        os.makedirs(scripts_dir, exist_ok=True)
        
        # Copy from workdir
        workdir_pr = f"data/workdir/{org}/{repo}/images/pr-{pr_num}"
        if os.path.exists(workdir_pr):
            for file in os.listdir(workdir_pr):
                src = os.path.join(workdir_pr, file)
                dst = os.path.join(scripts_dir, file)
                if os.path.isfile(src):
                    os.system(f'cp "{src}" "{dst}"')
        
        # Copy instances
        instances_pr = f"data/workdir/{org}/{repo}/instances/pr-{pr_num}"
        if os.path.exists(instances_pr):
            results_dir = os.path.join(full_dir, "results")
            for file in os.listdir(instances_pr):
                src = os.path.join(instances_pr, file)
                if file in ["fix-patch-run.log", "report.json", "run.log", "test-patch-run.log"]:
                    dst = os.path.join(results_dir, file)
                else:
                    dst = os.path.join(scripts_dir, file)
                if os.path.isfile(src):
                    os.system(f'cp "{src}" "{dst}"')
        
        # Copy Dockerfiles
        base_docker = f"data/workdir/{org}/{repo}/images/base/Dockerfile"
        if os.path.exists(base_docker):
            os.system(f'cp "{base_docker}" "{full_dir}/base-Dockerfile"')
        
        patch_docker = f"data/workdir/{org}/{repo}/images/pr-{pr_num}/Dockerfile"
        if os.path.exists(patch_docker):
            os.system(f'cp "{patch_docker}" "{full_dir}/patch-Dockerfile"')
        
        print(f"Processed {org}/{repo} PR {pr_num}")
        
    except Exception as e:
        print(f"Error processing line: {e}")
