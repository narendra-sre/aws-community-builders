# Automating AWS Infrastructure Deployment with Terraform: Reusable Modules, State Management, and Safe Workflows

## Introduction

Manual cloud provisioning can be difficult to reproduce, review, and audit consistently. Infrastructure as Code (IaC) addresses this by describing the desired infrastructure in version-controlled configuration.

This project uses Terraform to deploy a reusable, security-conscious Amazon S3 bucket configuration on AWS. It demonstrates provider configuration, variables and outputs, reusable modules, Terraform state, controlled plan/apply/destroy workflows, AWS CLI verification, and automated Terraform checks with GitHub Actions.

The implementation focuses on practical infrastructure automation while keeping security controls and operational safety visible throughout the workflow.

> **Cost notice:** This project provisions real AWS resources and is not guaranteed to be free. S3 storage, requests, and other account activity may incur charges. Review current AWS pricing and your account billing before deployment, and remove demonstration resources when they are no longer needed.

## Implementation status

- Terraform configuration deployed successfully; the six planned resources were created.
- Deployed S3 security settings verified using AWS CLI.
- Evidence command outputs and deployment screenshots captured.
- Infrastructure cleanup is pending.

## 1. What we are building

Terraform creates an S3 bucket with:

- A globally unique name generated using Terraform's `random` provider.
- Versioning enabled.
- Default server-side encryption using SSE-S3.
- All four S3 Block Public Access settings enabled.
- Bucket-owner-enforced object ownership.
- Consistent project and environment tags.

The S3 configuration is encapsulated in a reusable Terraform module.

[IMAGE PLACEHOLDER — Insert the architecture diagram from `images/architecture.svg`.]

## 2. Architecture and deployment flow

```text
Developer
   |
   v
Terraform root configuration
   |-- variables.tf
   |-- main.tf
   |-- outputs.tf
   |
   v
Reusable module: secure_s3_bucket
   |-- S3 bucket
   |-- Versioning
   |-- Default encryption
   |-- Block Public Access
   |-- Object ownership controls
   |
   v
AWS provider -> AWS account

Terraform state records managed resources.
GitHub Actions validates configuration; it does not deploy.
```

[IMAGE PLACEHOLDER — Insert a screenshot or diagram illustrating the Terraform deployment flow.]

## 3. Repository structure

```text
article-06-terraform-infrastructure-deployment/
├── ARTICLE.md
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── terraform-checks.yml
├── examples/
│   └── terraform.tfvars.example
├── images/
│   └── architecture.svg
├── evidence/
│   ├── README.md
│   ├── results/
│   │   ├── .gitkeep
│   │   └── [captured command outputs]
│   └── screenshots/
│       ├── [deployment and verification screenshots]
│       └── [GitHub Actions screenshot, if captured]
├── modules/
│   └── secure_s3_bucket/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── scripts/
│   ├── terraform-check.sh
│   ├── plan.sh
│   ├── apply.sh
│   ├── verify.sh
│   ├── capture-evidence.sh
│   └── destroy.sh
└── terraform/
    ├── versions.tf
    ├── providers.tf
    ├── variables.tf
    ├── main.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── .terraform.lock.hcl
```

The `.terraform.lock.hcl` file is generated during initialization and should be committed to version control. Terraform working directories, state files, backup state files, local variable files, and generated plan files should remain excluded through `.gitignore`. Evidence files should contain genuine results and must be reviewed for sensitive information before committing.

## 4. Reusable Terraform module

The root configuration calls `modules/secure_s3_bucket`. The module separates the S3 resource implementation from environment-specific inputs. It accepts a bucket name and tags, then configures versioning, encryption, public-access blocking, and object ownership.

[IMAGE PLACEHOLDER — Insert a screenshot showing `modules/secure_s3_bucket/` and the module call in the root configuration.]

## 5. Variables and outputs

Variables allow the same configuration to be reused without editing resource definitions. Inputs include the bucket name prefix, AWS region, environment, and project name.

A random suffix is added to the bucket name to reduce the chance of a global S3 naming collision. Terraform records the generated value in state. Outputs expose the bucket name, ARN, and region for operators and verification scripts. Do not use outputs to expose secrets.

