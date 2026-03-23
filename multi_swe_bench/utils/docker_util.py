# Copyright (c) 2024 Bytedance Ltd. and/or its affiliates

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

import logging
import os
import re
import warnings
from pathlib import Path
from typing import Optional, Union

# Suppress the gevent concurrency warning from Docker SDK
warnings.filterwarnings("ignore", message=".*gevent.*")

import docker

docker_client = docker.from_env()


def exists(image_name: str) -> bool:
    try:
        docker_client.images.get(image_name)
        return True
    except docker.errors.ImageNotFound:
        return False


def build(
    workdir: Path,
    dockerfile_name: str,
    image_full_name: str,
    logger: logging.Logger,
    timeout: int = 3600,
    retries: int = 2,
):
    """Build a Docker image with retry support

    Args:
        workdir: Working directory path
        dockerfile_name: Name of the Dockerfile
        image_full_name: Full name of the image to build
        logger: Logger instance
        timeout: Timeout in seconds for the build operation (default: 3600 = 1 hour)
        retries: Number of retry attempts on failure (default: 2)
    """
    workdir = str(workdir)

    def _do_build():
        logger.info(
            f"Start building image `{image_full_name}`, working directory is `{workdir}`"
        )
        try:
            build_logs = docker_client.api.build(
                path=workdir,
                dockerfile=dockerfile_name,
                tag=image_full_name,
                rm=True,
                forcerm=True,
                nocache=True,
                decode=True,
                encoding="utf-8",
                timeout=timeout,
            )

            for log in build_logs:
                if "stream" in log:
                    logger.info(log["stream"].strip())
                elif "error" in log:
                    error_message = log["error"].strip()
                    logger.error(f"Docker build error: {error_message}")
                    raise RuntimeError(f"Docker build failed: {error_message}")
                elif "status" in log:
                    logger.info(log["status"].strip())
                elif "aux" in log:
                    logger.info(log["aux"].get("ID", "").strip())

            logger.info(f"image({workdir}) build success: {image_full_name}")
        except docker.errors.BuildError as e:
            logger.error(f"build error: {e}")
            raise e
        except Exception as e:
            logger.error(f"Unknown build error occurred: {e}")
            raise e

    # Attempt build with retries
    attempt = 0
    last_error = None
    while attempt <= retries:
        try:
            _do_build()
            return  # Success, exit the function
        except Exception as e:
            last_error = e
            attempt += 1
            if attempt <= retries:
                logger.warning(
                    f"Build failed (attempt {attempt}/{retries + 1}), retrying in 10s..."
                )
                import time

                time.sleep(10)
            else:
                logger.error(
                    f"Build failed after {retries + 1} attempts, giving up."
                )
                raise last_error


def run(
    image_full_name: str,
    run_command: str,
    output_path: Optional[Path] = None,
    global_env: Optional[list[str]] = None,
    volumes: Optional[Union[dict[str, str], list[str]]] = None,
) -> str:
    container = None
    try:
        container = docker_client.containers.run(
            image=image_full_name,
            command=run_command,
            remove=False,
            detach=True,
            stdout=True,
            stderr=True,
            environment=global_env,
            volumes=volumes,
        )

        output = ""
        if output_path:
            # Wait for container to finish first to ensure all logs are captured
            container.wait()
            # Then fetch all logs at once
            logs = container.logs(stdout=True, stderr=True)
            output = logs.decode("utf-8")
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(output)
        else:
            container.wait()
            output = container.logs().decode("utf-8")

        return output
    finally:
        if container:
            try:
                container.remove(force=True)
            except Exception as e:
                print(f"Warning: Failed to remove container: {e}")


def remove(image_name: str, logger: logging.Logger = None):
    """Remove a Docker image by name

    Args:
        image_name: The name of the Docker image to remove
        logger: Optional logger for logging output
    """
    try:
        docker_client.images.remove(image_name, force=True)
        if logger:
            logger.info(f"Image {image_name} removed successfully")
    except Exception as e:
        if logger:
            logger.warning(f"Failed to remove image {image_name}: {e}")


def cleanup_docker_images(
    org: str,
    repo: str,
    pr_number: str,
    logger: logging.Logger = None
):
    """Clean up Docker images after processing a PR record

    Removes:
    - Images with tag matching pattern: pr-{number}
    - Dangling images with <none> name or tag (using Docker filter)
    - Any images with <none> tags (second pass scan)

    Preserves:
    - All other images including base images
    - PostgreSQL images (postgres, postgis) - required for database operations

    Args:
        org: GitHub organization name
        repo: GitHub repository name
        pr_number: Pull request number
        logger: Optional logger for logging output
    """
    if logger:
        logger.info(f"Starting Docker image cleanup for {org}/{repo}#{pr_number}")

    removed_count = 0
    dangling_count = 0

    # Remove images with tag pr-{number}
    try:
        images = docker_client.images.list()
        for image in images:
            image_tags = image.tags if image.tags else []

            # Skip PostgreSQL images - needed for database operations
            is_postgres = False
            for tag in image_tags:
                if "postgres" in tag.lower() or "postgis" in tag.lower():
                    is_postgres = True
                    break

            if is_postgres:
                continue

            # Check if any tag ends with :pr-{number} pattern
            # Full tag format is like "envagent/ansible_m_ansible:pr-86642"
            for tag in image_tags:
                # Extract just the tag part after the last colon
                tag_parts = tag.split(":")
                image_tag = tag_parts[-1] if len(tag_parts) > 1 else tag

                if image_tag == f"pr-{pr_number}":
                    if logger:
                        logger.info(f"Removing image with tag {tag}")
                    remove(tag, logger)
                    removed_count += 1
                    break
    except Exception as e:
        if logger:
            logger.warning(f"Error removing pr-{pr_number} images: {e}")

    # Remove dangling images (images with <none> name or tag)
    try:
        # First pass: remove dangling images using Docker filter
        dangling_images = docker_client.images.list(filters={"dangling": True})
        for image in dangling_images:
            image_tags = image.tags if image.tags else []

            # Check if image has <none> tag or no tags at all
            is_dangling = False
            if not image_tags:
                is_dangling = True
            else:
                for tag in image_tags:
                    if "<none>" in tag:
                        is_dangling = True
                        break

            if is_dangling:
                if logger:
                    logger.info(f"Removing dangling image: {image.short_id}")
                try:
                    docker_client.images.remove(image.id, force=True)
                    dangling_count += 1
                except Exception as e:
                    if logger:
                        logger.warning(f"Failed to remove dangling image {image.short_id}: {e}")

        # Second pass: scan ALL images for any with <none> tags that might not be marked as dangling
        all_images = docker_client.images.list()
        for image in all_images:
            image_tags = image.tags if image.tags else []

            # Check if any tag contains <none>
            has_none_tag = False
            for tag in image_tags:
                if "<none>" in tag:
                    has_none_tag = True
                    break

            if has_none_tag:
                # Skip if already removed in the first pass
                try:
                    docker_client.images.get(image.id)
                    if logger:
                        logger.info(f"Removing image with <none> tag: {image.short_id}")
                    docker_client.images.remove(image.id, force=True)
                    dangling_count += 1
                except docker.errors.ImageNotFound:
                    pass  # Already removed
                except Exception as e:
                    if logger:
                        logger.warning(f"Failed to remove image with <none> tag {image.short_id}: {e}")
    except Exception as e:
        if logger:
            logger.warning(f"Error during <none> tag image cleanup: {e}")

    if logger:
        logger.info(
            f"Cleanup complete: removed {removed_count} pr-{pr_number} images, "
            f"{dangling_count} dangling images"
        )
