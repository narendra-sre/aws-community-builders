SELECT dstport, protocol, action,
       COUNT(*) AS flow_records, SUM(bytes) AS total_bytes
FROM vpc_flow_logs
WHERE log_status = 'OK'
GROUP BY dstport, protocol, action
ORDER BY flow_records DESC
LIMIT 30;
