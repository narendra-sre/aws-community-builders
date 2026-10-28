"""Reference Lambda handler for S3 event notifications delivered by SQS.

This sample validates the envelope and logs event metadata. It does not read
object contents or perform business processing. Extend it carefully for your
use case, and make side effects idempotent because SQS standard queues can
redeliver messages.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())


def _process_record(record: dict[str, Any]) -> None:
    """Validate and log an S3 ObjectCreated event contained in an SQS body."""
    body = record.get("body")
    if not isinstance(body, str):
        raise ValueError("SQS record is missing a string body")

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ValueError("SQS body is not valid JSON") from exc

    # S3 sends a test event when bucket notifications are first configured.
    if payload.get("Event") == "s3:TestEvent":
        logger.info("Received S3 test event")
        return

    s3_records = payload.get("Records")
    if not isinstance(s3_records, list) or not s3_records:
        raise ValueError("SQS body does not contain S3 event Records")

    for s3_record in s3_records:
        event_name = s3_record.get("eventName", "")
        if not event_name.startswith("ObjectCreated:"):
            logger.info("Skipping unsupported S3 event type: %s", event_name)
            continue

        s3 = s3_record.get("s3", {})
        bucket_name = s3.get("bucket", {}).get("name")
        encoded_key = s3.get("object", {}).get("key")
        if not bucket_name or not encoded_key:
            raise ValueError("S3 event is missing bucket name or object key")

        object_key = unquote_plus(encoded_key)
        logger.info(
            "Received object-created event: bucket=%s key=%s event=%s",
            bucket_name,
            object_key,
            event_name,
        )
        # Add application-specific, idempotent processing here.


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Process an SQS batch and return failed SQS message identifiers only."""
    failures: list[dict[str, str]] = []

    for record in event.get("Records", []):
        message_id = record.get("messageId")
        if not message_id:
            # Without an identifier we cannot report a partial batch failure.
            # Raise to fail the invocation rather than silently lose the item.
            raise ValueError("SQS record is missing messageId")

        try:
            _process_record(record)
        except Exception:
            logger.exception("Failed to process SQS message id=%s", message_id)
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}
