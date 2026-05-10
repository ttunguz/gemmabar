import subprocess
import time
import urllib.request
import json
import os

models = [
    "mlx-community/gemma-4-e4b-it-8bit",
    "mlx-community/gemma-4-26b-a4b-it-4bit",
    "mlx-community/gemma-4-31b-it-4bit"
]

port = 5440
# 1 word ~ 1.3 tokens. "test " repeated 80,000 times gives ~100k tokens.
prompt_text = "Please write a story about a little bird. " + ("test " * 80000)
results = []

print("==========================================================")
print(f" 🚀 EXTREME CONTEXT ISOLATION (100K TOKENS) MATRIX")
print("==========================================================\n")

for idx, model in enumerate(models):
    print(f"\n======================================")
    print(f"[{idx+1}/3] Benchmarking: {model}")
    print(f"======================================")
    
    # Enable turbo-kv for extreme context
    server_cmd = [
        ".build/release/SwiftLM", 
        "--model", model,
        "--port", str(port),
        "--turbo-kv"
    ]
    
    with open("benchmark_100k_server.log", "w") as log_file:
        server_proc = subprocess.Popen(server_cmd, stdout=log_file, stderr=subprocess.STDOUT)
    
    # Wait for server to load the model
    loaded = False
    for i in range(1200):
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{port}/health", method="GET")
            with urllib.request.urlopen(req) as response:
                if response.status == 200:
                    loaded = True
                    break
        except:
            time.sleep(1.0)
            
    if not loaded:
        print(f"Error: Server failed to start for {model}")
        server_proc.terminate()
        server_proc.wait()
        continue
        
    print(f"Model {model} loaded. Submitting 100K context...")
    time.sleep(2) # Stabilize memory
    
    # Fire off evaluation
    payload = {
        "model": model,
        "stream": True,
        "max_tokens": 10,
        "messages": [{"role": "user", "content": prompt_text}]
    }
    
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method="POST"
    )
    
    start_time = time.time()
    ttft = None
    tokens = 0
    
    try:
        # This blocks until the first byte arrives (prefill duration)
        with urllib.request.urlopen(req, timeout=1200) as response:
            for line in response:
                line = line.decode('utf-8').strip()
                if not line or line == "data: [DONE]":
                    continue
                if line.startswith("data: "):
                    data_str = line[6:]
                    try:
                        data = json.loads(data_str)
                        if data.get('choices') and data['choices'][0]['delta'].get('content'):
                            if ttft is None:
                                ttft = time.time() - start_time
                                print(f"  -> First Token received in {ttft:.2f}s!")
                            tokens += 1
                    except json.JSONDecodeError:
                        continue
    except Exception as e:
        print(f"Generation failed: {e}")
        
    duration = time.time() - start_time
    if ttft is None:
        ttft = duration
        
    # Get peak memory
    peak_gb = 0
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/health", method="GET")
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            peak_mb = data.get("memory", {}).get("peak_mb", 0)
            peak_gb = peak_mb / 1024.0
    except Exception as e:
        print(f"Failed to fetch memory: {e}")
        
    # Teardown
    server_proc.terminate()
    try:
        server_proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        server_proc.kill()
        
    tps = tokens / (duration - ttft) if (duration - ttft) > 0 and tokens > 1 else 0
    print(f"--- Results for {model} ---")
    print(f"TTFT: {ttft:.2f}s | TPS: {tps:.2f} tok/s | Peak RAM: {peak_gb:.2f} GB | Tokens: {tokens}")
    
    results.append({
        "Model": model.split("/")[-1],
        "TTFT (s)": round(ttft, 2),
        "TPS": round(tps, 2),
        "Peak Mem (GB)": round(peak_gb, 2)
    })

print("\n\n=== FINAL 100K CONTEXT MARKDOWN TABLE ===")
print("| Model | 100K Time To First Token | Generation Speed | Peak GPU Memory (w/ TurboKV) |")
print("|---|---|---|---|")
for r in results:
    print(f"| `{r['Model']}` | {r['TTFT (s)']}s | {r['TPS']} tok/s | {r['Peak Mem (GB)']} GB |")
