#!/bin/bash
model=${1:-"mlx-community/gemma-4-e4b-it-8bit"}
port1=5415
port2=5416

echo "=========================================================="
echo " TurboQuant TTFT Isolation Benchmark"
echo " Model: $model"
echo " Context Strategy: Target 2,000+ Input Tokens"
echo "=========================================================="

# 1. Warm-up and Standard Setup (No TurboKV)
echo "Starting Standard Server (No TurboKV) on port $port1..."
.build/debug/SwiftLM --model $model --port $port1 > test_standard.log 2>&1 &
SERVER1_PID=$!

sleep 15
echo "Running Standard Benchmark..."
python3 tests/run_benchmarks.py --port $port1 --model $model --concurrency 1 --max-tokens 50 --input-multiplier 70

kill $SERVER1_PID
wait $SERVER1_PID 2>/dev/null

# 2. TurboKV Setup
echo ""
echo "Starting TurboQuant Server (--turbo-kv) on port $port2..."
.build/debug/SwiftLM --model $model --port $port2 --turbo-kv > test_turbo.log 2>&1 &
SERVER2_PID=$!

sleep 15
echo "Running TurboQuant Benchmark..."
python3 tests/run_benchmarks.py --port $port2 --model $model --concurrency 1 --max-tokens 50 --input-multiplier 70

kill $SERVER2_PID
wait $SERVER2_PID 2>/dev/null

echo "=========================================================="
echo " Done. Check the output above to compare Average Worker TTFT."
