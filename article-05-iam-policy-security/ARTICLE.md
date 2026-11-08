# From Wildcards to Least Privilege: Building a No-Infrastructure AWS IAM Policy Security Review Workflow

## Introduction

IAM policies can grant broader access than an application needs. A statement such as `"Action": "*"` combined with `"Resource": "*"` is a clear warning sign, while broad service permissions and sensitive IAM actions can also introduce unnecessary privilege.

This project compares an intentionally over-permissive IAM identity policy with a scoped S3 example. It uses three complementary review stages:

1. A local Python JSON checker that detects a deliberately limited set of risky patterns.
2. AWS IAM Access Analyzer policy validation.
3. AWS IAM Policy Simulator evaluations for selected action/resource pairs.

The workflow is review-only. It does not create IAM identities, attach policies, create an S3 bucket, or provision compute or storage infrastructure. The AWS API calls validate and simulate policy documents; they do not execute S3 operations.

> **Cost wording:** This project provisions no AWS infrastructure. Do not interpret that as a guarantee that every account activity is free. Check current AWS pricing and your account's billing information independently.

## 1. The problem

A policy can be valid JSON and still grant excessive permissions. For example:

```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```

This statement allows all actions on all resources within the scope of the identity policy, subject to the broader AWS authorization evaluation. Another pattern worth reviewing is a sensitive IAM action such as `iam:PassRole` allowed against every resource.

The challenge is to review policies before deployment without attaching an unsafe policy to a real identity or creating test infrastructure.

## 2. Architecture

[IMAGE PLACEHOLDER — Insert the project architecture diagram here. Suggested file: `images/architecture.svg`.]

The workflow has three stages:

```text
Developer / DevOps engineer
           |
           v
    IAM policy JSON files
           |
     +-----+----------------+
     |                      |
     v                      v
Over-permissive         Scoped S3
example policy          example policy
     |                      |
     +----------+-----------+
                |
                v
       Stage 1: Local check
        Python JSON auditor
                |
                v
     Stage 2: Policy validation
       IAM Access Analyzer
          ValidatePolicy
                |
                v
      Stage 3: Authorization test
       IAM Policy Simulator
        SimulateCustomPolicy
                |
                v
       Review actual results
                |
                v
        Evidence and reporting

No IAM resources, buckets, or compute are created.
```

The stages answer different questions:

- **Local checker:** Does the document contain any of the specific risky patterns selected for this project?
- **Access Analyzer:** What findings does AWS return when it validates the identity policy?
- **Policy Simulator:** What decision does the simulator return for the selected action/resource pairs and supplied policy?

These tools complement one another; none independently proves that a policy is safe for every workload.

## 3. Project files

- `policies/overprivileged-policy.json` — deliberately unsafe teaching example. Do not attach it to a real identity.
- `policies/least-privilege-policy.json` — scoped S3 permissions for a fictional bucket and telemetry prefix.
- `scripts/iam_policy_auditor.py` — limited local JSON policy checker.
- `scripts/audit-policies.sh` — runs the local checker.
- `scripts/validate-policies.sh` — calls Access Analyzer `ValidatePolicy` for both documents.
- `scripts/simulate-policies.sh` — evaluates three separate action/resource cases.
- `scripts/capture-evidence.sh` — runs the checks and stores fresh command outputs.
- `scripts/run-local-checks.sh` — runs the local checks, if included in the project version.
- `scripts/cleanup.sh` — provides local evidence cleanup guidance.

## 4. Stage 1: Local static checks

The Python program parses the JSON document and inspects selected statement fields, including `Effect`, `Action`, and `Resource`. Its rules include patterns such as:

- `Allow` with both `Action: "*"` and `Resource: "*"`.
- A service wildcard such as `s3:*` paired with `Resource: "*"`.
- Selected sensitive IAM actions allowed on `Resource: "*"`.

Run the checker from the project root:

```bash
./scripts/audit-policies.sh
```

The deliberately over-permissive sample is expected to produce findings. The scoped sample is expected to pass this checker's limited rule set. A clean result means only that none of the implemented rules matched; it is not a full IAM security assessment. The checker does not infer application requirements or evaluate every IAM policy feature.

## 5. Stage 2: AWS policy validation

Run:

