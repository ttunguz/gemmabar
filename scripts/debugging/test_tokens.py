from transformers import AutoTokenizer

tok = AutoTokenizer.from_pretrained("mlx-community/gemma-4-26b-a4b-it-4bit")
messages = [{"role": "user", "content": "What is 2+2?"}]
prompt = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
tokens = tok.encode(prompt)
print("PROMPT:", repr(prompt))
print("TOKENS:", len(tokens), tokens)
