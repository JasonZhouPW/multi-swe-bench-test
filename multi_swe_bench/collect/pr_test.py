import requests
import json

def get_merged_pulls(owner, repo, token):
    """
    Fetches all merged pull requests for a given repository.
    
    owner: GitHub username or organization name
    repo: Repository name
    token: GitHub Personal Access Token
    """
    
    # Use the Search API for more robust filtering
    # The 'is:pr is:merged' query finds pull requests that have been merged
    query = f"repo:{owner}/{repo} is:pr is:merged merged:>=2025-01-01 fix"
    url = f"https://api.github.com/search/issues?q={query}&sort=updated&order=desc"
    
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json"
    }
    
    merged_pulls = []
    page = 1
    
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

# Example usage (replace with your details)
# owner = "TheAlgorithms"
# repo = "Python"
# # !! Replace with your actual PAT (keep it secure)
# github_token = "YOUR_PERSONAL_ACCESS_TOKEN" 




if __name__ == "__main__":
    try:
        pull_requests = get_merged_pulls("fatedier", "frp", "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")

        print(f"Found {len(pull_requests)} merged pull requests.")
        for pr in pull_requests: # Print first 5
            # print("pr:", pr)
            print(f"PR #{pr['number']}: {pr['title']} (Merged at: {pr['pull_request']['merged_at']})")
    except requests.exceptions.HTTPError as e:
        print(f"Error fetching PRs: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