```bash
./scripts/validate-policies.sh
```

The script calls the Access Analyzer `ValidatePolicy` API for both policy documents. A representative command is:

```bash
aws accessanalyzer validate-policy \
  --policy-document file://policies/least-privilege-policy.json \
  --policy-type IDENTITY_POLICY \
  --output json
```

Review the actual `findings` returned by AWS. Finding types and messages are generated by AWS. Do not assume that every insecure-looking policy will return one particular finding, or that an empty findings list proves the policy is safe.

## 6. Stage 3: IAM Policy Simulator

The scoped policy is intended to allow `s3:PutObject` only for objects under the fictional bucket's `telemetry/` prefix. It includes an explicit restriction for bucket deletion and does not grant object deletion.

Run:

```bash
./scripts/simulate-policies.sh
```

The script makes three separate simulator calls so each action is evaluated against its corresponding resource ARN.

| Test | Action | Resource | Expected decision from the supplied policy |
|---|---|---|---|
| Intended operation | `s3:PutObject` | `arn:aws:s3:::article05-demo-bucket/telemetry/sample.json` | `allowed` |
| Explicit restriction | `s3:DeleteBucket` | `arn:aws:s3:::article05-demo-bucket` | `explicitDeny` |
| Not granted | `s3:DeleteObject` | `arn:aws:s3:::article05-demo-bucket/telemetry/sample.json` | `implicitDeny` |

These are expected outcomes based on the sample policy and simulator inputs. Use the actual simulator output as the source of truth for the run and update the article if it differs.

The simulator does not send a real S3 request and does not prove that a real request would succeed. Actual authorization can depend on additional identity, resource, permissions-boundary, session, Organizations, and request-context controls.

[IMAGE PLACEHOLDER — Insert a terminal screenshot showing the actual simulator `allowed` result for `s3:PutObject`.]

[IMAGE PLACEHOLDER — Insert a terminal screenshot showing the actual `explicitDeny` and `implicitDeny` results.]

## 7. Evidence collection

Run:

```bash
./scripts/capture-evidence.sh
```

Fresh command output is saved under `evidence/results/`. The capture script stores the local auditor output, Access Analyzer responses, and simulator decisions.

Take screenshots of your own terminal sessions and save them under `evidence/screenshots/`. Do not use fabricated execution results or billing screenshots.

Suggested screenshots:

- Local Python auditor findings for the over-permissive policy.
- Access Analyzer findings for the over-permissive policy.
- Access Analyzer response for the scoped policy.
- Simulator output for the three action/resource cases.
- The generated evidence file list.

[IMAGE PLACEHOLDER — Insert a screenshot of the local Python auditor output.]

[IMAGE PLACEHOLDER — Insert a screenshot of the Access Analyzer findings.]

[IMAGE PLACEHOLDER — Insert a screenshot of the generated `evidence/results/` files.]

Before publishing, review the evidence and remove sensitive account information or unrelated output. Do not commit credentials, tokens, private keys, or AWS configuration files.

## 8. Cost and safety considerations

This workflow does not provision AWS infrastructure, attach policies, or issue S3 data-plane requests. It invokes IAM policy validation and simulation APIs. Check current AWS pricing and your own account billing separately; this project does not guarantee that unrelated account activity has no cost.

Do not attach the over-permissive sample to a real IAM user, group, or role. The bucket ARN is fictional; no bucket is created or contacted.

## 9. Limitations and future work

- Expand the local checker's test suite and rule coverage while keeping its limitations explicit.
- Add unit tests for malformed documents, single-statement and array statements, wildcard actions, and sensitive permissions.
- Integrate the checks into a pull-request workflow after reviewing false-positive and failure-handling behavior.
- Add workload-specific requirements so a policy can be reviewed against what the application actually needs.
- Evaluate permissions boundaries, resource policies, session policies, and Organizations controls in an appropriate review or simulation context.

## Conclusion

Least privilege is not achieved by finding one wildcard and replacing it mechanically. It requires understanding the workload's intended actions and resources, checking policy structure, and testing representative authorization cases. A local checker, Access Analyzer validation, and Policy Simulator provide three useful review layers before a policy is deployed—without creating test infrastructure for this demonstration.

**Repository:** Replace this line with the public GitHub repository URL after publishing the project.
