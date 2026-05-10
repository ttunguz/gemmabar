import subprocess
import time
import urllib.request
import json
import random
import os

model = "mlx-community/gemma-4-26b-a4b-it-4bit"
port = 5442

print("Downloading realistic 100K text (War and Peace / Project Gutenberg)...")
try:
    # War and Peace is roughly 500k words. We'll grab just enough for ~100k tokens.
    req = urllib.request.Request("https://www.gutenberg.org/files/2600/2600-0.txt")
    with urllib.request.urlopen(req) as response:
        corpus = response.read().decode('utf-8')
except Exception as e:
    print(f"Failed to download book: {e}")
    # Fallback to realistic repeating sentences instead of single word "test"
    base_sentence = "The little bird flew across the vast blue sky, searching for a place to rest its weary wings among the towering oak trees. "
    corpus = base_sentence * 7000

# Select exactly 75,000 words (~100,000 tokens)
words = corpus.split()
WORDS_REQUIRED = 80000
if len(words) > WORDS_REQUIRED:
    words = words[1000:WORDS_REQUIRED+1000] # skip header
else:
    # If too short, multiply it
    multiplier = (WORDS_REQUIRED // len(words)) + 1
    words = (words * multiplier)[:WORDS_REQUIRED]

# Needle in a Haystack (Passkey) logic
# We insert a specific, random passkey at a random depth
passkey = random.randint(10000, 99999)
needle = f"\n\n### IMPORTANT ###\nThe secret passkey for the underground base is: {passkey}. Remember this number.\n### IMPORTANT ###\n\n"

# Insert needle at 70% depth
insert_idx = int(len(words) * 0.70)
words.insert(insert_idx, needle)

haystack_text = " ".join(words)
prompt_text = f"Read the following text. Hidden within it is a secret passkey for an underground base.\n\n{haystack_text}\n\nQuestion: What is the secret passkey for the underground base? Please reply with JUST the number."

server_cmd = [
    ".build/release/SwiftLM", 
    "--model", model,
    "--port", str(port),
    "--turbo-kv"
]

print(f"\n======================================")
print(f"Benchmarking Realistic NIAH Test: {model}")
print(f"Context size: ~{WORDS_REQUIRED} words / 100K tokens")
print(f"Needle: {passkey} (Hidden at 70% depth)")
print(f"======================================")

server_proc = subprocess.Popen(server_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Wait for server
loaded = False
for i in range(2000):
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/health", method="GET")
        with urllib.request.urlopen(req) as response:
            if response.status == 200:
                loaded = True
                break
    except:
        time.sleep(1.0)
        
if not loaded:
    print("Failed to start server")
    exit(1)

print(f"Model loaded. Submitting 100K Needle-in-a-Haystack prompt...")
time.sleep(2)

payload = {
    "model": model,
    "stream": False,
    "max_tokens": 15,
    "messages": [{"role": "user", "content": prompt_text}]
}

start_time = time.time()
try:
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=1200) as response:
        duration = time.time() - start_time
        data = json.loads(response.read().decode('utf-8'))
        answer = data['choices'][0]['message']['content'].strip()
        print(f"\nTime to process 100K context + generate answer: {duration:.2f}s")
        print(f"Model output: {answer}")
        if str(passkey) in answer:
            print("✅ PASS: The model successfully found the passkey!")
        else:
            print("❌ FAIL: The model generated output, but missed the passkey.")
except Exception as e:
    print(f"Generation failed: {e}")

server_proc.terminate()
