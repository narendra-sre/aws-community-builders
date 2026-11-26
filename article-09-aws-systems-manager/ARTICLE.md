## Introduction

Managing Amazon EC2 instances securely is an important part of operating workloads on AWS. Traditional SSH-based administration often requires inbound port 22 access, key-pair distribution, and additional controls to manage administrator access across environments.

AWS Systems Manager provides centralized operational capabilities for managing EC2 instances and other supported resources. Its Session Manager capability allows administrators to open interactive sessions without configuring inbound SSH access or managing SSH keys for the session.

In this project, I use Terraform to provision an Amazon Linux 2023 EC2 instance, an IAM instance profile for Systems Manager, and a security group with no inbound rules. I then use Systems Manager Session Manager to access the instance, Run Command to execute remote Linux commands, and Patch Manager to perform a patch-compliance scan.

The objective is to demonstrate a practical alternative to SSH-based instance administration while understanding the IAM and network requirements behind Systems Manager.

> **Cost notice:** This project creates AWS resources and can incur charges. Potential costs include EC2 runtime, EBS storage, data transfer, and any optional logging or networking resources. Review current pricing for your Region and account before deploying. Keep the test window short and remove resources after collecting evidence.

## 1. Architecture

```text
          Administrator
        AWS Console / CLI
                |
                v
       AWS Systems Manager
       Session Manager /
         Run Command
                ^
                |
       Outbound HTTPS channel
                |
             SSM Agent
                |
                v
          Amazon EC2
       Amazon Linux 2023
       (No inbound rules)

       IAM instance profile
       AmazonSSMManagedInstanceCore
```

The workflow is:

1. Provision an EC2 instance and its IAM instance profile.
2. Attach the AWS-managed `AmazonSSMManagedInstanceCore` policy to the instance role.
3. Configure a security group with no inbound rules.
4. Confirm that the SSM Agent registers the instance as a managed node.
5. Open an interactive shell using Session Manager.
6. Execute remote Linux diagnostics using Run Command.
7. Optionally run a Patch Manager scan and review the compliance result.

The starter implementation uses an existing default VPC and a default subnet in the selected Region. It assigns a public IP to the instance to provide straightforward outbound connectivity for this learning lab. The public IP is not used for inbound SSH access. No NAT Gateway or VPC interface endpoints are created.

## 2. AWS services and components used

| Service / component | Purpose |
|---|---|
| Amazon EC2 | Hosts the Amazon Linux managed node. |
| AWS Systems Manager | Provides centralized instance management capabilities. |
| SSM Agent | Runs on the instance and communicates with Systems Manager. |
| AWS IAM | Controls the permissions granted to the EC2 instance and administrator. |
| IAM instance profile | Delivers the instance role credentials to EC2. |
| Amazon VPC | Provides the network environment for the instance. |
| Terraform | Provisions the AWS resources used by the project. |

## 3. How Session Manager works

Session Manager does not require an inbound SSH connection. The SSM Agent on the instance establishes outbound communication with Systems Manager. An authorized administrator requests a session through the AWS Console or AWS CLI, and Systems Manager brokers the session.

Two separate permission areas matter:

- **Instance permissions:** The EC2 instance needs an IAM role with the permissions required by SSM Agent. This project attaches `AmazonSSMManagedInstanceCore`.
- **Administrator permissions:** The human or role starting a session needs appropriate Systems Manager permissions, such as permissions to start and terminate sessions and access the target managed node.

The instance also needs network connectivity to the Systems Manager endpoints over HTTPS (TCP 443). In private-subnet production designs, this can be provided using VPC interface endpoints or another approved outbound path.

## 4. Repository structure

```text
article-09-aws-systems-manager/
├── ARTICLE.md
├── README.md
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── scripts/
│   ├── deploy.sh
│   ├── verify.sh
│   └── destroy.sh
├── images/
│   └── cover-image.png
└── evidence/
    ├── README.md
    ├── results/
    └── screenshots/
```

## 5. Prerequisites

Before starting, make sure you have:

- An AWS account and an IAM identity authorized to create the resources in this project.
- AWS CLI v2 configured with the intended profile and Region.
- Terraform CLI version 1.6 or later.
- An existing default VPC and at least one default subnet in the selected Region.
- A Linux shell. The commands in this walkthrough use Ubuntu on WSL2.
- The AWS Session Manager plugin installed if you plan to start sessions from the AWS CLI.
- Permission for the administrator identity to use Systems Manager Session Manager and Run Command.

Check the tools and AWS identity:

```bash
aws --version
terraform version
aws sts get-caller-identity
aws configure get region
```

Use the same AWS profile and Region consistently for Terraform, AWS CLI, and the Systems Manager console.

## 6. Configure the project

Clone or extract the project and move into its directory:

```bash
cd article-09-aws-systems-manager
```

Create the Terraform variables file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Review `terraform/terraform.tfvars`. The example uses `ap-south-2` and `t3.micro`; confirm instance-type availability and current pricing in your Region before deployment.

Do not commit `terraform.tfvars`, AWS credentials, Terraform state files, or account-specific secrets to a public repository.

## 7. Review and deploy with Terraform

Make the helper scripts executable:

```bash
chmod +x scripts/*.sh
```

Format, initialize, and validate the configuration:

```bash
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform init
terraform -chdir=terraform validate
```

Review the proposed changes:

```bash
terraform -chdir=terraform plan
```

Then run the deployment helper:

```bash
./scripts/deploy.sh
```

