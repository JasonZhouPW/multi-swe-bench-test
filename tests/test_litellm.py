import litellm
import os

model_name = "doubao-seed-1-8-251228"
api_base = "https://ark.cn-beijing.volces.com/api/v3"
api_key = "ce3589eb-dde9-467f-8609-e5d84b8993e9"

# Try with openai/ prefix
try:
    print(f"Testing with openai/{model_name}...")
    response = litellm.completion(
        model=f"openai/{model_name}",
        messages=[{"role": "user", "content": "hi"}],
        api_base=api_base,
        api_key=api_key,
    )
    print("Success with openai/ prefix!")
    print(response.choices[0].message.content)
except Exception as e:
    print(f"Failed with openai/ prefix: {e}")

# Try with volcengine/ prefix
try:
    print(f"\nTesting with volcengine/{model_name}...")
    response = litellm.completion(
        model=f"volcengine/{model_name}",
        messages=[{"role": "user", "content": "hi"}],
        api_base=api_base,
        api_key=api_key,
    )
    print("Success with volcengine/ prefix!")
    print(response.choices[0].message.content)
except Exception as e:
    print(f"Failed with volcengine/ prefix: {e}")
