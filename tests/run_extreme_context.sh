#!/bin/bash
model=${1:-"mlx-community/gemma-4-e4b-it-8bit"}

# Base prompt is ~40 tokens.
# 20k tokens ≈ multiplier 500
# 100k tokens ≈ multiplier 2500

for multiplier in 500 2500; do
    tokens=$((multiplier * 40))
    echo ""
    echo "=========================================================="
    echo " 🚀 EXTREME CONTEXT ISOLATION "
    echo " Targeting: ~${tokens} Input Tokens (Multiplier: ${multiplier})"
    echo "=========================================================="

    port1=5417
    port2=5418

    echo "[1/2] Standard Context Loading (No TurboKV)..."
    .build/debug/SwiftLM --model $model --port $port1 > test_standard_extreme.log 2>&1 &
    SERVER1_PID=$!
    sleep 15
    python3 tests/run_benchmarks.py --port $port1 --model $model --concurrency 1 --max-tokens 5 --input-multiplier $multiplier
    kill $SERVER1_PID
    wait $SERVER1_PID 2>/dev/null

    echo ""
    echo "[2/2] TurboQuant Acceleration (--turbo-kv)..."
    .build/debug/SwiftLM --model $model --port $port2 --turbo-kv > test_turbo_extreme.log 2>&1 &
    SERVER2_PID=$!
    sleep 15
    python3 tests/run_benchmarks.py --port $port2 --model $model --concurrency 1 --max-tokens 5 --input-multiplier $multiplier
    kill $SERVER2_PID
    wait $SERVER2_PID 2>/dev/null
    
    echo "=========================================================="
done
echo "All extreme context tests completed."