The helper displays a Terraform plan and requires the explicit confirmation `APPLY` before creating resources. Review the plan and verify that it references the intended Region and expected resources before approving it.

## 8. Verify the EC2 instance and security group

Run:

```bash
./scripts/verify.sh
```

The script reports the EC2 instance state, security group ingress permissions, and Systems Manager managed-node information.

Confirm that:

- The EC2 instance reaches the `running` state.
- The expected IAM instance profile is attached.
- The security group has no inbound permissions.
- The instance eventually appears in Systems Manager as an online managed node.

SSM registration may take several minutes after instance launch. If the node is not listed immediately, check the instance role, SSM Agent status, and outbound network connectivity before changing the configuration.

## 9. Connect using Session Manager

Retrieve the instance ID and Region:

```bash
INSTANCE_ID="$(terraform -chdir=terraform output -raw instance_id)"
REGION="$(terraform -chdir=terraform output -raw aws_region)"
```

Start a session:

```bash
aws ssm start-session --target "$INSTANCE_ID" --region "$REGION"
```

The AWS CLI Session Manager plugin is required for CLI-based sessions. You can also start a session from the Systems Manager console by selecting the managed node and choosing the Session Manager connection option.

After connecting, run a few basic checks:

```bash
whoami
hostname
uname -a
df -h
```

This confirms that an interactive shell is available through Systems Manager without adding an inbound SSH rule.

## 10. Execute commands using Run Command

Run Command allows an authorized operator to execute commands on one or more managed nodes without opening an interactive shell.

The following example runs basic Linux diagnostics:

```bash
INSTANCE_ID="$(terraform -chdir=terraform output -raw instance_id)"
REGION="$(terraform -chdir=terraform output -raw aws_region)"

COMMAND_ID="$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["hostname","whoami","uname -a","df -h"]' \
  --region "$REGION" \
  --query 'Command.CommandId' \
  --output text)"

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION"
```

Check the command status and standard output. Command execution is asynchronous, so the invocation may need a short time to reach a terminal status.

## 11. Explore Patch Manager

Patch Manager helps assess and manage operating-system patch compliance for supported managed nodes.

For the initial lab, run a patch **scan** rather than installing updates:

```bash
INSTANCE_ID="$(terraform -chdir=terraform output -raw instance_id)"
REGION="$(terraform -chdir=terraform output -raw aws_region)"

aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunPatchBaseline" \
  --parameters 'Operation=["Scan"]' \
  --region "$REGION"
```

Check the command invocation and the Patch Manager compliance view in Systems Manager. Patch scan results depend on the operating system, configured package repositories, patch baseline, and the time needed for the scan to complete.

This project demonstrates a scan only. It does not automatically install patches or schedule a maintenance window.

## 12. Operational considerations and limitations

- **No inbound SSH:** The security group intentionally has no ingress rules. Do not add port 22 just to make Session Manager work.
- **Outbound connectivity:** The instance must reach the required Systems Manager endpoints over HTTPS. A running SSM Agent and correct IAM role are not sufficient if network connectivity is blocked.
- **Two permission layers:** The instance role authorizes the agent; the administrator's IAM identity must separately be allowed to start sessions or send commands.
- **Agent health:** If the managed node is missing or offline, check SSM Agent status and logs, instance role attachment, credentials, DNS, routes, and outbound HTTPS connectivity.
- **Private subnet design:** A production private-subnet implementation can use Systems Manager VPC interface endpoints. Endpoint security groups must allow inbound TCP 443 from the managed instances, and private DNS should be configured as appropriate.
- **Session logging:** This starter project does not configure session logging to S3 or CloudWatch Logs. Add the required destinations and permissions if audit retention is part of the requirement.
- **Patch results:** A patch scan does not guarantee that every patch can be installed. Review the baseline, package sources, and compliance details.
- **Cost:** EC2 runtime and EBS storage can incur charges. Review pricing and clean up promptly.

## 13. Evidence checklist

Save genuine screenshots under `evidence/screenshots/`:

1. Terraform plan and apply completion.
2. Terraform state list and outputs.
3. EC2 instance details showing the instance profile.
4. Security group inbound rules showing no rules.
5. Systems Manager managed node showing Online.
6. Successful Session Manager terminal.
7. Run Command invocation and output.
8. Patch Manager scan result or compliance view, if completed.
9. Terraform destroy completion.

Redact account IDs, public IP addresses, email addresses, and other sensitive information before publishing.

## 14. Cleanup

After collecting the screenshots and command results, review the destroy plan and remove the resources created by this project:

```bash
./scripts/destroy.sh
```

The helper requires you to type `DESTROY` after reviewing the plan. Verify in the AWS Console that the EC2 instance, IAM instance profile and role, and security group have been removed.

## Conclusion

This project demonstrates how AWS Systems Manager can provide centralized EC2 administration without relying on inbound SSH access. Session Manager provides interactive access, Run Command supports remote operational tasks, and Patch Manager provides a way to assess patch compliance.

The key operational lesson is that secure remote management depends on more than an attached IAM role. The managed node needs a healthy SSM Agent, correct instance permissions, working outbound connectivity, and an administrator identity authorized to perform the requested action.

## References

- [AWS Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html)
- [Setting up Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started.html)
- [AmazonSSMManagedInstanceCore policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html)
- [Systems Manager VPC endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [Running commands using Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html)
- [Patch Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html)

**Project repository:** AWS Community Builder Repository
