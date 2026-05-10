#!/bin/bash
model="mlx-community/gemma-4-e4b-it-8bit"
echo "Starting server for $model..."
.build/debug/SwiftLM --model $model --port 5414 > test_server.log 2>&1 &
SERVER_PID=$!

echo "Waiting for server to load and download weights if necessary..."
# Wait up to 5 minutes for download/load
for i in {1..150}; do
    if grep -q "Server running" test_server.log || grep -q "Server listening" test_server.log || grep -q "started" test_server.log || grep -q "binding" test_server.log; then
        echo "Server is up!"
        sleep 5 # Warmup wait
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Server crashed!"
        tail -n 20 test_server.log
        exit 1
    fi
    sleep 2
done

echo "Running benchmark script..."
python3 tests/run_benchmarks.py --port 5414 --model $model --concurrency 1 --max-tokens 100

echo "Shutting down server..."
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "Done."
