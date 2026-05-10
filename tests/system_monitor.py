import time
import subprocess
import re
import platform
from datetime import datetime

def get_apple_gpu_usage():
    if platform.system() != "darwin" or platform.machine().lower() not in ["arm64", "aarch64"]:
        return "N/A"
        
    try:
        res = subprocess.run(
            "ioreg -r -c AGXAccelerator | grep -o '\"Device Utilization %\"=[0-9]*' | cut -d= -f2 | head -n 1",
            shell=True, capture_output=True, text=True, timeout=5
        )
        val = res.stdout.strip()
        if val.isdigit():
            return f"{val}%"
            
        res2 = subprocess.run(
            "ioreg -r -c IOAccelerator -d 1 | grep -o '\"Device Utilization[^\"\"]*\"[^=]*=[0-9]*' | cut -d= -f2 | head -n 1",
            shell=True, capture_output=True, text=True, timeout=5
        )
        val2 = res2.stdout.strip()
        if val2.replace(" ", "").isdigit():
            return f"{val2.replace(' ', '')}%"
    except Exception:
        pass
        
    return "N/A"

def get_cpu_and_ram():
    cpu_pct = "0.0"
    ram_gb = "0.0"
    try:
        # Get CPU using top
        top_res = subprocess.run(["top", "-l", "1", "-n", "0"], capture_output=True, text=True)
        cpu_match = re.search(r'CPU usage:\s*([\d.]+)', top_res.stdout)
        if cpu_match:
            cpu_pct = f"{float(cpu_match.group(1)):04.1f}"
            
        # Get RAM using vm_stat (pages are 4096 bytes or 16384 bytes, let's get page size)
        pagesize_res = subprocess.run(["pagesize"], capture_output=True, text=True)
        pagesize = int(pagesize_res.stdout.strip())
        
        vm_res = subprocess.run(["vm_stat"], capture_output=True, text=True)
        # sum active + wired + compressed
        active = int(re.search(r'Pages active:\s*(\d+)', vm_res.stdout).group(1))
        wired = int(re.search(r'Pages wired down:\s*(\d+)', vm_res.stdout).group(1))
        compressed = int(re.search(r'Pages occupied by compressor:\s*(\d+)', vm_res.stdout).group(1))
        
        used_bytes = (active + wired + compressed) * pagesize
        ram_gb = f"{used_bytes / (1024**3):05.2f}"
    except Exception:
        pass
        
    return cpu_pct, ram_gb

def monitor():
    print("Timestamp | CPU % | RAM (GB) | GPU % (Apple)")
    print("-" * 55)
    
    while True:
        timestamp = datetime.now().strftime("%H:%M:%S")
        cpu_pct, ram_gb = get_cpu_and_ram()
        gpu_pct = get_apple_gpu_usage()
        
        print(f"{timestamp} | CPU: {cpu_pct}% | RAM_GB: {ram_gb} | GPU: {gpu_pct}", flush=True)
        time.sleep(2)

if __name__ == "__main__":
    monitor()
