# Preventing Public Exposure Before It Happens: Event-Driven AWS Security Guardrails with Terraform, Lambda, and EventBridge

## Introduction

Most cloud security tooling tells you about a mistake after it has already happened. A scanner runs on a schedule, a finding appears in a dashboard, and someone eventually opens a ticket. In the meantime, a security group that allows SSH from `0.0.0.0/0` is reachable from the entire internet, and a bucket whose public access block has been removed can be opened to the internet with a single ACL or bucket policy change.

In this article I build a guardrail that reacts to the API call itself rather than to the next scan. When someone opens a sensitive port to the world or weakens the public access block on an S3 bucket, a Lambda function is invoked within seconds. It either reverts the change or, in dry-run mode, only alerts. Every decision is written to an audit table, and the team receives an email. The entire stack is provisioned with Terraform and designed to run inside the AWS Free Tier.

The complete project, including Terraform code, the remediator, test scripts, and sanitized evidence, is in my GitHub repository, linked at the end.

## 1. The Problem

Two misconfigurations cause a disproportionate share of avoidable cloud exposure:

* **Administrative ports open to the internet.** SSH (22) and RDP (3389) opened to `0.0.0.0/0` are routinely targeted by automated scanners within minutes of appearing.
* **Public S3 buckets.** Buckets become public when the Block Public Access settings are removed, usually to make a quick test work and then forgotten.

Both are easy to introduce. A single CLI command or console click is enough. Both are also easy to miss: the change looks reasonable in isolation, and nobody is watching the API stream.

Detection alone has a structural weakness. A scheduled scan has a detection window measured in hours, while the change itself takes effect in seconds. Auto-remediation closes that window, but it introduces its own risk. A guardrail that silently breaks a legitimate workflow is worse than none. The design therefore has to answer three questions: how to act quickly, how to avoid acting wrongly, and how to prove afterwards what happened.

## 2. Architecture

The flow has six steps:

1. An engineer or an automation pipeline calls `AuthorizeSecurityGroupIngress`, `DeleteBucketPublicAccessBlock`, or `PutBucketPublicAccessBlock`.
2. CloudTrail records the call. Its management events reach the default EventBridge bus as `AWS API Call via CloudTrail`, so no additional trail is required for detection.
3. An EventBridge rule matches only the three violation-relevant event names, and invokes the remediator Lambda with up to three retries.
4. The Lambda claims the event ID in DynamoDB, evaluates the change, and either remediates or simulates the remediation depending on the dry-run setting.
5. The outcome is written to the findings table, and an alert is published to SNS and delivered by email.
6. Any event that fails every retry is parked in an SQS dead-letter queue for inspection.

[Insert `images/guardrail-architecture.svg` here]

The services were chosen for cost as much as capability. I avoided AWS Config and Security Hub, which are powerful but billed per rule evaluation or finding, and I avoided customer-managed KMS keys, which carry a monthly charge. Lambda, EventBridge rules on the default bus, DynamoDB on-demand, SNS email, SQS, and CloudWatch Logs with 14-day retention all fit within the Free Tier for a workload of this size.

## 3. Design Decisions

**Event-driven rather than polling.** The guardrail reacts to the API call, so it acts within seconds and does not pay for periodic full-account scans.

**Revoke the exact rule, narrowed to the world.** The remediator does not wipe the security group. It removes only the authorized rule, and only the `0.0.0.0/0` or `::/0` entries within it. A rule that also allows a private CIDR keeps its private entries. This keeps the blast radius of the correction as small as the violation.

**Idempotent processing.** EventBridge delivers at least once, so the same event can arrive twice. The remediator writes the event ID to DynamoDB with a conditional `PutItem`. A second delivery fails the condition and is recorded as a duplicate. If processing crashes midway, the claim is deleted before the error is re-raised, so the retry can run to completion instead of being wrongly skipped.

**Loop safety.** Remediation itself produces CloudTrail events. Revoking an ingress rule emits `RevokeSecurityGroupIngress`, which the rule does not match. Restoring a public access block emits `PutBucketPublicAccessBlock`, which the rule does match, but the handler first checks compliance and does nothing if the bucket is already fully blocked. The system converges instead of looping.

**Dry-run by default.** The first deployment sets `DRY_RUN=true`. It records what it would have changed and sends alerts, but changes nothing. This lets a team observe real traffic for days before enforcing. Enforcement is a single Terraform variable.

**Exemptions by tag.** Some resources legitimately need public access, such as a static website bucket or a bastion host. A resource tagged `guardrail-exempt=true` is skipped and recorded as exempt. The tradeoff is that anyone who can apply tags can grant an exemption, so tag-write permissions become a security-sensitive privilege. I discuss how to govern that in the limitations section.

**Least privilege.** Each IAM statement maps to a specific API call in the handler. Describe calls are the only ones that cannot be scoped by resource, and they are isolated in their own statement. The one known gap is the S3 statement, which covers all buckets. Narrowing it with a tag condition is planned future work, and I've documented it in the code rather than hiding it.

## 4. Implementation

### 4.1 Detection rule

The EventBridge pattern matches the CloudTrail event envelope on source service and event name:

```hcl
event_pattern = jsonencode({
  "detail-type" = ["AWS API Call via CloudTrail"]
  detail = {
    eventSource = ["ec2.amazonaws.com", "s3.amazonaws.com"]
    eventName   = concat(["AuthorizeSecurityGroupIngress"], local.bucket_events)
  }
})
```

The target carries both a retry policy and a dead-letter queue. These two settings are what turn "the Lambda failed once" into "the event was retried for an hour and then preserved for inspection."

