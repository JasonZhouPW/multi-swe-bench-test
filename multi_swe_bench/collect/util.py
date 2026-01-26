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

import argparse
import asyncio
import json
import sys
import time
import urllib.request
import urllib.error
from typing import Optional
from pathlib import Path


def parse_tokens(tokens: str | list[str] | Path) -> list[str]:
    """
    Try to parse tokens as a list of strings.

    Supported input formats:
    - list[str]: returned unchanged
    - comma-separated string: "tok1,tok2"
    - file path string or Path: read non-empty lines from the file
    - single token string: returned as a single-element list
    """

    if isinstance(tokens, list):
        return tokens

    # If a Path object is provided, read non-empty lines
    if isinstance(tokens, Path):
        if not tokens.exists() or not tokens.is_file():
            raise ValueError(f"Token file {tokens} does not exist or is not a file.")
        with tokens.open("r", encoding="utf-8") as file:
            return [line.strip() for line in file if line.strip()]

    # Handle strings
    if isinstance(tokens, str):
        s = tokens.strip()
        # Comma-separated list
        if "," in s:
            return [t.strip() for t in s.split(",") if t.strip()]
        # String that looks like a path to an existing file
        p = Path(s)
        if p.exists() and p.is_file():
            with p.open("r", encoding="utf-8") as file:
                return [line.strip() for line in file if line.strip()]
        # Single token string
        return [s]

    return []


def find_default_token_file() -> Path:
    """
    Try to find a default token file in the current directory.
    """

    possible_files = ["token", "tokens", "token.txt", "tokens.txt"]
    for file_name in possible_files:
        file_path = Path(file_name)
        file_path = Path.cwd() / file_path
        if file_path.exists() and file_path.is_file():
            return file_path
    return None


def get_tokens(tokens) -> list[str]:
    if tokens is None:
        default_token_file = find_default_token_file()
        if default_token_file is None:
            print("Error: No tokens provided and no default token file found.")
            sys.exit(1)
        tokens = default_token_file
    else:
        ## if tokensstr contains ',', split it
        if isinstance(tokens, str) and "," in tokens:
            tokens = tokens.split(",")
        # If tokens are provided as a list, they might need conversion
        else:
            tokens = tokens[0] if len(tokens) == 1 else tokens

    try:
        token_list = parse_tokens(tokens)
        if not token_list:
            raise ValueError("Token list is empty after parsing.")
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    assert token_list, "No tokens provided."
    return token_list


def optional_int(value):
    if value.lower() == "none" or value.lower() == "null" or value == "":
        return None
    try:
        return int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid integer value: {value}")


def make_request_with_retry(
    request_func,
    max_retries: int = 5,
    initial_backoff: float = 1.0,
    backoff_multiplier: float = 2.0,
    max_backoff: float = 60.0,
    verbose: bool = True,
):
    """
    Wrapper for making HTTP requests with exponential backoff retry for rate limiting.

    Args:
        request_func: A function that performs the HTTP request and returns response
        max_retries: Maximum number of retry attempts (default: 5)
        initial_backoff: Initial backoff time in seconds (default: 1.0)
        backoff_multiplier: Multiplier for exponential backoff (default: 2.0)
        max_backoff: Maximum backoff time in seconds (default: 60.0)
        verbose: Whether to print retry messages (default: True)

    Returns:
        The response from request_func

    Raises:
        Exception: If all retries are exhausted
    """
    last_error = None

    for attempt in range(max_retries):
        try:
            response = request_func()

            is_rate_limited = False
            if hasattr(response, "status_code"):
                if response.status_code == 429:
                    is_rate_limited = True
                    last_error = Exception(f"HTTP 429: Rate limit exceeded")
                elif response.status_code == 403:
                    is_rate_limited = True
                    last_error = Exception(f"HTTP 403: Forbidden (possibly rate limit)")
                else:
                    return response
            elif hasattr(response, "status"):
                if response.status == 429:
                    is_rate_limited = True
                    last_error = Exception(f"HTTP 429: Rate limit exceeded")
                elif response.status == 403:
                    is_rate_limited = True
                    last_error = Exception(f"HTTP 403: Forbidden (possibly rate limit)")
                else:
                    return response
            else:
                return response

            if is_rate_limited:
                backoff_time = min(
                    initial_backoff * (backoff_multiplier**attempt), max_backoff
                )

                if hasattr(response, "headers"):
                    reset_time_str = response.headers.get(
                        "X-RateLimit-Reset"
                    ) or response.headers.get("Retry-After")
                    if reset_time_str:
                        try:
                            reset_time = int(reset_time_str)
                            current_time = int(time.time())
                            if reset_time > current_time:
                                backoff_time = max(
                                    backoff_time, reset_time - current_time
                                )
                        except (ValueError, TypeError):
                            pass

                if verbose:
                    print(
                        f"Rate limit hit (attempt {attempt + 1}/{max_retries}). "
                        f"Waiting {backoff_time:.1f} seconds before retry..."
                    )
                time.sleep(backoff_time)
                continue

            if last_error:
                raise last_error

            return response

        except Exception as e:
            last_error = e
            if attempt < max_retries - 1:
                backoff_time = min(
                    initial_backoff * (backoff_multiplier**attempt), max_backoff
                )
                if verbose:
                    print(
                        f"Request failed (attempt {attempt + 1}/{max_retries}): {str(e)}. "
                        f"Waiting {backoff_time:.1f} seconds before retry..."
                    )
                time.sleep(backoff_time)
            else:
                raise Exception(
                    f"Request failed after {max_retries} attempts: {str(e)}"
                )

    raise last_error if last_error else Exception("Request failed after retries")


