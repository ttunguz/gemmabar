import subprocess
import time
import urllib.request
import json
import sys
import os

models = [
    "mlx-community/gemma-4-e4b-it-8bit",
    "mlx-community/gemma-4-26b-a4b-it-4bit",
    "mlx-community/gemma-4-31b-it-4bit"
]

port = 5430
prompt_text = "Please write a story about a little bird. " + ("test " * 100)
results = []

for idx, model in enumerate(models):
    print(f"\n======================================")
    print(f"[{idx+1}/4] Benchmarking: {model}")
    print(f"======================================")
    
    server_cmd = [
        ".build/release/SwiftLM", 
        "--model", model,
        "--port", str(port),
        "--prefill-size", "512"
    ]
    
    with open("benchmark_server.log", "w") as log_file:
        server_proc = subprocess.Popen(server_cmd, stdout=log_file, stderr=subprocess.STDOUT)
    
    # Wait for server to load the model (allow up to 20 mins for HUGE downloads)
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
        
    print(f"Model {model} loaded. Starting generation...")
    time.sleep(2) # Stabilize memory
    
    # Fire off evaluation
    payload = {
        "model": model,
        "stream": True,
        "max_tokens": 20,
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
        with urllib.request.urlopen(req) as response:
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

print("\n\n=== FINAL MARKDOWN TABLE ===")
print("| Model | Time To First Token (s) | Generation Speed (tok/s) | Peak GPU Memory (GB) |")
print("|---|---|---|---|")
for r in results:
    print(f"| `{r['Model']}` | {r['TTFT (s)']}s | {r['TPS']} tok/s | {r['Peak Mem (GB)']} GB |")
