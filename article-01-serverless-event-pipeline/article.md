# Building a Serverless Event-Driven Processing Pipeline with Amazon S3, Amazon SQS, and AWS Lambda

**Level:** Intermediate  
**Focus:** Event-driven architecture, asynchronous processing, reliability, security, and observability  
**Example code:** [aws-community-builders repository](https://github.com/narendra-sre/aws-community-builders/tree/main/article-01-serverless-event-pipeline)

> **Implementation status:** This article describes a reference implementation using Terraform and Python. It has not yet been deployed or validated in a live AWS account. Treat the code as a starting point: review it, run the checks in the repository, and test in a controlled environment before using it for production workloads.

## Introduction

Imagine you operate an application where users upload invoices, images, reports, or CSV files. Each upload needs to trigger some work: validate metadata, extract information, transform data, or notify another system.

A tightly coupled implementation can make the upload path slower and harder to operate. If processing is temporarily unavailable, the upload workflow may also be affected. A more resilient approach is to separate the act of accepting a file from the work that follows it.

In this article, we'll explore an event-driven pattern built with Amazon Simple Storage Service (Amazon S3), Amazon Simple Queue Service (Amazon SQS), and AWS Lambda. We'll also cover a dead-letter queue, IAM permissions, encryption, monitoring, retries, and idempotency.

📷 **[INSERT IMAGE 1 HERE — Overall architecture diagram: `images/01-architecture.png`]**  
*Figure 1. A file-created event is queued, processed asynchronously by Lambda, and observed through CloudWatch. Repeatedly failing messages can be moved to a dead-letter queue.*

## 1. The problem we're solving

A simple file upload workflow often starts with one question: what should happen after a file arrives?

For a small prototype, an application might upload a file and then call a processing function directly. This can be acceptable, but it creates a tighter dependency between the upload path and the processing operation. Slow processing, transient errors, or sudden bursts of uploads can complicate the user experience and recovery process.

The design goal is to make file storage and file processing separate responsibilities. We want to:

- Accept files without requiring the processing job to finish immediately.
- Buffer events when uploads arrive faster than they can be processed.
- Retry temporary failures.
- Isolate repeatedly failing messages for investigation.
- Limit permissions to what each component needs.
- Make activity and failures visible to operators.

## 2. Architecture overview

The main components are:

| Component | Responsibility |
|---|---|
| Amazon S3 | Stores uploaded objects and emits object-created notifications. |
| Amazon SQS processing queue | Buffers notifications so processing can happen asynchronously. |
| AWS Lambda | Polls the queue through an event source mapping and handles messages in batches. |
| Amazon SQS dead-letter queue (DLQ) | Holds messages that could not be processed after the configured retry limit. |
| AWS CloudWatch Logs | Stores Lambda execution logs for troubleshooting. |
| AWS IAM | Defines which actions the Lambda execution role can perform. |

The flow is deliberately asynchronous. S3 publishes an event notification to SQS; Lambda polls SQS using an event source mapping. This differs from the model where S3 invokes Lambda directly.

### Why put SQS between S3 and Lambda?

SQS acts as a buffer. If a burst of uploads creates more work than Lambda can process immediately, messages can wait in the queue. The queue also gives the consumer a retry mechanism and a place to route messages that repeatedly fail.

A queue does not make processing exactly-once. Standard SQS queues provide at-least-once delivery, so a message may be delivered more than once. The consumer should be designed to tolerate duplicates.

## 3. End-to-end event flow

📷 **[INSERT IMAGE 2 HERE — Event-processing sequence: `images/02-event-flow.png`]**  
*Figure 2. Upload, event notification, queueing, Lambda polling, processing, and logging in sequence.*

Let's walk through the request lifecycle:

1. **A user uploads an object to S3.** The bucket stores the object. The bucket can be configured to send object-created notifications to a designated SQS queue.
2. **S3 publishes a notification.** The queue policy must allow the expected S3 bucket to send messages. Restrict the policy to the intended source bucket and account where applicable.
3. **SQS retains the message.** The message stays in the queue until the consumer handles it successfully or the redrive policy sends it to the DLQ.
4. **Lambda polls the queue.** The Lambda event source mapping retrieves batches of messages and invokes the function.
5. **The function validates and processes each record.** In a real implementation, processing might read object metadata, parse a file, or submit a downstream task. The example handler logs object details as a small demonstration rather than performing expensive file transformations.
6. **Successful records are acknowledged.** Lambda/SQS integration deletes successfully processed messages after invocation handling.
7. **Failures are retried.** With partial batch response support enabled, the function can report individual failed message identifiers so successful records in the same batch do not have to be retried unnecessarily.
8. **Logs support investigation.** Operators can review Lambda logs and queue metrics to understand processing volume and failures.

### A practical note about payloads

S3 event notifications normally contain bucket and object-key details. Object keys in event records are URL-encoded; decode them before using them as literal keys. If the application needs to read the object body, the Lambda execution role also needs narrowly scoped S3 read access. Don't grant object access merely because the event contains a bucket and key.

## 4. Handling failures: retries and a dead-letter queue

Failures are part of normal distributed-system operation. A downstream dependency may time out, a file may be malformed, or the function may encounter a bug.

📷 **[INSERT IMAGE 3 HERE — Retry and dead-letter path: `images/03-retry-dlq.png`]**  
*Figure 3. Failed messages can be retried by SQS/Lambda integration and moved to a dead-letter queue after the configured receive limit.*

A dead-letter queue helps separate messages that need attention from the main processing backlog. The queue's redrive policy defines the maximum receive count before a message is moved to the DLQ.

When a message lands in the DLQ:

- Inspect the body and message attributes to understand the failure.
- Correlate the message with Lambda logs using timestamps and application identifiers.
- Determine whether the issue was transient, data-specific, or caused by a code defect.
- Fix the underlying problem before redriving messages to the source queue.
- Avoid blindly replaying a large DLQ into an unhealthy downstream service.

### Partial batch failures

Lambda can receive multiple SQS messages in one invocation. Without partial batch response handling, one failed record can cause the whole batch to be retried. When `ReportBatchItemFailures` is enabled, the function returns the message identifiers for records that failed, allowing successfully processed records to be acknowledged separately.

The handler must return the correct SQS message identifiers for failures. This improves retry efficiency but does not remove the need for idempotency.

## 5. Idempotency: preparing for duplicate delivery

For standard queues, at-least-once delivery means duplicate processing is possible. For example, a function might complete a side effect but fail before the message is acknowledged. The same message can then be delivered again.

An idempotent operation produces the same effective result when repeated with the same input. Useful techniques include:

- Use a stable business identifier or a combination of bucket, object key, object version, and event metadata to identify the work item.
- Store processing status in a durable data store when the business operation requires deduplication.
- Use conditional writes or unique constraints to prevent duplicate side effects.
- Make downstream APIs idempotent when they support idempotency keys.
- Consider S3 versioning if the processing semantics depend on a particular object version.

The simple example in the repository demonstrates event handling and partial batch failure structure. It is not a complete business-level deduplication system.

## 6. Security design: least privilege and protected storage

📷 **[INSERT IMAGE 4 HERE — Security boundaries: `images/04-security-boundaries.png`]**  
*Figure 4. Each service has a specific permission boundary: S3 may publish to the queue, Lambda may poll the queue and write logs, and bucket access remains private by default.*

Security should be designed into the workflow rather than added after it works.

### S3 bucket controls

The Terraform example configures S3 Block Public Access, server-side encryption, and versioning. These are useful baseline controls, but they do not replace a complete data-protection policy. For production, consider retention requirements, lifecycle rules, access logging where appropriate, and whether a customer-managed KMS key is required.

### Queue policy

The queue policy should permit `s3.amazonaws.com` to send messages only from the intended bucket and account context. Avoid a broad policy that allows arbitrary sources to publish messages to the queue.

### Lambda execution role

The Lambda role should contain only the permissions required for the function to operate: write its CloudWatch logs, receive/delete messages, inspect queue attributes, and access other resources only when the application requires them. The example should be reviewed carefully before production use, including the exact actions and resource ARNs.

### Encryption

S3 server-side encryption protects stored objects. SQS encryption can be configured separately; if using a customer-managed KMS key, ensure the relevant principals have the necessary key permissions. Encryption configuration does not, by itself, determine who is authorized to read a resource.

### Keep credentials out of code

Use an appropriate AWS credential provider or role-based access rather than embedding access keys in source files. Never commit real credentials, account identifiers that you intend to keep private, customer data, or secrets into the repository.

## 7. Observability and operational signals

CloudWatch Logs are the starting point for inspecting function execution, but logs alone are not enough to operate a queue-based workflow.

Monitor signals such as:

- **ApproximateNumberOfMessagesVisible:** messages waiting to be processed.
- **ApproximateAgeOfOldestMessage:** how long the oldest queued message has been waiting.
- **NumberOfMessagesSent / NumberOfMessagesReceived:** useful for understanding queue activity, with the usual caveat that these are approximate queue metrics.
- **Lambda errors and throttles:** indicators that processing is failing or capacity is constrained.
- **DLQ visible message count:** a useful alert signal for messages that need investigation.

For a production deployment, define alarms using the service metrics that matter to the workload, set retention for logs, and document the response procedure when alerts fire. Avoid logging full file contents or sensitive values.

## 8. Cost considerations

The architecture avoids managing long-running servers, but serverless does not mean free. Charges may arise from S3 storage and requests, SQS requests, Lambda invocations and duration, CloudWatch log ingestion and storage, data transfer, and optional encryption or monitoring features.

Before running the example:

1. Check the current AWS Free Tier terms and eligibility for your account. Offerings and eligibility rules can change.
2. Use a dedicated test bucket and a small number of test objects.
3. Configure log retention rather than keeping logs indefinitely by default.
4. Delete test resources after validating the workflow.
5. Review AWS Billing and Cost Management and consider a budget alert. A budget alert is not a hard spending cap and may arrive after charges have accrued.

This article intentionally does not promise a zero-cost deployment. Actual costs depend on your account eligibility, Region, request volume, payload sizes, logging, and usage duration.

## 9. Implementation notes and testing strategy

The companion repository contains a Terraform reference implementation and a Python Lambda handler. The Terraform defines the core infrastructure, including the S3 bucket, processing queue, DLQ, queue policy, Lambda function, execution permissions, logging, and event source mapping.

The code has not been deployed or validated in a live account yet. Before treating it as a working implementation, use a controlled test account and validate the following:

1. Run `terraform fmt -check` and `terraform validate` after initializing the project.
2. Review `terraform plan` and confirm that every resource and permission is expected.
3. Check that the S3 notification destination and SQS queue policy satisfy AWS requirements.
4. Upload a small test object and confirm a notification reaches SQS.
5. Confirm Lambda is invoked and logs appear in CloudWatch Logs.
6. Test a deliberately failing message in a non-production environment and verify retry/DLQ behaviour.
7. Test mixed-success batches and inspect the partial batch response behaviour.
8. Check that a message cannot be published by an unintended source and that the Lambda role cannot access unrelated resources.
9. Review cost and remove resources when testing is complete.

Use the README in the project directory for the exact commands and configuration. Do not run `terraform apply` until you have reviewed the plan, security implications, and potential cost.

## 10. When would I use this architecture?

This pattern is useful when a storage event should start background work and the system benefits from buffering and retry handling. Examples include:

- Validating uploaded CSV files.
- Starting image or document processing.
- Running metadata extraction jobs.
- Kicking off asynchronous data-import workflows.
- Separating ingestion from downstream processing in internal tools.

It may be unnecessary for a tiny workflow where a direct S3-to-Lambda integration is sufficient. It also isn't a universal solution for long-running orchestration, strict ordering, or exactly-once business effects. Those requirements need additional design choices.

## Conclusion

Amazon S3, Amazon SQS, and AWS Lambda can form a useful building block for resilient event-driven processing. S3 stores the input, SQS buffers the work, Lambda processes messages asynchronously, and CloudWatch provides operational visibility. A DLQ creates a controlled place to investigate repeatedly failing messages.

The key production lessons are broader than the services themselves: assume failures, design for duplicate delivery, restrict permissions, monitor queue health, and validate cost before deployment. Those practices help turn a basic serverless flow into a system that is easier to operate responsibly.

## References

- [Amazon S3 event notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [Using Lambda with Amazon SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [Handling errors for an SQS event source in Lambda](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
- [Using dead-letter queues in Amazon SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [Security best practices for Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [AWS Lambda pricing](https://aws.amazon.com/lambda/pricing/)

---

**Author note before publication:** Add your own short paragraph about why you chose this pattern and what you learned while reviewing the implementation. Once you've actually tested it, update the implementation-status note with the specific checks you completed and any limitations you observed. Do not claim deployment or test results before doing them.
