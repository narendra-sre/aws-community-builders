# Article 08 — VPC Flow Logs + S3 + Athena

## Architecture
Existing VPC → VPC Flow Logs (ALL) → private S3 bucket → Athena workgroup → SQL queries.

## 1. Prerequisites
```bash
aws --version
terraform version
aws sts get-caller-identity
aws ec2 describe-vpcs --region ap-south-2 --query 'Vpcs[].{VpcId:VpcId,Default:IsDefault,CIDR:CidrBlock}' --output table
```
Choose an existing VPC you are authorized to monitor. A VPC with active network interfaces and workloads is needed to produce useful records.

## 2. Configure
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```
Edit `terraform/terraform.tfvars` and set your real VPC ID.

## 3. Plan and deploy
```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
```
Review the plan and type `APPLY` only if it is correct.

## 4. Verify
```bash
./scripts/verify.sh
terraform -chdir=terraform state list
terraform -chdir=terraform output
```
Confirm FlowLogStatus is ACTIVE.

## 5. Wait for log delivery
```bash
BUCKET=$(terraform -chdir=terraform output -raw flow_logs_bucket_name)
aws s3 ls s3://$BUCKET/AWSLogs/ --recursive | head -30
```
Allow several minutes. If no objects appear, confirm the VPC has interfaces and observed traffic, the flow log is ACTIVE, and delivery has no reported errors.

## 6. Create Athena table
Run:
```bash
./scripts/run-query.sh sql/01_create_table.sql
```

## 7. Analyze traffic
```bash
./scripts/run-query.sh sql/02_rejected_traffic.sql
./scripts/run-query.sh sql/03_top_source_addresses.sql
./scripts/run-query.sh sql/04_destination_ports.sql
```
The table is `default.vpc_flow_logs`. Empty results can simply mean no matching records were delivered during the observation window.

## 8. Evidence
Save genuine screenshots under `evidence/screenshots/`: Terraform plan/apply, state and outputs, S3 encryption and public-access block, Flow Log ACTIVE status, delivered S3 objects, Athena table creation, and query results. Redact account IDs and sensitive IP addresses.

## 9. Cleanup
```bash
./scripts/destroy.sh
```
The bucket is configured with `force_destroy = true`, so Terraform destroy deletes its contents too. Save any evidence you need first. Verify in the console that the bucket, Flow Log, and Athena workgroup are removed.

## Cost notes
S3 storage, Flow Logs delivery, and Athena scans can incur charges. This project does not create compute instances or NAT gateways. Keep queries small and clean up promptly.
