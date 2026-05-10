#!/bin/bash
echo "Timestamp | CPU % | RAM (GB) | GPU % (Apple)"
echo "-------------------------------------------------"

while true; do
  ts=$(date "+%H:%M:%S")
  
  # CPU
  cpu=$(top -l 1 -n 0 | awk '/^CPU usage:/ {print $3}' | tr -d '%')
  if [ -z "$cpu" ]; then cpu="0.0"; fi
  
  # RAM
  pagesize=$(pagesize)
  vm_stat_out=$(vm_stat)
  active=$(echo "$vm_stat_out" | grep "Pages active:" | awk '{print $3}' | tr -d '.')
  wired=$(echo "$vm_stat_out" | grep "Pages wired down:" | awk '{print $4}' | tr -d '.')
  compressor=$(echo "$vm_stat_out" | grep "Pages occupied by compressor:" | awk '{print $5}' | tr -d '.')
  used_bytes=$(( (active + wired + compressor) * pagesize ))
  ram_gb=$(echo "scale=2; $used_bytes / 1073741824" | bc)
  
  # GPU
  gpu=$(ioreg -r -c AGXAccelerator | grep -o '\"Device Utilization %\"=[0-9]*' | cut -d= -f2 | head -n 1)
  if [ -z "$gpu" ]; then
    gpu=$(ioreg -r -c IOAccelerator -d 1 | grep -o '\"Device Utilization[^\"\"]*\"[^=]*=[0-9]*' | cut -d= -f2 | head -n 1)
  fi
  
  if [ -z "$gpu" ]; then
    gpu_fmt="N/A"
  else
    gpu_fmt="${gpu}%"
  fi
  
  echo "$ts | CPU: ${cpu}% | RAM_GB: $ram_gb | GPU: $gpu_fmt"
  sleep 2
done
