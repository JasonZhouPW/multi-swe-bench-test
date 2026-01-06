import requests
import json

def get_merged_pulls(owner, repo, token, keyword=None, search_scope="all"):
    """
    Fetches all merged pull requests for a given repository with optional keyword search.
    
    owner: GitHub username or organization name
    repo: Repository name
    token: GitHub Personal Access Token
    keyword: Optional keyword for fuzzy search
    search_scope: Where to search - "all", "title", "body", "comments"
    """
    
    # Base query components
    base_query_parts = [f"repo:{owner}/{repo}", "is:pr", "is:merged"]
    
    # Add keyword search if provided
    if keyword:
        if search_scope == "title":
            base_query_parts.append(f'in:{search_scope} "{keyword}"')
        elif search_scope == "body":
            base_query_parts.append(f'in:{search_scope} "{keyword}"')
        elif search_scope == "comments":
            base_query_parts.append(f'in:{search_scope} "{keyword}"')
        else:  # search in all fields
            base_query_parts.append(f'"{keyword}"')
    
    # Join all query parts
    query = " ".join(base_query_parts)
    url = f"https://api.github.com/search/issues?q={query}&sort=updated&order=desc"
    
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json"
    }
    
    merged_pulls = []
    
    while url:
        response = requests.get(url, headers=headers)
        response.raise_for_status() # Raise an exception for bad status codes
        
        data = response.json()
        merged_pulls.extend(data['items'])
        
        # Check for the 'next' link in the pagination headers
        url = None
        if 'next' in response.links:
            url = response.links['next']['url']
            
    return merged_pulls

# Example usage with keyword fuzzy search
if __name__ == "__main__":
    try:
        # Example 1: Search without keyword (get all merged PRs)
        print("=== Example 1: Get all merged PRs ===")
        tk = "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"
        pull_requests = get_merged_pulls("fatedier", "frp", tk)
        print(f"Found {len(pull_requests)} merged pull requests.")
        
        # Example 2: Search with keyword "fix" in title
        print("\n=== Example 2: Search keyword 'fix' in title ===")
        pull_requests_fix = get_merged_pulls(
            "fatedier", "frp", tk,
            keyword="fix", search_scope="title"
        )
        print(f"Found {len(pull_requests_fix)} PRs with 'fix' in title.")
        for pr in pull_requests_fix[:3]:  # Show first 3
            print(f"PR #{pr['number']}: {pr['title']}")
        
        # Example 3: Search with keyword "bug" in all fields
        print("\n=== Example 3: Search keyword 'bug' in all fields ===")
        pull_requests_bug = get_merged_pulls(
            "fatedier", "frp", tk,
            keyword="bug", search_scope="all"
        )
        print(f"Found {len(pull_requests_bug)} PRs with 'bug' keyword.")
        for pr in pull_requests_bug[:3]:  # Show first 3
            print(f"PR #{pr['number']}: {pr['title']}")
            
        # Example 4: Search with multiple keywords
        print("\n=== Example 4: Search with multiple keywords ===")
        query_with_multiple = get_merged_pulls(
            "fatedier", "frp", tk,
            keyword="memory leak", search_scope="body"
        )
        print(f"Found {len(query_with_multiple)} PRs with 'memory leak' in body.")
        
    except requests.exceptions.HTTPError as e:
        print(f"Error fetching PRs: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
