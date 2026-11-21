# Article 08: Analyzing AWS Network Traffic Using VPC Flow Logs and Amazon Athena

This hands-on project captures VPC network traffic metadata with Amazon VPC Flow Logs, stores the records in Amazon S3, and analyzes them with Amazon Athena using SQL.

## Architecture
Existing VPC → VPC Flow Logs → private S3 bucket → Amazon Athena → SQL analysis.

## What it provisions
- S3 bucket with encryption and public-access blocking.
- Bucket policy for the VPC Flow Logs delivery service.
- VPC Flow Log configured for ALL traffic in an existing VPC.
- Athena workgroup and a named query to create the external table.

No EC2 instances, VPCs, subnets, NAT gateways, or internet gateways are created.

## Prerequisites
AWS CLI v2, Terraform >= 1.6, an existing VPC, and permissions for S3, EC2 Flow Logs, and Athena.

See README.md for deployment, verification, queries, evidence, and cleanup.

## Important
Flow Logs capture metadata, not packet payloads. They do not generate traffic. If the selected VPC has no active interfaces or traffic during the capture window, no records may appear. Delivery is best-effort and can take several minutes.

S3 storage, Flow Logs delivery, and Athena data scanned may incur charges. Keep the test window short and clean up after capturing evidence.

## Implementation status
This repository contains Terraform, SQL examples, and helper scripts. Deployment and query results must be generated and verified in your own AWS account. Do not claim successful results until you have captured genuine evidence.
