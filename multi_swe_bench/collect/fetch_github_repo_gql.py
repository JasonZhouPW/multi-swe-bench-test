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

"""
GitHub GraphQL API Test Module - Rate Limit Optimized

This module provides functions to fetch repositories and pull requests
using GitHub's GraphQL API with various filtering conditions.

Key features for rate limit avoidance:
- Token rotation across multiple tokens
- GraphQL for efficient batch fetching
- Rate limit tracking per token
- Parallel processing with rate limit awareness
- ETag caching for conditional requests

GraphQL Endpoint: https://api.github.com/graphql
"""

import json
import argparse
import random
import re
import time
import csv
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
from collections import defaultdict
from pathlib import Path

import requests

from multi_swe_bench.collect.util import get_tokens, make_request_with_retry


GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"
GITHUB_REST_URL = "https://api.github.com"


@dataclass
class RateLimitStatus:
    """Track rate limit status for a token."""

    remaining: int = 5000
    limit: int = 5000
    reset_time: float = 0.0
    token: str = ""

    def is_exhausted(self) -> bool:
        """Check if rate limit is exhausted."""
        return self.remaining <= 0

    def should_wait(self) -> bool:
        """Check if we should wait before making requests."""
        if self.remaining <= 0:
            return True
        now = time.time()
        if self.reset_time > now:
            wait_time = self.reset_time - now + 1
            return wait_time > 0
        return False

    def get_wait_time(self) -> float:
        """Get recommended wait time in seconds."""
        if self.remaining <= 0:
            now = time.time()
            return max(0, self.reset_time - now) + 1
        return 0.0


