# Article 04: Event-Driven AWS Security Guardrails with Terraform

An event-driven guardrail that blocks two common causes of cloud exposure as they happen:

1. Security group rules that open SSH (22) or RDP (3389) to `0.0.0.0/0` or `::/0`.
2. S3 bucket public access blocks that are deleted or weakened.

CloudTrail management events flow through EventBridge into a Lambda remediator. The remediator is idempotent, runs in dry-run mode by default, honors an exemption tag, records every decision in DynamoDB, alerts through SNS, and sends failed events to an SQS dead-letter queue.

## Architecture

See `ARTICLE.md` for the full design. In short:

```
API call -> CloudTrail -> EventBridge rule -> Lambda remediator -> DynamoDB (audit)
                                                              -> SNS (email alert)
                              retries exhausted -> SQS dead-letter queue
```

## Repository layout

```
ARTICLE.md                 Article draft for AWS Builder Center
README.md                  This file
.gitignore                 Excludes state, variable files, and build output
evidence/                  Sanitized outputs and screenshots from the run
images/                    Architecture diagram and cover image
scripts/
  simulate-violations.sh   Creates the three test scenarios
  capture-evidence.sh      Saves sanitized outputs into evidence/
  cleanup.sh               Removes test resources and destroys the stack
terraform/
  versions.tf              Provider versions
  provider.tf              Region and default tags
  variables.tf             Inputs (region, alert email, dry-run, ports, exempt tag)
  main.tf                  All resources
  outputs.tf               Names used by scripts and evidence capture
  terraform.tfvars.example Template for your variables
  lambda/handler.py        Remediator code
```

## Prerequisites

* Terraform 1.6 or later
* AWS CLI v2, configured for an account on the AWS Free Tier
* Python is not needed locally; the Lambda runtime is Python 3.12
* A default VPC in the target region (present in most accounts; check with `aws ec2 describe-vpcs --filters Name=isDefault,Values=true`)
* Permission to create EC2 security groups, S3 buckets, IAM roles, Lambda, EventBridge rules, DynamoDB, SNS, and SQS

## Run it

Run these from the project root unless noted.

```bash
# 1. Configure variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars and set alert_email

# 2. Deploy in dry-run mode (the default)
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
cd ..
```

Open the confirmation email from AWS SNS and click the subscription link. Alerts will not arrive until you confirm it.

```bash
# 3. Trigger the scenarios (dry-run: nothing should change)
./scripts/simulate-violations.sh

# 4. Check the dry-run results
#    - Alert email should show would_revoke and would_restore records.
#    - The security group in scenario 1 should still allow 0.0.0.0/0 on port 22.
#    - Scenario 2 (exempt) should produce no alert.

# 5. Enforce: flip the switch and apply
cd terraform
terraform apply -var="dry_run=false" -auto-approve
cd ..

# 6. Run the scenarios again and confirm enforcement
./scripts/simulate-violations.sh

# 7. Capture sanitized evidence into evidence/
./scripts/capture-evidence.sh
```

Before you commit anything, check every file in `evidence/` for account IDs, email addresses, and ARNs that you do not want public. The capture script replaces the account ID, but other values may still need review.

## Tear down

```bash
./scripts/cleanup.sh
```

This deletes the test security groups and buckets, then runs `terraform destroy`. Run it when you finish, so nothing keeps running.

## Cost notes

Everything here is designed for the Free Tier. Avoided on purpose: AWS Config, Security Hub, customer-managed KMS keys, and VPC endpoints. Log retention is 14 days. The DLQ retains messages for 14 days, the maximum. Check the Billing dashboard after your first run.

## Known limitations

* Detection covers new API calls only. Existing exposure needs a one-time sweep.
* Bucket policies and ACLs are not covered; only the public access block is.
* The S3 IAM statement is account-wide; narrowing it is future work.
* The exemption tag is only as trustworthy as the permission to write tags.
* Revocation takes seconds, so a Service Control Policy should be layered on in production to prevent some calls outright.
