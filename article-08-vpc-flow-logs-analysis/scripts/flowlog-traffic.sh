#!/bin/bash

exec > /var/log/flowlog-traffic.log 2>&1

echo "Starting VPC Flow Logs traffic generation"

for i in $(seq 1 30); do
    echo "Iteration: $i"
    date

    echo "DNS request"
    getent hosts example.com || true

    echo "Allowed HTTPS request"
    curl -sS --connect-timeout 5 \
      -o /dev/null \
      -w "HTTPS status: %{http_code}\n" \
      https://example.com || true

    echo "Rejected HTTP request"
    curl -sS --connect-timeout 3 \
      -o /dev/null \
      http://example.com || true

    echo "Rejected TCP port 4444 request"
    timeout 3 bash -c 'echo test > /dev/tcp/1.1.1.1/4444' || true

    sleep 10
done

echo "Traffic generation completed"
