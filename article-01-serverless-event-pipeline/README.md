# Article 1 — Serverless Event-Driven Processing Pipeline

This project accompanies the article [Building a Serverless Event-Driven Processing Pipeline with Amazon S3, Amazon SQS, and AWS Lambda](ARTICLE.md).

## Contents

- `ARTICLE.md` — full article draft with image placements and captions.
- `images/` — original diagrams used in the article (PNG files), with editable Graphviz source (`.dot`) and Mermaid alternatives (`.mmd`).
- `main.tf`, `variables.tf`, `versions.tf` — Terraform reference implementation.
- `lambda/handler.py` — Python Lambda handler.

## Implementation status

This is a reference implementation and has not yet been deployed or validated in a live AWS account. Review the Terraform plan and security configuration before applying it.

## Prerequisites

- Terraform compatible with the constraint in `versions.tf`
- AWS CLI configured for a test account/role
- An AWS Region supported by the selected resource settings
- Python runtime compatible with the Lambda configuration

## Review and validate

From this directory:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the complete plan and AWS pricing before running `terraform apply`. Do not apply automatically or use a production account for first testing. The article includes a checklist for end-to-end validation, failure handling, security, and cleanup.

## Images

The article references these images in order:

1. `images/01-architecture.png` — overall architecture
2. `images/02-event-flow.png` — processing sequence
3. `images/03-retry-dlq.png` — retry and DLQ behaviour
4. `images/04-security-boundaries.png` — security boundaries

These diagrams are original project illustrations. The `.dot` files are editable Graphviz source; `.mmd` files are Mermaid alternatives for compatible viewers.
