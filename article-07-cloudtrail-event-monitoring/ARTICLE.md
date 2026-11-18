# Detecting AWS Security Group Changes with CloudTrail, EventBridge, and SNS

## Introduction

Security group rules control network access to AWS resources. An unexpected ingress or egress change can expose a workload or interrupt a service. Detecting these changes quickly is an important part of cloud operations and security monitoring.

This project builds an event-driven notification workflow using AWS CloudTrail management events, Amazon EventBridge, and Amazon SNS. When a security group rule is authorized or revoked, EventBridge matches the corresponding API event and sends a notification to an SNS topic.

Terraform provisions the notification components and a dedicated test security group. A controlled test adds and removes an SSH ingress rule from the documentation-only TEST-NET-1 range (`203.0.113.0/24`); it does not open access from a real public client network.

> **Cost notice:** This project creates AWS resources. SNS requests and other account activity may incur charges. Review current AWS pricing and your account billing before deployment. This project does not promise zero cost.

## Implementation status

- Terraform configuration and event-driven notification resources are provided.
- Deployment, verification, controlled test, and cleanup scripts are included.
- Run the project in your own AWS account and capture genuine deployment and notification evidence before publishing implementation results.

## 1. Architecture

```text
EC2 security group API activity
             |
             v
CloudTrail management event
             |
             v
Amazon EventBridge rule
             |
             v
Amazon SNS topic
             |
             v
Confirmed email subscription
```

[IMAGE PLACEHOLDER — Insert `images/architecture.svg`.]

EventBridge receives AWS service events delivered through CloudTrail. The rule filters selected EC2 security group rule API calls and forwards matching events to SNS. The email recipient must confirm the SNS subscription before receiving notifications.

## 2. What Terraform creates

- An SNS topic for security group change notifications.
- An SNS topic policy allowing EventBridge to publish to the topic.
- An EventBridge rule matching selected security group ingress and egress API calls.
- An EventBridge target connecting the rule to the SNS topic.
- A dedicated security group used only for the controlled test.

The project does not create an EC2 instance or open SSH access to a real public network.

## 3. Repository structure

```text
article-07-cloudtrail-event-monitoring/
├── ARTICLE.md
├── README.md
├── .gitignore
├── images/architecture.svg
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── scripts/
│   ├── deploy.sh
│   ├── subscribe-email.sh
│   ├── verify.sh
│   ├── test-alert.sh
│   └── destroy.sh
└── evidence/
    ├── README.md
    ├── results/.gitkeep
    └── screenshots/.gitkeep
```

## 4. Event pattern

The EventBridge rule filters CloudTrail API events from EC2. It includes `AuthorizeSecurityGroupIngress`, `RevokeSecurityGroupIngress`, `AuthorizeSecurityGroupEgress`, and `RevokeSecurityGroupEgress`.

[IMAGE PLACEHOLDER — Insert a screenshot of the EventBridge rule and event pattern after deployment.]

The rule matches selected API activity, not every possible network exposure condition. It is a focused detection example, not a complete security posture management solution.

## 5. Deploy

Prerequisites: Ubuntu/WSL2 or another Linux shell, Terraform CLI, AWS CLI v2, and an AWS identity authorized to manage the resources in this project.

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

Review the plan and ensure it contains only expected resources. Then:

```bash
./scripts/deploy.sh
```

[IMAGE PLACEHOLDER — Insert a screenshot of the reviewed Terraform plan.]
[IMAGE PLACEHOLDER — Insert a screenshot of successful Terraform apply.]

## 6. Subscribe an email endpoint

```bash
./scripts/subscribe-email.sh YOUR_EMAIL_ADDRESS
```

Open the AWS subscription confirmation email and confirm the subscription before testing.

[IMAGE PLACEHOLDER — Insert a screenshot showing the SNS subscription confirmed. Hide the email address.]

## 7. Verify the deployment

```bash
./scripts/verify.sh
```

The script checks the EventBridge rule, target, SNS topic, and test security group. These checks confirm configuration and wiring; they do not prove that an email was delivered.

[IMAGE PLACEHOLDER — Insert a screenshot of verification output.]

## 8. Generate a controlled test event

```bash
./scripts/test-alert.sh
```

The script adds a temporary TCP/22 ingress rule using `203.0.113.0/24`, a documentation-only address range, to the dedicated test security group. It then removes the temporary rule. The API activity should match the EventBridge rule and produce an SNS notification. Delivery is asynchronous, so allow time for the notification to arrive.

Do not use a production security group for this test. Do not replace the documentation-only CIDR with `0.0.0.0/0`.

[IMAGE PLACEHOLDER — Insert a screenshot of the controlled test command output.]
[IMAGE PLACEHOLDER — Insert a screenshot of the received SNS email alert, with personal details redacted.]

## 9. Operational considerations and limitations

- This example detects selected security group API calls; it is not a complete detector for all network exposure or all AWS security changes.
- Event delivery is asynchronous. Do not treat the notification path as a synchronous enforcement control.
- Email delivery depends on a confirmed SNS subscription and the recipient's mail provider.
- A production design should consider dead-letter handling, monitoring failed targets, alert routing, least-privilege permissions, and incident response procedures.
- Add other event patterns deliberately and test each one.
- Keep credentials and account-specific information out of source control and public screenshots.

## 10. Cleanup

After collecting evidence:

```bash
./scripts/destroy.sh
```

Review the destroy plan and confirm only the resources created for this demonstration will be removed.

[IMAGE PLACEHOLDER — Insert a screenshot of successful cleanup.]

## Conclusion

CloudTrail, EventBridge, and SNS provide a straightforward event-driven foundation for operational notifications. By filtering security group change API events and routing matches to SNS, teams can gain visibility into selected network access changes without continuously polling AWS APIs.

The value of this workflow comes from combining focused event detection with verification, tested delivery, clear operational limitations, and safe cleanup.

**Repository:** Add the public GitHub repository URL after publishing.
