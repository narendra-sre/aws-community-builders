## Introduction

Understanding what is happening inside a VPC is an important part of operating and troubleshooting workloads on AWS. When an application cannot connect to another service, a security group rule appears to be blocking traffic, or an unexpected network connection is suspected, engineers need evidence about the traffic that was accepted or rejected.

Amazon VPC Flow Logs provide network traffic metadata for network interfaces in a VPC, subnet, or individual network interface. The records can be delivered to Amazon S3 and queried with Amazon Athena, allowing engineers to investigate traffic patterns using SQL without deploying a separate log-processing cluster.

In this project, I used Terraform to configure VPC Flow Logs for an existing VPC, delivered the records to a private S3 bucket, and used Athena to query the captured traffic. I also generated test network activity so that the log pipeline could be validated with actual records.

The goal is not to capture packet contents. Flow Logs provide metadata about IP traffic, such as source and destination addresses, ports, protocol, packet and byte counts, and whether the traffic was accepted or rejected.

> **Cost notice:** This project creates AWS resources and can incur charges. Potential costs include S3 storage and requests, VPC Flow Logs delivery, Athena queries, and any temporary EC2 test instance. Review current pricing for your Region and account before deploying. Keep the test window short and remove temporary resources after collecting evidence.

## 1. Architecture

```text
                 Existing Amazon VPC
                         |
                         v
                  VPC Flow Logs
                         |
                         v
             Private Amazon S3 bucket
                         |
                         v
                  Amazon Athena
                         |
                         v
                  SQL analysis
```


The workflow is:

1. Select an existing VPC to monitor.
2. Enable VPC Flow Logs for all traffic (`ALL`).
3. Deliver the generated log files to an encrypted S3 bucket.
4. Define an external table in Athena that maps the Flow Logs fields to columns.
5. Run SQL queries to investigate rejected traffic, source addresses, and destination ports.

The project uses an existing VPC. It does not create a new VPC, subnet, NAT gateway, or internet gateway.

## 2. AWS services used

| Service | Purpose |
|---|---|
| Amazon VPC Flow Logs | Collects metadata about IP traffic entering and leaving the selected VPC network interfaces. |
| Amazon S3 | Stores the compressed Flow Logs files. |
| AWS Identity and Access Management (IAM) | Controls the permissions required for Flow Logs delivery and access to the log bucket. |
| Amazon Athena | Runs SQL queries directly against the data stored in S3. |
| AWS Glue Data Catalog | Stores the Athena table metadata used to interpret the log files. |
| Terraform | Provisions the AWS resources used by the project. |

## 3. What Terraform provisions

The Terraform configuration creates the following resources:

- An S3 bucket dedicated to Flow Logs.
- S3 public-access-block settings.
- S3 bucket ownership controls.
- Server-side encryption for objects stored in the bucket.
- A bucket policy that permits the VPC Flow Logs delivery service to write log objects.
- A VPC Flow Log configured for `ALL` traffic on the selected existing VPC.
- An Athena workgroup with a dedicated S3 query-results location.
- A named Athena query containing the external-table definition.

The selected VPC and its networking resources are not modified by this Terraform configuration.

A temporary EC2 instance can be used to generate traffic during the test. That workload is a validation step, not part of the baseline Terraform deployment. If you create one, use a dedicated test security group and remove the instance and security group when testing is complete.

## 4. Repository structure

```text
article-08-vpc-flow-logs-analysis/
├── ARTICLE.md
├── README.md
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── sql/
│   ├── 01_create_table.sql
│   ├── 02_rejected_traffic.sql
│   ├── 03_top_source_addresses.sql
│   └── 04_destination_ports.sql
├── scripts/
│   ├── deploy.sh
│   ├── verify.sh
│   ├── run-query.sh
│   └── destroy.sh
├── images/
└── evidence/
    ├── README.md
    ├── results/
    └── screenshots/
```

## 5. Prerequisites

Before starting, make sure you have:

- An AWS account and an IAM identity with permissions to manage the resources in this project.
- AWS CLI v2 configured with the intended profile and Region.
- Terraform CLI version 1.6 or later.
- An existing VPC in the Region selected for the deployment.
- A Linux shell. The commands in this walkthrough use Ubuntu on WSL2.
- Basic familiarity with S3, VPC networking, Terraform, and SQL.

Check the tools and AWS identity:

```bash
aws --version
terraform version
aws sts get-caller-identity
aws configure get region
```

Use the same AWS profile and Region consistently for Terraform, AWS CLI, and the Athena console.

## 6. Configure the project

Clone or extract the project and move into its directory:

```bash
cd article-08-vpc-flow-logs-analysis
```

