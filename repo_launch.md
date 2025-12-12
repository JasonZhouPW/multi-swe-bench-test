# call repo launch

## 1. run gen_repolaunch.sh

```bash
./gen_repolaunch.sh <org> <repo> <instance_id> <language>
```

## 2. run repo launch
set env:
```
export OPENAI_BASE_URL=https://ark.cn-beijing.volces.com/api/v3 #defaut for Alibaba replace with your own openai base url
export OPENAI_API_KEY=<your own openai api key>
export TAVILY_API_KEY=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
```


github repo : https://github.com/microsoft/RepoLaunch
```bash
python -m launch.run --config-path <repo_launch_config_path> 
```

repo_launch_config:
```json
{
    "mode": {
        "setup": true,
        "organize": true
    },
    "llm_provider_name": "OpenAI",
    "model_config": {        
        "model_name": "llama3.1:8b", // you own model name for example:qwen3-max
        "temperature": 0.0
    },
    "workspace_root": "data/examples/",
    "dataset": "data/examples/dataset.jsonl",
    "print_to_console": false,
    "first_N_repos": -1,
    "overwrite": false,
    "max_workers": 5,
    "os": "linux",
    "max_trials": 2,
    "max_steps_setup": 60,
    "max_steps_verify": 20,
    "max_steps_organize": 30,
    "timeout": 60,
    "image_prefix": "repolaunch/dev"
}
```

output: dataset.jsonl example:
```
{"repo":"FlowiseAI/Flowise","instance_id":"1212113","base_commit":"d090b715c8f138ee887d5a2b1795cee40e5f4b37","create_at":"2025-12-12T03:49:43Z","language":"javascript"}

```