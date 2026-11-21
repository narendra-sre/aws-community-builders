SELECT interface_id, srcaddr, dstaddr, srcport, dstport,
       protocol, packets, bytes, action, log_status
FROM vpc_flow_logs
WHERE action = 'REJECT'
ORDER BY start_time DESC
LIMIT 100;
