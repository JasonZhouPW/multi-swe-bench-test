from dotenv import load_dotenv
load_dotenv()

import asyncio
import massgen

result = asyncio.run(massgen.run(
    query="What is machine learning?",
    # models=["openai/ministral-3:8b"],
    config="./config.yaml",
    enable_filesystem=True,
))
print(result["final_answer"])  # Consensus answer from winning agent