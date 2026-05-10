import subprocess
import time
import sys
import json
import os

model = "google/gemma-4-26b-moe" 
if len(sys.argv) > 1:
    model = sys.argv[1]

configs = [
    ("No-Turbo_No-SSD", []),
    ("No-Turbo_With-SSD", ["--stream-experts"]),
    ("With-Turbo_No-SSD", ["--turbo-kv"]),
    ("With-Turbo_With-SSD", ["--turbo-kv", "--stream-experts"])
]

print("Starting matrix benchmark for", model)

all_results = {}

for i, (name, flags) in enumerate(configs):
    print(f"\n=== Running Configuration: {name} ===")
    
    port = str(5413 + i)
    server_cmd = [".build/debug/SwiftLM", "--model", model, "--port", port] + flags
    print(f"Starting server: {' '.join(server_cmd)}")
    
    # We dump stderr to a log file so we can debug if it fails
    with open("server_matrix_test.log", "w") as log_file:
        server_proc = subprocess.Popen(server_cmd, stdout=log_file, stderr=subprocess.STDOUT)
    
    # Give the server time to download and load weights
    time.sleep(20) 
    
    if server_proc.poll() is not None:
        print("Error: Server crashed before benchmarking could begin!")
        with open("server_matrix_test.log", "r") as f:
            print("Server logs:")
            print(f.read()[-1000:]) # print last 1000 chars
        continue
    
    try:
        bench_cmd = [sys.executable, "tests/run_benchmarks.py", "--port", port, "--model", model, "--concurrency", "4", "--max-tokens", "200"]
        print(f"Running benchmark script...")
        
        bench_proc = subprocess.run(bench_cmd, capture_output=True, text=True)
        print(bench_proc.stdout)
        if bench_proc.stderr:
            print("Benchmark Stderr:", bench_proc.stderr)
        
        if os.path.exists("benchmark_results.json"):
            with open("benchmark_results.json") as f:
                res = json.load(f)
                avg_ttft = res.get("avg_ttft", 0)
                agg_tps = res.get("aggregate_tps", 0)
                all_results[name] = {"avg_ttft": avg_ttft, "aggregate_tps": agg_tps}
            os.rename("benchmark_results.json", f"benchmark_{name}.json")
        else:
            print("Failed to produce benchmark_results.json")
            
    finally:
        print("Terminating server...")
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_proc.kill()
        time.sleep(5)

print("\n=== MATRIX RESULTS SUMMARY ===")
if not all_results:
    print("No results collected.")
else:
    for name, metrics in all_results.items():
        print(f"{name.ljust(25)}: TTFT {metrics['avg_ttft']:.2f}s | TPS {metrics['aggregate_tps']:.2f}")