class RateLimitedClient:
    """
    Rate limit aware client with token rotation.

    This class manages multiple GitHub tokens and automatically rotates them
    to avoid hitting rate limits. It tracks rate limit status for each token
    and distributes requests intelligently.
    """

    def __init__(self, tokens: List[str]):
        """
        Initialize the rate-limited client.

        Args:
            tokens: List of GitHub Personal Access Tokens
        """
        if not tokens:
            raise ValueError("At least one GitHub token is required")

        self.tokens = tokens
        self.token_status: Dict[str, RateLimitStatus] = {}
        self.current_token_index = 0

        # Initialize status for each token
        for token in tokens:
            self.token_status[token] = RateLimitStatus(token=token)

        # GraphQL client state
        self.graphql_queries_per_second = 0
        self.last_query_time = 0

    def _get_best_token(self) -> str:
        """Get the token with the most remaining requests."""
        best_token = None
        best_remaining = -1

        for token, status in self.token_status.items():
            # Skip tokens that need to wait
            if status.should_wait():
                continue
            if status.remaining > best_remaining:
                best_remaining = status.remaining
                best_token = token

        # If all tokens need rest, find the one with earliest reset
        if best_token is None:
            earliest_reset = float("inf")
            for token, status in self.token_status.items():
                if status.reset_time < earliest_reset:
                    earliest_reset = status.reset_time
                    best_token = token

        return best_token or self.tokens[0]

    def _update_rate_limit(self, token: str, response) -> None:
        """Update rate limit status from response headers."""
        status = self.token_status.get(token)
        if status is None:
            return

        # GraphQL rate limits
        if "X-RateLimit-Limit" in response.headers:
            status.limit = int(response.headers.get("X-RateLimit-Limit", 5000))
            status.remaining = int(response.headers.get("X-RateLimit-Remaining", 5000))
            reset_ts = int(response.headers.get("X-RateLimit-Reset", 0))
            status.reset_time = reset_ts

        # REST API rate limits
        elif "x-ratelimit-limit" in response.headers:
            status.limit = int(response.headers.get("x-ratelimit-limit", 5000))
            status.remaining = int(response.headers.get("x-ratelimit-remaining", 5000))
            reset_ts = int(response.headers.get("x-ratelimit-reset", 0))
            status.reset_time = reset_ts

    def _wait_for_token(self, token: str) -> None:
        """Wait if token needs rate limit recovery."""
        status = self.token_status.get(token)
        if status:
            wait_time = status.get_wait_time()
            if wait_time > 0:
                print(
                    f"  Rate limit approaching, waiting {wait_time:.1f}s for token..."
                )
                time.sleep(wait_time)
                # Reset remaining after waiting
                status.remaining = status.limit

    def execute_graphql(
        self, query: str, variables: Optional[Dict[str, Any]] = None, timeout: int = 30
    ) -> Dict[str, Any]:
        """
        Execute GraphQL query with automatic token rotation and rate limiting.
        """
        payload: Dict[str, Any] = {"query": query}
        if variables:
            payload["variables"] = variables

        # Rate limit GraphQL queries
        now = time.time()
        time_since_last = now - self.last_query_time
        if time_since_last < 0.2:  # Max 5 queries per second
            time.sleep(0.2 - time_since_last)
        self.last_query_time = time.time()

        token = self._get_best_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        def make_request():
            return requests.post(
                GITHUB_GRAPHQL_URL,
                headers=headers,
                data=json.dumps(payload),
                timeout=timeout,
            )

        response = make_request_with_retry(
            make_request,
            max_retries=5,
            initial_backoff=1.0,
            backoff_multiplier=2.0,
            max_backoff=60.0,
            verbose=False,
        )

        self._update_rate_limit(token, response)
        response.raise_for_status()
        result = response.json()

        # Check for GraphQL errors
        if "errors" in result:
            error_messages = [
                e.get("message", "Unknown error") for e in result["errors"]
            ]
            raise Exception(f"GraphQL errors: {', '.join(error_messages)}")

        return result.get("data", {})

    def fetch_rest(
        self,
        url: str,
        params: Optional[Dict[str, Any]] = None,
        token: Optional[str] = None,
        use_etag: bool = True,
    ) -> requests.Response:
        """
        Fetch from REST API with rate limiting.

        Args:
            url: REST API URL
            params: Query parameters
            token: Specific token to use (None for automatic selection)
            use_etag: Whether to use ETag for conditional requests
        """
        if token is None:
            token = self._get_best_token()

        self._wait_for_token(token)

        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }

        if use_etag:
            # Check if we have cached ETag
            etag_key = f"etag:{url}"
            cached_etag = getattr(self, "_etag_cache", {}).get(etag_key)
            if cached_etag:
                headers["If-None-Match"] = cached_etag

        def make_request():
            return requests.get(url, headers=headers, params=params)

        response = make_request_with_retry(
            make_request,
            max_retries=5,
            initial_backoff=1.0,
            backoff_multiplier=2.0,
            max_backoff=60.0,
            verbose=False,
        )

        self._update_rate_limit(token, response)

        # Cache ETag
        if use_etag and response.status_code == 200:
            etag = response.headers.get("ETag")
            if etag:
                if not hasattr(self, "_etag_cache"):
                    self._etag_cache = {}
                self._etag_cache[f"etag:{url}"] = etag

        return response

    def get_rate_limit_summary(self) -> Dict[str, Dict]:
        """Get rate limit status for all tokens."""
        return {
            token[:10] + "...": {
                "remaining": status.remaining,
                "limit": status.limit,
                "reset_time": time.strftime(
                    "%Y-%m-%d %H:%M:%S", time.localtime(status.reset_time)
                ),
            }
            for token, status in self.token_status.items()
        }


