# Article 02 — Secure AWS Automation with GitHub Actions and OIDC

This project accompanies `ARTICLE.md`.

## Contents

- `ARTICLE.md` — full technical article.
- `images/` — original architecture and trust-flow diagrams.
- `terraform/` — IAM role, trust policy, and narrow example S3 permissions.
- `.github/workflows/oidc-demo.yml` — example GitHub Actions workflow.

## Prerequisites

- AWS account and a dedicated non-production test environment.
- Terraform installed.
- A GitHub repository where you can configure Actions variables.
- An AWS IAM OIDC identity provider for `https://token.actions.githubusercontent.com` already created in the target account, with audience `sts.amazonaws.com`.
- An existing dedicated test bucket with a `reports/` prefix if running the sample S3 list command.

## Configure

1. Review `terraform/variables.tf`.
2. Set the AWS Region, existing GitHub OIDC provider ARN, exact GitHub OIDC subject, and test bucket.
3. Before setting `github_oidc_subject`, inspect the actual `sub` claim issued by the workflow. See Section 5 of `ARTICLE.md` for a temporary diagnostic step.
4. Use the complete subject exactly as issued. Depending on the repository, it may use the legacy name-based format or the newer immutable format containing owner and repository IDs.
5. Run:

   ```bash
   terraform init
   terraform fmt -check
   terraform validate
   terraform plan

## Implementation and Validation

The demonstration was deployed and validated using AWS IAM,
Amazon S3, Terraform, GitHub Actions, and OpenID Connect.

### Validated Scenarios

- GitHub Actions successfully authenticated with AWS using OIDC.
- AWS issued temporary credentials through STS.
- The IAM role permitted access to the approved `reports/` prefix.
- Access to the `private/` prefix was denied.
- GitHub Actions execution screenshots and AWS evidence were captured.

### Evidence

See the `evidence/` directory for Terraform plans, IAM
configuration, CloudTrail results, and workflow screenshots.
