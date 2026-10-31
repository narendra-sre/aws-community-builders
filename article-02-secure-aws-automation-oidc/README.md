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
2. Set the AWS Region, existing GitHub OIDC provider ARN, repository owner/name, trusted branch, and test bucket.
3. Run `terraform init`, `terraform fmt -check`, `terraform validate`, and inspect `terraform plan`.
4. Apply only after reviewing the plan and permissions.
5. Add the Terraform output role ARN as GitHub repository variable `AWS_ROLE_ARN`.
6. Add the test bucket name as GitHub repository variable `DEMO_BUCKET`.
7. Commit the workflow to the trusted branch and run it.
8. Verify the identity with `aws sts get-caller-identity`.

## Security notes
- The role trusts one repository and branch by exact subject match.
- The example role can only list/read objects under the configured `reports/` prefix.
- Do not replace the trust condition with a broad wildcard.
- Do not add static AWS access keys to GitHub secrets.
- Review and pin third-party actions to a full commit SHA before production use.
- This reference implementation has not been deployed or validated in a live AWS account.

## Cleanup
Remove the IAM role and policy created by this Terraform configuration after testing. Do not delete a shared OIDC provider if other workloads depend on it. Remove test data only if it was created solely for this exercise.
