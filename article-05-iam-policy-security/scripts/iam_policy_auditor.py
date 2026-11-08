#!/usr/bin/env python3
"""Small educational static checker for selected IAM JSON policy patterns.

This is not a complete IAM policy parser, AWS authorization engine, or
replacement for IAM Access Analyzer. It deliberately checks a limited set
of risky patterns so the checks are explainable and reproducible.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

SENSITIVE_ACTIONS = {
    "iam:PassRole", "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion",
    "iam:AttachRolePolicy", "iam:AttachUserPolicy", "iam:PutRolePolicy",
    "iam:PutUserPolicy",
}


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def audit(path: Path):
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [{"severity": "ERROR", "sid": "<document>", "message": str(exc)}], False

    findings = []
    if not isinstance(doc, dict):
        return [{"severity": "ERROR", "sid": "<document>", "message": "Policy document must be a JSON object."}], False
    statements = doc.get("Statement")
    if isinstance(statements, dict):
        statements = [statements]
    if not isinstance(statements, list) or not statements:
        return [{"severity": "ERROR", "sid": "<document>", "message": "Statement must be a non-empty object or array."}], False

    for index, stmt in enumerate(statements, start=1):
        if not isinstance(stmt, dict):
            findings.append({"severity": "ERROR", "sid": f"Statement_{index}", "message": "Statement must be an object."})
            continue
        sid = stmt.get("Sid", f"Statement_{index}")
        effect = stmt.get("Effect")
        actions = [str(x) for x in as_list(stmt.get("Action"))]
        resources = [str(x) for x in as_list(stmt.get("Resource"))]
        if effect == "Allow" and "*" in actions and "*" in resources:
            findings.append({"severity": "CRITICAL", "sid": sid, "message": "Allow with Action='*' and Resource='*'."})
        if effect == "Allow" and any(a.endswith(":*") for a in actions) and "*" in resources:
            findings.append({"severity": "HIGH", "sid": sid, "message": "Service-wide action wildcard is granted on Resource='*'."})
        if effect == "Allow":
            for action in actions:
                if action in SENSITIVE_ACTIONS and "*" in resources:
                    findings.append({"severity": "HIGH", "sid": sid, "message": f"Sensitive action {action} is granted on Resource='*'."})
    return findings, True


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {Path(sys.argv[0]).name} POLICY.json [POLICY.json ...]", file=sys.stderr)
        return 2
    any_error = False
    for name in sys.argv[1:]:
        path = Path(name)
        findings, parsed = audit(path)
        print(f"\nPolicy: {path}")
        if not parsed:
            any_error = True
        if findings:
            for item in findings:
                print(f"[{item['severity']}] {item['sid']}: {item['message']}")
        else:
            print("PASS: no patterns from this checker's limited rule set were found.")
        # A policy with security findings is an expected demonstration result;
        # malformed/unreadable input is an execution error.
        if not parsed:
            any_error = True
    return 2 if any_error else 0

if __name__ == "__main__":
    raise SystemExit(main())
