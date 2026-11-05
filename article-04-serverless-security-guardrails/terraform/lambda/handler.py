"""
Security guardrail remediator.

Invoked by EventBridge for CloudTrail management events:
  * ec2:AuthorizeSecurityGroupIngress
      Revokes only the world-open (0.0.0.0/0 or ::/0) rule when it exposes a sensitive port.
  * s3:PutBucketPublicAccessBlock / s3:DeleteBucketPublicAccessBlock
      Restores the full public access block when any protection has been weakened.

Design notes
  * Idempotent: a conditional DynamoDB PutItem claims each EventBridge event ID once,
    so at-least-once delivery cannot cause duplicate processing.
  * Failure-safe: if processing raises, the claim is released so EventBridge retries
    can run the event again. Events that exhaust retries go to the SQS dead-letter queue.
  * Loop-safe: remediation calls are CloudTrail events too, but they do not match the
    violation logic. RevokeSecurityGroupIngress is not in the rule, and a bucket that is
    already compliant produces no action.
  * Dry-run by default (DRY_RUN=true): it records and alerts but changes nothing.
  * Exemptions: a tag guardrail-exempt=true on the resource skips enforcement.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
s3 = boto3.client("s3")
sns = boto3.client("sns")
findings = boto3.resource("dynamodb").Table(os.environ["FINDINGS_TABLE"])

TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]
DRY_RUN = os.environ.get("DRY_RUN", "true").lower() == "true"
SENSITIVE_PORTS = {int(p) for p in os.environ.get("SENSITIVE_PORTS", "22,3389").split(",") if p.strip()}
EXEMPT_TAG_KEY = os.environ.get("EXEMPT_TAG_KEY", "guardrail-exempt")

WORLD_V4 = "0.0.0.0/0"
WORLD_V6 = "::/0"
BUCKET_EVENTS = {"PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock"}


def handler(event, context):
    detail = event.get("detail", {})
    event_id = event["id"]

    # Failed API calls changed nothing, so there is nothing to remediate.
    if detail.get("errorCode"):
        return _log("skipped", event_id, reason="failed API call")

    name = detail.get("eventName")
    if name == "AuthorizeSecurityGroupIngress":
        return _guard(event_id, _handle_security_group, detail)
    if name in BUCKET_EVENTS:
        return _guard(event_id, _handle_bucket, detail)
    return _log("ignored", event_id, reason=f"unhandled event {name}")


# ---------------------------------------------------------------------------
# Orchestration: idempotency, audit record, alerting
# ---------------------------------------------------------------------------

def _guard(event_id, evaluate, detail):
    if not _claim(event_id):
        return _log("duplicate", event_id)

    try:
        outcome = evaluate(detail)
    except Exception:
        # Release the claim so the EventBridge retry can process this event again.
        findings.delete_item(Key={"event_id": event_id})
        raise

    record = {
        "event_id": event_id,
        "event_name": detail.get("eventName"),
        "actor": detail.get("userIdentity", {}).get("arn", "unknown"),
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "dry_run": DRY_RUN,
        **outcome,
    }
    findings.put_item(Item=record)

    if outcome["action"] != "none":
        _notify(record)

    logger.info(json.dumps(record, default=str))
    return record


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


def _notify(record):
    subject = f"[guardrail] {record['action']} {record.get('resource')}"
    sns.publish(TopicArn=TOPIC_ARN, Subject=subject[:99], Message=json.dumps(record, indent=2, default=str))


def _log(outcome, event_id, **extra):
    record = {"event_id": event_id, "outcome": outcome, **extra}
    logger.info(json.dumps(record, default=str))
    return record


# ---------------------------------------------------------------------------
# Rule 1: security groups open to the world on sensitive ports
# ---------------------------------------------------------------------------

def _handle_security_group(detail):
    params = detail.get("requestParameters") or {}
    group_id = params.get("groupId")
    permissions = (params.get("ipPermissions") or {}).get("items", [])

    try:
        group = ec2.describe_security_groups(GroupIds=[group_id])["SecurityGroups"][0]
    except ClientError as err:
        if err.response["Error"]["Code"] == "InvalidGroup.NotFound":
            return {"resource": group_id, "action": "none", "reason": "group no longer exists"}
        raise

    if _has_exempt_tag(group.get("Tags", [])):
        return {"resource": group_id, "action": "none", "reason": "exempt"}

    # Build the minimal revoke request: the exact authorized rule, narrowed to world CIDRs only.
    revoke_rules, exposed_ports = [], set()
    for perm in permissions:
        ports = _sensitive_ports_in(perm)
        v4, v6 = _world_cidrs(perm)
        if ports and (v4 or v6):
            revoke_rules.append(_revoke_rule(perm, v4, v6))
            exposed_ports.update(ports)

    if not revoke_rules:
        return {"resource": group_id, "action": "none", "reason": "no world-open sensitive rule"}

    action = "would_revoke" if DRY_RUN else _revoke(group_id, revoke_rules)
    return {
        "resource": group_id,
        "action": action,
        "exposed_ports": sorted(exposed_ports),
        "reason": "sensitive port open to the internet",
        "rules": revoke_rules,
    }


def _sensitive_ports_in(perm):
    proto = perm.get("ipProtocol")
    if proto == "-1":  # all protocols and all ports
        return sorted(SENSITIVE_PORTS)
    if proto not in ("tcp", "6"):
        return []
    low, high = perm.get("fromPort", 0), perm.get("toPort", 65535)
    return sorted(p for p in SENSITIVE_PORTS if low <= p <= high)


def _world_cidrs(perm):
    v4 = [r["cidrIp"] for r in (perm.get("ipRanges") or {}).get("items", []) if r.get("cidrIp") == WORLD_V4]
    v6 = [r["cidrIpv6"] for r in (perm.get("ipv6Ranges") or {}).get("items", []) if r.get("cidrIpv6") == WORLD_V6]
    return v4, v6


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


def _revoke(group_id, rules):
    try:
        ec2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=rules)
        return "revoked"
    except ClientError as err:
        if err.response["Error"]["Code"] == "InvalidPermission.NotFound":
            return "already_revoked"  # someone else removed it first; the goal is met
        raise


# ---------------------------------------------------------------------------
# Rule 2: S3 buckets whose public access block was removed or weakened
# ---------------------------------------------------------------------------

def _handle_bucket(detail):
    bucket = (detail.get("requestParameters") or {}).get("bucketName")
    if not bucket:
        return {"resource": None, "action": "none", "reason": "no bucket name in event"}

    if _bucket_is_exempt(bucket):
        return {"resource": bucket, "action": "none", "reason": "exempt"}

    if _public_access_fully_blocked(bucket):
        return {"resource": bucket, "action": "none", "reason": "already compliant"}

    if DRY_RUN:
        action = "would_restore"
    else:
        action = _restore_public_access_block(bucket)

    return {
        "resource": bucket,
        "action": action,
        "reason": "public access block removed or weakened",
    }


def _bucket_is_exempt(bucket):
    try:
        tags = s3.get_bucket_tagging(Bucket=bucket)["TagSet"]
    except ClientError as err:
        if err.response["Error"]["Code"] in ("NoSuchTagSet", "NoSuchBucket"):
            return False
        raise
    return _has_exempt_tag(tags)


def _public_access_fully_blocked(bucket):
    try:
        cfg = s3.get_public_access_block(Bucket=bucket)["PublicAccessBlockConfiguration"]
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchPublicAccessBlockConfiguration":
            return False
        raise
    return all(cfg.get(k) for k in ("BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets"))


def _restore_public_access_block(bucket):
    try:
        s3.put_public_access_block(
            Bucket=bucket,
            PublicAccessBlockConfiguration={
                "BlockPublicAcls": True,
                "IgnorePublicAcls": True,
                "BlockPublicPolicy": True,
                "RestrictPublicBuckets": True,
            },
        )
        return "restored"
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchBucket":
            return "bucket_missing"
        raise


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _has_exempt_tag(tags):
    return any(t.get("Key") == EXEMPT_TAG_KEY and t.get("Value") == "true" for t in tags)