```hcl
retry_policy {
  maximum_event_age_in_seconds = 3600
  maximum_retry_attempts       = 3
}

dead_letter_config {
  arn = aws_sqs_queue.dlq.arn
}
```

### 4.2 Revoking only the violating rule

The security group handler inspects each authorized permission in the CloudTrail record and builds the smallest revoke request that undoes the violation:

```python
def _revoke_rule(perm, v4, v6):
    rule = {"IpProtocol": perm["ipProtocol"]}
    if "fromPort" in perm:
        rule["FromPort"] = perm["fromPort"]
        rule["ToPort"] = perm["toPort"]
    if v4:
        rule["IpRanges"] = [{"CidrIp": cidr} for cidr in v4]
    if v6:
        rule["Ipv6Ranges"] = [{"CidrIpv6": cidr} for cidr in v6]
    return rule
```

The revoke must match the original protocol and port range exactly, which is why the handler copies them from the event rather than reconstructing them from the configured sensitive ports.

### 4.3 Claiming each event once

```python
def _claim(event_id):
    try:
        findings.put_item(
            Item={"event_id": event_id, "status": "PROCESSING"},
            ConditionExpression="attribute_not_exists(event_id)",
        )
        return True
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise
```

The wrapper that calls this function releases the claim on failure:

```python
try:
    outcome = evaluate(detail)
except Exception:
    findings.delete_item(Key={"event_id": event_id})
    raise
```

Without that release, a transient API error would leave the event permanently marked as processing, and every retry would be skipped.

### 4.4 Infrastructure

Everything is defined in five Terraform files: `versions.tf` pins the AWS and archive providers, `provider.tf` applies default tags, `variables.tf` exposes the dry-run switch, sensitive port list, and alert address, `main.tf` declares the resources, and `outputs.tf` exposes names needed by the test and evidence scripts. The handler is packaged from `lambda/handler.py` by an archive data source, so a code change produces a new `source_code_hash` and Terraform updates the function on the next apply.

## 5. Testing the Guardrail

`scripts/simulate-violations.sh` exercises three scenarios:

1. Open SSH on a normal security group. This should be a violation.
2. Open SSH on a security group tagged `guardrail-exempt=true`. This should be allowed.
3. Delete the public access block on a new bucket. This should be a violation.

I ran the test in dry-run mode first, confirmed that the alerts and audit records were correct and nothing was changed, and then set `dry_run = false` and reran it.

| Scenario | Expected in dry-run | Expected in enforce mode | Observed |
|---|---|---|---|
| 1. Open SSH, untagged SG | `would_revoke` recorded, alert sent, rule still present | rule revoked, alert sent | [Insert observed result] |
| 2. Open SSH, exempt SG | `none` (exempt), no alert | same | [Insert observed result] |
| 3. Public access block deleted | `would_restore` recorded, alert sent | block restored, alert sent | [Insert observed result] |

The time from API call to revocation was [insert measured seconds from CloudTrail eventTime to the revoke call in the logs]. This is the window in which the exposure existed, and it is the number that matters most when comparing this approach with scheduled scanning.

## 6. Evidence

The `evidence/` folder contains sanitized outputs from the run. Account IDs are replaced with `111122223333`.

| File | What it shows |
|---|---|
| `terraform-plan-summary.json` | The resources the stack creates |
| `findings-table-sanitized.json` | One audit record per processed event, including dry-run flag and actor |
| `remediator-logs-sanitized.json` | Lambda decisions, including duplicate and exempt paths |
| `cloudtrail-authorize-ingress-sanitized.json` | The originating API call for scenario 1 |
| `cloudtrail-delete-public-access-block-sanitized.json` | The originating API call for scenario 3 |
| `sg-after-remediation-sanitized.json` | The security group after enforcement |
| `screenshots/` | Console views of the alert email, DynamoDB items, and bucket settings |

## 7. Cost

On an account used only for this project, the workload should stay within the Free Tier: a handful of Lambda invocations, a few dozen DynamoDB writes, a few email notifications, and a small amount of log data. I verified this against the Billing dashboard after running the simulation, and the observed charges were [insert observed charges, or "zero"]. Costs can change, so check your own account's Free Tier usage before leaving the stack running.

## 8. Limitations and Future Work

**The guardrail is reactive, not preventive.** There is a window of seconds between the API call and the correction. A Service Control Policy can prevent some of these calls outright, and I would layer one on top in a production setting.

**It does not find existing exposure.** The guardrail only sees new API calls. A one-time sweep of existing security groups and buckets would complement it.

**Exemptions need governance.** Because exemption is a tag, the control is only as strong as the permission to write tags. A production version should restrict tag changes on guarded resources, or require an approval record.

**Bucket policies and ACLs are out of scope.** This rule covers the public access block only. A bucket made public through a bucket policy or ACL would need additional rules.

**The S3 IAM statement is broader than ideal.** It covers all buckets. A tag-based condition would narrow it to buckets the team owns.

## Conclusion

Public exposure is one of the most common and most preventable cloud misconfigurations. Scanning finds it eventually, but the exposure starts the moment the API call succeeds. This project closes that gap with an event-driven guardrail that acts within seconds, revokes only what violates policy, records every decision, and fails safely.

The design choices that matter most are not the services but the behaviors around them: dry-run before enforcement, idempotent processing, a dead-letter queue, narrowly scoped revocation, and an explicit exemption path. Those choices are what make an automated security control safe to run in a real account.

**GitHub repository:** [Insert your aws-community-builder repository URL]
