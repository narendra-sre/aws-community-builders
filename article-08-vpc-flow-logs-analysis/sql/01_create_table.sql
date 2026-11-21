CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
  version int, account_id string, interface_id string, srcaddr string,
  dstaddr string, srcport int, dstport int, protocol bigint,
  packets bigint, bytes bigint, start_time bigint, end_time bigint,
  action string, log_status string
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ' '
STORED AS TEXTFILE
LOCATION 's3://__FLOW_LOGS_BUCKET__/AWSLogs/';
