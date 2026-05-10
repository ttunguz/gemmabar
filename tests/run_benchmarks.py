import argparse
import time
import json
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

def worker(url, model, prompt, max_tokens, worker_id):
    payload = {
        "model": model,
        "stream": True,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}]
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
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
        print(f"Worker {worker_id} failed: {e}")
        return None
        
    duration = time.time() - start_time
    
    if ttft is None:
        ttft = duration
        
    return {
        "ttft": ttft,
        "tokens": tokens,
        "duration": duration,
        "throughput": tokens / duration if duration > 0 else 0
    }

def run_benchmark(host, port, model, concurrency, prompt, max_tokens, input_multiplier=1):
    url = f"http://{host}:{port}/v1/chat/completions"
    
    # Scale the prompt depending on the input multiplier to test long context
    actual_prompt = (prompt + " ") * input_multiplier
    
    print(f"=========================================")
    print(f" SwiftLM Serve Normal Benchmark System")
    print(f"=========================================")
    print(f" Model       : {model}")
    print(f" Concurrency : {concurrency}")
    print(f" Endpoint    : {url}")
    print(f" Max Tokens  : {max_tokens}")
    print(f" Input Multi : {input_multiplier} (Approx ~{15 * input_multiplier} words)")
    print(f"=========================================\n")
    print("Running...")
    
    start_time = time.time()
    
    results = []
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = {executor.submit(worker, url, model, actual_prompt, max_tokens, i): i for i in range(concurrency)}
        for future in as_completed(futures):
            res = future.result()
            if res is not None:
                results.append(res)
                
    duration = time.time() - start_time
    
    if not results:
        print("All workers failed.")
        return
        
    total_tokens = sum(r['tokens'] for r in results)
    ttft_values = [r['ttft'] for r in results]
    tps_values = [r['throughput'] for r in results]
    
    avg_ttft = sum(ttft_values) / len(ttft_values)
    avg_tps = sum(tps_values) / len(tps_values)
    
    print(f"=========================================")
    print(f" ✅ Results")
    print(f"=========================================")
    print(f" Total Tokens       : {total_tokens}")
    print(f" Wall Clock Time    : {duration:.2f}s")
    print(f" Aggregate TPS      : {total_tokens / duration:.2f} tok/s")
    print(f" Average Worker TTFT: {avg_ttft:.2f}s")
    print(f" Average Worker TPS : {avg_tps:.2f} tok/s")
    print(f"=========================================\n")
    
    result_json = {
        "model": model,
        "concurrency": concurrency,
        "total_tokens": total_tokens,
        "duration": duration,
        "aggregate_tps": total_tokens / duration,
        "avg_ttft": avg_ttft,
        "avg_worker_tps": avg_tps,
        "workers": results
    }
    
    with open("benchmark_results.json", "w") as f:
        json.dump(result_json, f, indent=2)
        
    print("Results saved to benchmark_results.json")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5413)
    parser.add_argument("--model", required=True)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--max-tokens", type=int, default=200)
    parser.add_argument("--input-multiplier", type=int, default=1, help="Multiplier for the text prompt length to stress the TTFT performance.")
    args = parser.parse_args()
    
    prompt = "Write a detailed technical explanation of how Mixture of Experts models work, covering routing mechanisms, expert selection, load balancing, and memory efficiency. Be thorough."
    
    run_benchmark(args.host, args.port, args.model, args.concurrency, prompt, args.max_tokens, args.input_multiplier)

if __name__ == "__main__":
    main()