[IMAGE PLACEHOLDER — Insert a screenshot of the Terraform variables and outputs, if useful.]

## 6. Terraform state management

Terraform state maps configuration resources to real infrastructure objects. Terraform uses it to calculate changes during subsequent plans.

This standalone demonstration uses the default local state file. State can contain sensitive infrastructure metadata:

- Do not commit `terraform.tfstate` or backup state files.
- Do not manually edit state files.
- Protect and back up state.
- For team or production use, prefer a protected remote backend with access controls, encryption, versioning, and locking.

[IMAGE PLACEHOLDER — Insert a screenshot of `terraform state list` showing the managed resources. Redact account-specific details.]

This repository documents local state; it does not automatically create a remote backend. A remote backend requires a separately bootstrapped storage location and deliberate access-control design.

## 7. Deployment workflow

From the project root:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
terraform fmt -recursive
terraform -chdir=terraform init
./scripts/terraform-check.sh
./scripts/plan.sh
```

Review the plan before applying. It should contain only the intended S3 bucket and its security configuration. Do not approve changes you do not recognize.

```bash
./scripts/apply.sh
```

Terraform asks for confirmation. Read the proposed changes before approving.

[IMAGE PLACEHOLDER — Insert a screenshot of the reviewed Terraform plan showing the planned resource creation.]

[IMAGE PLACEHOLDER — Insert a screenshot of the successful Terraform apply summary.]

## 8. Verify the deployed configuration

```bash
./scripts/verify.sh
```

The script uses Terraform outputs and AWS CLI read operations to check the bucket's public-access block, versioning, encryption, and ownership controls.

[IMAGE PLACEHOLDER — Insert a screenshot of the actual AWS CLI verification output.]

After deployment, a second Terraform plan should report no changes when the live infrastructure matches the configuration.

[IMAGE PLACEHOLDER — Insert a screenshot showing `No changes. Your infrastructure matches the configuration.`]

Report only settings that the verification commands actually confirm. A successful apply is not a substitute for checking the resulting configuration.

## 9. Automated checks with GitHub Actions

The included GitHub Actions workflow runs Terraform formatting, initialization, and validation when relevant files change. It does not apply infrastructure and does not require AWS credentials.

A production deployment workflow should use short-lived credentials through GitHub OIDC, a narrowly scoped IAM role, protected environments, and explicit approval gates rather than long-lived access keys.

[IMAGE PLACEHOLDER — Insert a screenshot of a successful GitHub Actions workflow run, after the workflow has run.]

## 10. Cost, safety, and cleanup

This project creates an S3 bucket and related S3 configuration resources. Charges may apply for storage, requests, and other AWS usage. Review current AWS pricing and your account billing. Consider setting a budget or billing alert.

After collecting and reviewing evidence, destroy the demonstration resources if they are no longer needed:

```bash
./scripts/destroy.sh
```

The bucket uses `force_destroy = false`. If it contains objects or versions, Terraform will not silently empty it. Inspect the bucket and remove only demonstration data you intentionally created, then run destroy again. Do not enable force deletion simply to make cleanup easier.

[IMAGE PLACEHOLDER — Insert a screenshot of the destroy confirmation and successful completion after cleanup.]

## 11. Limitations and next steps

- Local state is used for a single-user demonstration; team use should adopt a protected remote backend.
- GitHub Actions validates configuration but deliberately does not deploy.
- This is a small S3 example, not a complete production landing zone.
- It does not include organization-wide guardrails, centralized logging, or cross-account deployment.
- Future improvements could add policy-as-code checks, environment promotion, remote-state bootstrapping, and an OIDC-based deployment workflow.

## Conclusion

Terraform makes infrastructure changes reviewable and repeatable by describing desired state as code. Reusable modules, explicit variables and outputs, a deliberate state strategy, and a plan-before-apply workflow form a practical foundation for AWS infrastructure management.

Automation is more than running `terraform apply`: it includes reviewing changes, protecting state, verifying deployed settings, controlling permissions, understanding cost, and cleaning up responsibly.

**Repository:** Add the public GitHub repository URL here after publishing.
