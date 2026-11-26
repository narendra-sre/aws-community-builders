# Article 09 — AWS Systems Manager: Secure EC2 Management Without SSH

## Architecture

Administrator (AWS Console / CLI) → AWS Systems Manager → SSM Agent → Amazon EC2. The instance uses an IAM instance profile and a security group with no inbound rules.

## 1. Prerequisites

```bash
aws --version
terraform version
aws sts get-caller-identity
aws ec2 describe-vpcs --region ap-south-2 --query 'Vpcs[].{VpcId:VpcId,Default:IsDefault,CIDR:CidrBlock}' --output table
```

You need an existing default VPC/default subnet, permissions to create the project's EC2 and IAM resources, and the Session Manager plugin if using the AWS CLI to open sessions.

## 2. Configure

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Review the Region and instance type in `terraform/terraform.tfvars`. Check current pricing and availability before deploying.

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

Confirm the EC2 instance is running, its security group has no inbound rules, and the instance appears as an online managed node in Systems Manager. Registration can take several minutes.

## 5. Connect using Session Manager

```bash
INSTANCE_ID=$(terraform -chdir=terraform output -raw instance_id)
REGION=$(terraform -chdir=terraform output -raw aws_region)
aws ssm start-session --target "$INSTANCE_ID" --region "$REGION"
```

The AWS CLI Session Manager plugin is required for CLI sessions. Alternatively, start the session from the Systems Manager console.

## 6. Run a remote command

```bash
INSTANCE_ID=$(terraform -chdir=terraform output -raw instance_id)
REGION=$(terraform -chdir=terraform output -raw aws_region)

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["hostname","whoami","uname -a","df -h"]' \
  --region "$REGION" \
  --query 'Command.CommandId' --output text)

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"
```

## 7. Patch Manager scan

Start with a scan, not an install:

```bash
INSTANCE_ID=$(terraform -chdir=terraform output -raw instance_id)
REGION=$(terraform -chdir=terraform output -raw aws_region)

aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunPatchBaseline" \
  --parameters 'Operation=["Scan"]' \
  --region "$REGION"
```

Check the command invocation and Patch Manager compliance view after the scan completes.

## 8. Evidence

Save genuine screenshots under `evidence/screenshots/`: Terraform plan/apply, state and outputs, EC2 instance profile, security group ingress showing no rules, managed node Online, Session Manager shell, Run Command result, Patch Manager scan if performed, and cleanup. Redact account IDs and sensitive details.

## 9. Cleanup

```bash
./scripts/destroy.sh
```

Review the destroy plan and type `DESTROY`. Verify that the EC2 instance, IAM resources, and security group have been removed.

## Cost notes

EC2 runtime and EBS storage can incur charges. This starter project uses a public subnet and public IP for outbound connectivity and does not create NAT Gateways or VPC interface endpoints. Review current AWS pricing and clean up promptly.