class GitHubGraphQLClient:
    """Client for interacting with GitHub's GraphQL API."""

    def __init__(self, token: str):
        """
        Initialize the GraphQL client.

        Args:
            token: GitHub Personal Access Token with appropriate scopes
        """
        self.token = token
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/vnd.github.hawkgirl-preview+json",
        }
        self.max_retries = 5
        self.retry_delay = 1.0

    def execute_query(
        self, query: str, variables: Optional[Dict[str, Any]] = None, timeout: int = 30
    ) -> Dict[str, Any]:
        """
        Execute a GraphQL query with automatic retry on rate limiting.

        Args:
            query: GraphQL query string
            variables: Optional variables for the query
            timeout: Request timeout in seconds

        Returns:
            GraphQL response data

        Raises:
            Exception: If query fails after all retries
        """
        payload: Dict[str, Any] = {"query": query}
        if variables:
            payload["variables"] = variables

        def make_request():
            return requests.post(
                GITHUB_GRAPHQL_URL,
                headers=self.headers,
                data=json.dumps(payload),
                timeout=timeout,
            )

        response = make_request_with_retry(
            make_request,
            max_retries=self.max_retries,
            initial_backoff=self.retry_delay,
            backoff_multiplier=2.0,
            max_backoff=60.0,
            verbose=True,
        )

        response.raise_for_status()
        result = response.json()

        # Check for GraphQL errors
        if "errors" in result:
            error_messages = [
                e.get("message", "Unknown error") for e in result["errors"]
            ]
            raise Exception(f"GraphQL errors: {', '.join(error_messages)}")

        return result.get("data", {})

    def fetch_repositories(
        self, owner: str, first: int = 100, after: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Fetch repositories for a given owner/organization.

        Args:
            owner: Repository owner (user or organization)
            first: Number of repositories to fetch (max 100)
            after: Cursor for pagination

        Returns:
            Dict containing repositories and pagination cursor
        """
        query = """
        query($owner: String!, $first: Int!, $after: String) {
            repositoryOwner(login: $owner) {
                repositories(first: $first, after: $after, orderBy: {field: STARGAZERS, direction: DESC}) {
                    pageInfo {
                        hasNextPage
                        endCursor
                    }
                    nodes {
                        name
                        nameWithOwner
                        description
                        url
                        stargazerCount
                        forkCount
                        createdAt
                        updatedAt
                        primaryLanguage {
                            name
                        }
                        isArchived
                        isFork
                    }
                }
            }
        }
        """

        variables = {"owner": owner, "first": min(first, 100), "after": after}
        return self.execute_query(query, variables)

    def search_repositories(
        self, query: str, first: int = 100, after: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Search repositories using GitHub's search syntax.

        Args:
            query: Search query (e.g., "language:python stars:>1000")
            first: Number of results (max 100)
            after: Cursor for pagination

        Returns:
            Search results with pagination info
        """
        graphql_query = """
        query($query: String!, $first: Int!, $after: String) {
            search(query: $query, type: REPOSITORY, first: $first, after: $after) {
                repositoryCount
                pageInfo {
                    hasNextPage
                    endCursor
                }
                nodes {
                    ... on Repository {
                        name
                        nameWithOwner
                        description
                        url
                        stargazerCount
                        forkCount
                        createdAt
                        updatedAt
                        primaryLanguage {
                            name
                        }
                        isArchived
                    }
                }
            }
        }
        """

        variables = {"query": query, "first": min(first, 100), "after": after}
        return self.execute_query(graphql_query, variables)

    def search_issues_prs(
        self,
        query: str,
        first: int = 100,
        after: Optional[str] = None,
        type: str = "ISSUE",
    ) -> Dict[str, Any]:
        """
        Search issues and pull requests.

        Args:
            query: Search query (e.g., "repo:owner/repo is:pr is:merged")
            first: Number of results (max 100)
            after: Cursor for pagination
            type: Search type (ISSUE or PULL_REQUEST)

        Returns:
            Search results with pagination info
        """
        graphql_query = f"""
        query($query: String!, $first: Int!, $after: String) {{
            search(query: $query, type: {type}, first: $first, after: $after) {{
                issueCount
                pageInfo {{
                    hasNextPage
                    endCursor
                }}
                nodes {{
                    ... on PullRequest {{
                        number
                        title
                        body
                        url
                        state
                        createdAt
                        updatedAt
                        mergedAt
                        closedAt
                        author {{
                            login
                        }}
                        labels(first: 10) {{
                            nodes {{
                                name
                            }}
                        }}
                        repository {{
                            nameWithOwner
                        }}
                    }}
                    ... on Issue {{
                        number
                        title
                        body
                        url
                        state
                        createdAt
                        updatedAt
                        closedAt
                        author {{
                            login
                        }}
                        labels(first: 10) {{
                            nodes {{
                                name
                            }}
                        }}
                        repository {{
                            nameWithOwner
                        }}
                    }}
                }}
            }}
        }}
        """

        variables = {"query": query, "first": min(first, 100), "after": after}
        return self.execute_query(graphql_query, variables)


def fetch_repos_bulk_with_details(
    client: RateLimitedClient,
    repo_names: List[str],
    include_languages: bool = True,
) -> List[Dict[str, Any]]:
    """
    Fetch repository details in bulk using GraphQL.

    This is the MOST efficient way to get repository data without hitting rate limits.
    GraphQL allows fetching multiple repos in a single request.

    Args:
        client: RateLimitedClient instance with multiple tokens
        repo_names: List of "owner/repo" names
        include_languages: Whether to include language breakdown

    Returns:
        List of repository data with all requested fields
    """
    # Filter out None values
    valid_repo_names = [r for r in repo_names if r]
    results = []
    batch_size = 50  # GraphQL allows up to ~50 repos per query

    for i in range(0, len(repo_names), batch_size):
        batch = repo_names[i : i + batch_size]

        # Build fragment for repository fields
        fields = [
            "name",
            "nameWithOwner",
            "description",
            "url",
            "stargazerCount",
            "forkCount",
            "createdAt",
            "updatedAt",
            "primaryLanguage { name }",
        ]

        if include_languages:
            fields.append("languages(first: 10) { nodes { name bytes } }")

        # Build the query with fragments
        fragments = []
        for j, repo in enumerate(batch):
            owner, name = repo.split("/")
            fragments.append(f"""
                repo{j}: repository(owner: "{owner}", name: "{name}") {{
                    ...RepoFields
                }}
            """)

        query = f"""
        query {{
            {chr(10).join(fragments)}
        }}
        
        fragment RepoFields on Repository {{
            {chr(10).join(fields)}
        }}
        """

        try:
            data = client.execute_graphql(query)

            for j, repo in enumerate(batch):
                repo_data = data.get(f"repo{j}")
                if repo_data:
                    results.append(repo_data)

            print(
                f"  Fetched batch {i // batch_size + 1}/{(len(repo_names) + batch_size - 1) // batch_size}"
            )

            # Brief pause between batches
            time.sleep(0.3)

        except Exception as e:
            print(f"  Error fetching batch {i // batch_size + 1}: {e}")
            # Fallback to individual requests
            for repo in batch:
                try:
                    owner, name = repo.split("/")
                    single_query = f"""
                    query($owner: String!, $name: String!) {{
                        repository(owner: $owner, name: $name) {{
                            {chr(10).join(fields)}
                        }}
                    }}
                    """
                    data = client.execute_graphql(
                        single_query, {"owner": owner, "name": name}
                    )
                    if data.get("repository"):
                        results.append(data["repository"])
                except Exception as e2:
                    print(f"    Failed to fetch {repo}: {e2}")

    return results


def fetch_all_repos_with_pagination(
    client: GitHubGraphQLClient, owner: str, max_repos: int = 1000
) -> List[Dict[str, Any]]:
    """
    Fetch all repositories for an owner with automatic pagination.

    Args:
        client: GraphQL client instance
        owner: Repository owner
        max_repos: Maximum number of repos to fetch

    Returns:
        List of repository data dictionaries
    """
    all_repos = []
    after = None
    batch_size = 100

    while len(all_repos) < max_repos:
        try:
            data = client.fetch_repositories(owner, first=batch_size, after=after)

            owner_data = data.get("repositoryOwner")
            if not owner_data:
                print(f"Owner '{owner}' not found or has no repositories")
                break

            repos = owner_data.get("repositories", {}).get("nodes", [])
            if not repos:
                break

            all_repos.extend(repos)
            print(f"Fetched {len(repos)} repos (total: {len(all_repos)})")

            # Check pagination
            page_info = owner_data.get("repositories", {}).get("pageInfo", {})
            if not page_info.get("hasNextPage"):
                break

            after = page_info.get("endCursor")

            # Rate limiting delay
            time.sleep(0.5)

        except Exception as e:
            print(f"Error fetching repos: {e}")
            break

    return all_repos[:max_repos]


def filter_repos_by_conditions(
    repos: List[Dict[str, Any]],
    min_forks: int = 0,
    min_prs: int = 0,
    language: Optional[str] = None,
    min_lang_percent: float = 0.0,
    client: Optional[RateLimitedClient] = None,
) -> List[Dict[str, Any]]:
    """
    Filter repositories by various conditions.

    This function uses GraphQL when possible to avoid rate limits.
    PR count and language percentage can be fetched in bulk.

    Args:
        repos: List of repository data dictionaries
        min_forks: Minimum number of forks
        min_prs: Minimum number of pull requests
        language: Target programming language for percentage check
        min_lang_percent: Minimum percentage of target language code
        client: Optional RateLimitedClient for efficient API calls

    Returns:
        Filtered list of repositories
    """
    filtered = []

    # Quick filters that can be done without extra API calls
    for repo in repos:
        if repo.get("forkCount", 0) < min_forks:
            continue
        filtered.append(repo)

    print(f"After fork filter: {len(filtered)} repos")

    # If no additional filtering needed, return early
    if min_prs <= 0 and (not language or min_lang_percent <= 0):
        return filtered

    # For language and PR filtering, use bulk GraphQL if client provided
    if client:
        # Extract repo names
        repo_names = [r.get("nameWithOwner") or r.get("full_name") for r in filtered]

        # Fetch languages in bulk
        detailed_repos = fetch_repos_bulk_with_details(
            client,
            repo_names,
            include_languages=bool(language and min_lang_percent > 0),
        )

        # Map back to original repos
        repo_map = {r.get("nameWithOwner") or r.get("full_name"): r for r in filtered}

        final_filtered = []
        for detailed in detailed_repos:
            name = detailed.get("nameWithOwner") or detailed.get("full_name")
            original = repo_map.get(name)
            if not original:
                continue

            # Check language percentage
            if language and min_lang_percent > 0:
                langs = detailed.get("languages", {}).get("nodes", [])
                total_bytes = sum(l.get("bytes", 0) for l in langs)
                if total_bytes > 0:
                    # Map common language names
                    lang_map = {
                        "c": "C",
                        "cpp": "C++",
                        "cs": "C#",
                        "javascript": "JavaScript",
                        "typescript": "TypeScript",
                        "python": "Python",
                        "java": "Java",
                        "go": "Go",
                        "ruby": "Ruby",
                        "rust": "Rust",
                    }
                    target_lang = lang_map.get(language.lower(), language)
                    target_bytes = next(
                        (
                            l.get("bytes", 0)
                            for l in langs
                            if l.get("name", "").lower() == target_lang.lower()
                        ),
                        0,
                    )
                    percent = (target_bytes / total_bytes) * 100
                    if percent < min_lang_percent:
                        continue

            final_filtered.append(original)

        return final_filtered

    # Fallback: sequential processing without client
    # This will hit rate limits faster!
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    for repo in filtered:
        full_name = repo.get("nameWithOwner") or repo.get("full_name")
        if not full_name:
            continue

        # Check language percentage if needed
        if language and min_lang_percent > 0:
            langs_url = f"{GITHUB_REST_URL}/repos/{full_name}/languages"
            try:
                resp = requests.get(langs_url, headers=headers)
                langs_data = resp.json()

                total_bytes = sum(langs_data.values())
                if total_bytes > 0:
                    lang_map = {
                        "c": "C",
                        "cpp": "C++",
                        "cs": "C#",
                        "javascript": "JavaScript",
                        "typescript": "TypeScript",
                        "python": "Python",
                        "java": "Java",
                        "go": "Go",
                        "ruby": "Ruby",
                        "rust": "Rust",
                    }
                    target_lang = lang_map.get(language.lower(), language)
                    target_bytes = langs_data.get(target_lang, 0)
                    percent = (target_bytes / total_bytes) * 100

                    if percent < min_lang_percent:
                        continue

            except Exception:
                pass

        filtered.append(repo)

    return filtered


def search_repos_with_conditions(
    client: GitHubGraphQLClient, query: str, max_results: int = 1000
) -> List[Dict[str, Any]]:
    """
    Search repositories using GraphQL with the provided query.

    Args:
        client: GraphQL client instance
        query: Search query (e.g., "language:python stars:>1000")
        max_results: Maximum number of results

    Returns:
        List of repository data dictionaries
    """
    all_results = []
    after = None
    batch_size = 100

    print(f"Searching repositories with query: {query}")

    while len(all_results) < max_results:
        try:
            data = client.search_repositories(query, first=batch_size, after=after)

            search_data = data.get("search", {})
            results = search_data.get("nodes", [])

            if not results:
                break

            all_results.extend(results)
            print(f"Fetched {len(results)} repos (total: {len(all_results)})")

            # Check pagination
            page_info = search_data.get("pageInfo", {})
            if not page_info.get("hasNextPage"):
                break

            after = page_info.get("endCursor")

            # Rate limiting delay
            time.sleep(0.5)

        except Exception as e:
            print(f"Error searching repos: {e}")
            break

    return all_results[:max_results]


def save_results(
    results: List[Dict[str, Any]], output_file: str, output_format: str = "jsonl"
) -> None:
    """
    Save results to a file.

    Args:
        results: List of result dictionaries
        output_file: Output file path
        output_format: Output format (jsonl or csv)
    """
    output_path = Path(output_file)

    if output_format == "csv" or str(output_file).endswith(".csv"):
        # Save as CSV matching the existing pipeline format
        with open(output_path, "w", newline="", encoding="utf-8-sig") as f:
            writer = csv.writer(f)
            writer.writerow(
                ["Rank", "Name", "Stars", "Forks", "Description", "URL", "Last Updated"]
            )
            for i, item in enumerate(results, 1):
                # Handle both GraphQL and REST API formats
                name = item.get("nameWithOwner") or item.get("full_name", "")
                stars = item.get("stargazerCount", 0) or item.get("stargazers_count", 0)
                forks = item.get("forkCount", 0) or item.get("forks_count", 0)
                desc = item.get("description", "") or ""
                url = item.get("url", "") or item.get("html_url", "")
                updated = item.get("updatedAt", "") or item.get("updated_at", "")

                writer.writerow([i, name, stars, forks, desc, url, updated])
        print(f"Saved {len(results)} results to {output_file}")
    else:
        # Default JSONL format
        with open(output_path, "w", encoding="utf-8") as f:
            for item in results:
                f.write(json.dumps(item, ensure_ascii=False) + "\n")
        print(f"Saved {len(results)} results to {output_file}")


def get_parser() -> argparse.ArgumentParser:
    """Create argument parser for command line usage."""
    parser = argparse.ArgumentParser(
        description="GitHub GraphQL API - Rate Limit Optimized",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Search with basic filters (efficient - single GraphQL query)
  python test_github_gql.py search --query "language:python stars:>100" --max 500
  
  # Search with multiple tokens for higher rate limits
  python test_github_gql.py search --query "language:python" --tokens tokens.txt --max 1000
  
  # Search with advanced filtering (requires extra API calls)
  python test_github_gql.py search --query "language:python" --min-stars 100 --min-prs 50 --min-lang-percent 70

Rate Limit Tips:
  - Use multiple tokens in a file (one per line) for 5x-10x more requests
  - Basic filters (stars, forks, language) are free in GraphQL search
  - Advanced filters (PR count, language %) require extra API calls
  - GraphQL is more efficient than REST for bulk data fetching
        """,
    )

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Repos command
    repos_parser = subparsers.add_parser(
        "repos", help="Fetch repositories for an owner"
    )
    repos_parser.add_argument("--owner", required=True, help="Repository owner")
    repos_parser.add_argument(
        "--max", type=int, default=1000, help="Maximum repos to fetch"
    )
    repos_parser.add_argument(
        "--output", type=str, default="repos.jsonl", help="Output file"
    )
    repos_parser.add_argument(
        "--tokens", type=str, nargs="*", default=None, help="Token file or tokens"
    )

    # Search command
    search_parser = subparsers.add_parser(
        "search", help="Search repositories with filters"
    )
    search_parser.add_argument(
        "--query",
        required=True,
        help="Search query (e.g., 'language:python stars:>1000')",
    )
    search_parser.add_argument("--max", type=int, default=1000, help="Maximum results")
    search_parser.add_argument(
        "--output",
        type=str,
        default="search.csv",
        help="Output file path (supports .csv or .jsonl)",
    )
    search_parser.add_argument(
        "--tokens",
        type=str,
        nargs="*",
        default=None,
        help="Token file or tokens (one per line for multiple tokens)",
    )

    # Filter options for search
    search_parser.add_argument(
        "--min-stars", type=int, default=0, help="Minimum star count"
    )
    search_parser.add_argument(
        "--min-forks", type=int, default=0, help="Minimum fork count"
    )
    search_parser.add_argument(
        "--language", type=str, default=None, help="Programming language for filtering"
    )
    search_parser.add_argument(
        "--min-prs",
        type=int,
        default=0,
        help="Minimum PR count (slower - extra API calls)",
    )
    search_parser.add_argument(
        "--min-lang-percent",
        type=float,
        default=0.0,
        help="Minimum % of target language (slower - extra API calls)",
    )

    # Bulk fetch command
    bulk_parser = subparsers.add_parser(
        "bulk", help="Bulk fetch repo details with multiple tokens"
    )
    bulk_parser.add_argument(
        "--input", required=True, help="Input file with repo names (one per line)"
    )
    bulk_parser.add_argument("--output", required=True, help="Output JSONL file")
    bulk_parser.add_argument(
        "--tokens", required=True, help="Token file (one token per line)"
    )
    bulk_parser.add_argument(
        "--include-langs", action="store_true", help="Include language breakdown"
    )
    bulk_parser.add_argument(
        "--min-stars", type=int, default=0, help="Filter by minimum stars"
    )
    bulk_parser.add_argument(
        "--min-forks", type=int, default=0, help="Filter by minimum forks"
    )

    return parser


def main():
    """Main entry point for command line usage."""
    parser = get_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    # Get tokens
    tokens = get_tokens(args.tokens)
    if not tokens:
        print("Error: No GitHub tokens provided")
        return

    print(f"Using {len(tokens)} token(s) for rate limit distribution")

    # Create rate-limited client for bulk operations
    rate_limited_client = RateLimitedClient(tokens)

    # Use single token for standard GraphQL client
    token = random.choice(tokens)
    client = GitHubGraphQLClient(token)

    # Detect output format from file extension
    def get_output_format(output_file: str) -> str:
        if output_file.endswith(".csv"):
            return "csv"
        return "jsonl"

    if args.command == "repos":
        print(f"Fetching repositories for owner: {args.owner}")
        repos = fetch_all_repos_with_pagination(client, args.owner, max_repos=args.max)
        save_results(repos, args.output, get_output_format(args.output))
        print(f"Total repos fetched: {len(repos)}")

    elif args.command == "search":
        print(f"Searching for: {args.query}")

        # Build query with basic filters
        query_parts = [args.query]
        if args.min_stars > 0 and "stars:" not in args.query:
            query_parts.append(f"stars:>={args.min_stars}")
        if args.min_forks > 0 and "forks:" not in args.query:
            query_parts.append(f"forks:>={args.min_forks}")
        if args.language and f"language:" not in args.query:
            query_parts.append(f"language:{args.language}")

        search_query = " ".join(query_parts)
        print(f"Effective query: {search_query}")

        # Search with basic filters
        repos = search_repos_with_conditions(
            client,
            search_query,
            max_results=args.max,
        )

        # Apply advanced filters if needed
        if args.min_prs > 0 or (args.language and args.min_lang_percent > 0):
            print(
                f"Applying advanced filters (min_prs={args.min_prs}, min_lang_percent={args.min_lang_percent}%)..."
            )
            repos = filter_repos_by_conditions(
                repos,
                min_forks=args.min_forks,
                min_prs=args.min_prs,
                language=args.language,
                min_lang_percent=args.min_lang_percent,
                client=rate_limited_client,
            )

        save_results(repos, args.output, get_output_format(args.output))
        print(f"Total repos fetched: {len(repos)}")

    elif args.command == "bulk":
        # Bulk fetch with rate limiting
        print(f"Bulk fetching repo details...")

        # Read repo names
        with open(args.input, "r") as f:
            repo_names = [line.strip() for line in f if line.strip()]

        print(f"Loaded {len(repo_names)} repositories")

        # Apply basic filters first
        if args.min_stars > 0 or args.min_forks > 0:
            print(f"Applying basic filters...")
            # Build query
            filter_parts = []
            if args.min_stars > 0:
                filter_parts.append(f"stars:>={args.min_stars}")
            if args.min_forks > 0:
                filter_parts.append(f"forks:>={args.min_forks}")
            filter_query = " ".join(filter_parts)
            print(f"Filter query: {filter_query}")

            repos = search_repos_with_conditions(
                client,
                filter_query,
                max_results=len(repo_names),
            )
            repo_names = [
                r.get("nameWithOwner") for r in repos if r.get("nameWithOwner")
            ]

        # Fetch details in bulk
        detailed_repos = fetch_repos_bulk_with_details(
            rate_limited_client,
            repo_names,
            include_languages=args.include_langs,
        )

        save_results(detailed_repos, args.output, get_output_format(args.output))
        print(f"Total repos with details: {len(detailed_repos)}")

        # Show rate limit status
        print("\nRate limit status:")
        for token_info, status in rate_limited_client.get_rate_limit_summary().items():
            print(
                f"  {token_info}: {status['remaining']}/{status['limit']} (resets at {status['reset_time']})"
            )

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