async def async_request_with_retry(
    request_func,
    max_retries: int = 5,
    initial_backoff: float = 1.0,
    backoff_multiplier: float = 2.0,
    max_backoff: float = 60.0,
    verbose: bool = True,
):
    """
    Async wrapper for making HTTP requests with exponential backoff retry for rate limiting.

    Args:
        request_func: An async function that performs HTTP request and returns response
        max_retries: Maximum number of retry attempts (default: 5)
        initial_backoff: Initial backoff time in seconds (default: 1.0)
        backoff_multiplier: Multiplier for exponential backoff (default: 2.0)
        max_backoff: Maximum backoff time in seconds (default: 60.0)
        verbose: Whether to print retry messages (default: True)

    Returns:
        The response from request_func

    Raises:
        Exception: If all retries are exhausted
    """
    last_error = None

    for attempt in range(max_retries):
        try:
            response = await request_func()

            is_rate_limited = False
            if response.status == 429:
                is_rate_limited = True
                last_error = Exception(f"HTTP 429: Rate limit exceeded")
            elif response.status == 403:
                is_rate_limited = True
                last_error = Exception(f"HTTP 403: Forbidden (possibly rate limit)")
            else:
                response.raise_for_status()
                return response

            if is_rate_limited and attempt < max_retries - 1:
                backoff_time = min(
                    initial_backoff * (backoff_multiplier**attempt), max_backoff
                )

                reset_time_str = response.headers.get(
                    "X-RateLimit-Reset"
                ) or response.headers.get("Retry-After")
                if reset_time_str:
                    try:
                        reset_time = int(reset_time_str)
                        current_time = int(time.time())
                        if reset_time > current_time:
                            backoff_time = max(backoff_time, reset_time - current_time)
                    except (ValueError, TypeError):
                        pass

                if verbose:
                    print(
                        f"Rate limit hit (attempt {attempt + 1}/{max_retries}). "
                        f"Waiting {backoff_time:.1f} seconds before retry..."
                    )
                await asyncio.sleep(backoff_time)
                continue

            if last_error:
                raise last_error

            return response

        except Exception as e:
            last_error = e
            if attempt < max_retries - 1:
                backoff_time = min(
                    initial_backoff * (backoff_multiplier**attempt), max_backoff
                )
                if verbose:
                    print(
                        f"Request failed (attempt {attempt + 1}/{max_retries}): {str(e)}. "
                        f"Waiting {backoff_time:.1f} seconds before retry..."
                    )
                await asyncio.sleep(backoff_time)
            else:
                raise Exception(
                    f"Request failed after {max_retries} attempts: {str(e)}"
                )

    raise last_error if last_error else Exception("Request failed after retries")
