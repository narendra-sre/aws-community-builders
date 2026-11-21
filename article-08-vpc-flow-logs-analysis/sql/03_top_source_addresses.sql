SELECT srcaddr, COUNT(*) AS flow_records,
       SUM(packets) AS total_packets, SUM(bytes) AS total_bytes
FROM vpc_flow_logs
WHERE log_status = 'OK'
GROUP BY srcaddr
ORDER BY total_bytes DESC
LIMIT 20;