Create the Terraform variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` and provide the existing VPC ID and the required project settings.

For example:

```hcl
region = "ap-south-2"
vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
```

Use your own VPC ID. Do not commit `terraform.tfvars`, AWS credentials, Terraform state files, or account-specific secrets to a public repository.

## 7. Review and deploy with Terraform

Format and validate the configuration:

```bash
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform init
terraform -chdir=terraform validate
```

Review the proposed changes:

```bash
terraform -chdir=terraform plan
```

Check that the plan refers to the intended VPC and only contains the resources expected for this project. Then run the deployment helper:

```bash
./scripts/deploy.sh
```

The helper displays the Terraform plan and requires an explicit confirmation before applying it. Review the plan before approving it.


The deployment outputs include the Flow Logs bucket name, Flow Log ID, Athena workgroup name, and selected VPC ID.

## 8. Verify VPC Flow Logs

Check the Flow Log configuration:

```bash
aws ec2 describe-flow-logs \
  --region ap-south-2 \
  --query 'FlowLogs[].{Id:FlowLogId,Status:FlowLogStatus,Delivery:DeliverLogsStatus,Traffic:TrafficType,Destination:LogDestination}' \
  --output table
```

Confirm that:

- The Flow Log exists for the intended VPC.
- The Flow Log status is `ACTIVE`.
- The traffic type is `ALL`.
- The destination points to the project's S3 bucket.
- The delivery status does not report an error.

The `ACTIVE` state confirms that the Flow Log is configured. It does not mean that log files will appear immediately. Flow Logs are not a traffic generator; records are produced only when there is traffic on monitored network interfaces.


## 9. Generate test network traffic

For a useful demonstration, generate some traffic in the selected VPC. A small temporary EC2 instance can make DNS and HTTPS requests and attempt connections that the test security group does not permit.

Use a dedicated test instance and security group. Do not modify a production security group or use production workloads for this experiment.

Example traffic-generation commands to run on a test Linux instance:

```bash
# DNS lookup
getent hosts example.com

# HTTPS request
curl -I --connect-timeout 5 https://example.com

# Example connection attempt to a port that should not be allowed
timeout 3 bash -c 'echo test > /dev/tcp/1.1.1.1/4444'
```

The outcome of a connection attempt depends on the destination, routing, network ACLs, security group rules, and the remote endpoint. A failed client command by itself does not prove that the VPC Flow Logs record will have an `REJECT` action. Validate the resulting Flow Logs records.

Allow time for Flow Logs to be delivered. Delivery is not instantaneous, and the service publishes log files on a best-effort basis.


## 10. Confirm that log files reached Amazon S3

List the objects in the Flow Logs bucket:

```bash
aws s3 ls s3://YOUR_FLOW_LOGS_BUCKET/AWSLogs/ --recursive
```

Replace `YOUR_FLOW_LOGS_BUCKET` with the bucket name from the Terraform output.

The objects are stored under an account- and Region-specific prefix. Flow Logs files are compressed, and their names include information such as the account, Region, Flow Log ID, and delivery time.

To inspect a delivered object locally:

```bash
aws s3 cp s3://YOUR_FLOW_LOGS_BUCKET/PATH_TO_LOG_FILE.log.gz .
gzip -dc PATH_TO_LOG_FILE.log.gz | head
```

Replace the bucket and object path with an actual object from your S3 listing.

At this point, the important validation is that actual `.log.gz` objects exist in the expected Flow Logs prefix. An empty bucket immediately after enabling Flow Logs is not sufficient evidence of a failure; first check that the VPC has active network interfaces and that traffic has occurred, then allow time for delivery.


## 11. Create the Athena table

Open the Amazon Athena console in the same AWS Region used for the Flow Logs deployment.

Configure the query editor:

- Data source: `AwsDataCatalog`
- Database: `default`
- Workgroup: `article08-flowlogs-workgroup` (or the workgroup name returned by Terraform)
- Query result location: the S3 query-results prefix configured for the workgroup

The default VPC Flow Logs format contains fields such as version, account ID, interface ID, source and destination addresses, source and destination ports, protocol, packet count, byte count, start and end times, action, and log status.

Create an external table that maps those fields:

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
  version int,
  account_id string,
  interface_id string,
  srcaddr string,
  dstaddr string,
  srcport int,
  dstport int,
  protocol bigint,
  packets bigint,
  bytes bigint,
  start_time bigint,
  end_time bigint,
  action string,
  log_status string
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ' '
STORED AS TEXTFILE
LOCATION 's3://YOUR_FLOW_LOGS_BUCKET/AWSLogs/';
```

Replace `YOUR_FLOW_LOGS_BUCKET` with the actual bucket name. The table location must point to the prefix containing the delivered Flow Logs files.

Run the statement, then confirm that the table exists:

```sql
SHOW TABLES;
```

Inspect the columns:

```sql
DESCRIBE vpc_flow_logs;
```


## 12. Analyze rejected traffic

A useful first investigation is to identify records where the action is `REJECT`.

```sql
SELECT
    interface_id,
    srcaddr,
    dstaddr,
    srcport,
    dstport,
    protocol,
    packets,
    bytes,
    action,
    log_status
FROM vpc_flow_logs
WHERE action = 'REJECT'
ORDER BY start_time DESC
LIMIT 100;
```

This query can help identify traffic that was rejected by the network controls represented in the Flow Logs record.

When reviewing the results, look for:

- Source and destination addresses.
- Destination ports and protocol.
- The network interface associated with the record.
- Whether the record action is `REJECT`.
- Whether the log status is `OK`.

A query returning no rows is a valid observation, not a result to invent or hide. It may mean that no rejected traffic was captured in the selected time range, or that the test did not produce the expected rejected flow. Confirm that log files exist, check the capture window, and generate a controlled test if needed.


## 13. Identify top source addresses

The next query groups records by source address and ranks them by the number of bytes observed:

```sql
SELECT
    srcaddr,
    COUNT(*) AS flow_records,
    SUM(packets) AS total_packets,
    SUM(bytes) AS total_bytes
FROM vpc_flow_logs
WHERE log_status = 'OK'
GROUP BY srcaddr
ORDER BY total_bytes DESC
LIMIT 20;
```

This gives a basic view of which source addresses account for the largest amount of traffic in the captured data.

Keep in mind that Flow Logs contain records for network flows, not application-level requests. A high byte count does not automatically indicate malicious activity. Correlate unusual results with workload ownership, expected traffic patterns, security controls, and other monitoring data.


## 14. Analyze destination ports

Grouping records by destination port, protocol, and action can help identify common network communication patterns:

```sql
SELECT
    dstport,
    protocol,
    action,
    COUNT(*) AS flow_records,
    SUM(bytes) AS total_bytes
FROM vpc_flow_logs
WHERE log_status = 'OK'
GROUP BY dstport, protocol, action
ORDER BY flow_records DESC
LIMIT 30;
```

Use the results to investigate:

- Frequently used destination ports.
- Whether traffic on a port was accepted or rejected.
- Differences between TCP, UDP, and other IP protocols.
- Unexpected ports that may deserve further investigation.

Port numbers alone do not identify the application with certainty. Interpret them in the context of the workload and the rest of the network architecture.


## 15. Operational considerations and limitations

- **Flow Logs are metadata, not packet capture.** They do not include packet payloads or application request contents.
- **Flow Logs do not create traffic.** A quiet VPC or an interface with no traffic may produce no useful records during the test window.
- **Delivery is best-effort and delayed.** Do not expect every record to appear immediately after enabling the Flow Log.
- **Interpret `REJECT` carefully.** A rejected record indicates that traffic was rejected by the relevant network controls; it does not, by itself, identify the exact root cause.
- **Check `log_status`.** Values such as `OK`, `NODATA`, and `SKIPDATA` have different meanings. Filter or interpret them deliberately.
- **Use a bounded query scope.** Athena charges based on the amount of data scanned. Avoid repeatedly scanning a large prefix, and consider partitioning or a more selective layout for larger environments.
- **Protect the log destination.** Keep S3 Block Public Access enabled, use encryption, and grant only the required principals access.
- **Treat test workloads as temporary.** Remove the test EC2 instance and its dedicated security group after collecting evidence.
- **Do not publish secrets.** Redact account IDs, public IP addresses, email addresses, credentials, and other sensitive values from screenshots where appropriate.

For a production deployment, consider a deliberate partitioning strategy, lifecycle policies for log retention, query-cost controls, centralized logging, and alerting based on validated traffic patterns.

## 16. Cleanup

After collecting the screenshots and query evidence, remove the temporary test workload and its dedicated security group. Verify that the instance is terminated before removing its security group.

Then review the Terraform destroy plan and remove the resources created by this project:

```bash
./scripts/destroy.sh
```

The project's S3 bucket is configured for destructive cleanup. Its contents, including delivered Flow Logs and Athena query results stored there, may be deleted when the bucket is destroyed. Download or preserve the evidence you need before cleanup.


## Conclusion

This project demonstrates a practical way to collect VPC network traffic metadata and investigate it with SQL. VPC Flow Logs provide visibility into accepted and rejected traffic, S3 provides durable object storage for the records, and Athena makes it possible to query the data without managing a separate analytics cluster.

The key lesson is that enabling Flow Logs is only the first step. A useful investigation also requires generating or observing real traffic, confirming that log files were delivered, validating the Athena table schema, and interpreting query results in the context of the network design.

## References

- [Amazon VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [Publish Flow Logs to Amazon S3](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-s3.html)
- [Querying VPC Flow Logs with Amazon Athena](https://docs.aws.amazon.com/athena/latest/ug/vpc-flow-logs.html)
- [Amazon Athena pricing](https://aws.amazon.com/athena/pricing/)
- [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/)

**Project repository:** AWS Community Builder Repository
