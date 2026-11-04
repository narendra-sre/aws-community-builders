# Detecting and Remediating AWS Infrastructure Drift Using Terraform and CloudTrail

## Introduction

Infrastructure as Code (IaC) has become an important part of modern cloud infrastructure management. Tools such as Terraform allow engineering teams to provision, configure, and manage cloud resources consistently through declarative configuration files.

However, managing infrastructure through code does not guarantee that every change will always happen through code.

In real-world environments, administrators or engineers may manually modify AWS resources through the AWS Management Console or AWS CLI. These changes can cause the actual infrastructure to differ from the configuration maintained in Terraform.

This situation is known as **infrastructure drift**.

In this article, I'll demonstrate how to introduce infrastructure drift deliberately in AWS, detect it using Terraform, investigate the manual modification using AWS CloudTrail, and restore the desired configuration using Terraform.

We'll use an Amazon EC2 instance and its tags as a simple but practical example.

## 1. Understanding Infrastructure Drift

Infrastructure drift occurs when the actual configuration of a cloud resource differs from the desired configuration defined in Infrastructure as Code.

Consider an EC2 instance managed through Terraform with the following tags:

```hcl
tags = {
  Name        = "Terraform infrastructure drift"
  Environment = "development"
  ManagedBy   = "Terraform"
}
```

Now imagine an administrator manually changes the Environment tag through the AWS Console:

```text
Environment = production
```

The actual AWS resource now differs from the Terraform configuration.

Terraform still declares:

```text
Environment = development
```

But AWS reports:

```text
Environment = production
```

This difference is infrastructure drift.

Drift can create configuration inconsistencies, unexpected infrastructure behavior, security risks, and difficulties during infrastructure maintenance.

## 2. Architecture and Technology Stack

The demonstration uses the following components:

* Terraform: Infrastructure provisioning, drift detection, and remediation.
* Amazon EC2: The AWS resource used for the drift experiment.
* Amazon VPC security group: Controls network access to the EC2 instance.
* AWS CloudTrail: Records the API activity associated with the manual change.
* AWS CLI: Inspects AWS resources and retrieves audit events.

The implementation is performed in the AWS Asia Pacific (Hyderabad) Region (`ap-south-2`).

**Architecture flow:**

Terraform provisions an EC2 instance. A manual modification changes its Environment tag. Terraform detects the difference, CloudTrail provides an audit record of the modification, and Terraform restores the declared configuration.

[Insert terraform-drift-architecture.svg here]

## 3. Provisioning Infrastructure Using Terraform

The first step is to define the required AWS infrastructure using Terraform.

The demonstration provisions:

* One Amazon EC2 instance.
* One security group.
* An Amazon Linux 2023 AMI discovered dynamically through a Terraform data source.

The EC2 instance uses the `t3.micro` instance type.

### AMI discovery

Instead of hardcoding an AMI ID, Terraform uses an AWS data source to discover a suitable Amazon Linux 2023 image.

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values  = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values  = ["hvm"]
  }
}
```

### EC2 resource

The EC2 instance is configured with the discovered AMI and the selected instance type.

```hcl
resource "aws_instance" "drift_demo" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.drift_demo.id]

  tags = {
    Name        = var.project_name
    Environment = "development"
    ManagedBy   = "Terraform"
  }
}
```

The Environment tag is important because we'll intentionally modify it outside Terraform.

### Terraform initialization and validation

Before provisioning, I initialized and validated the Terraform configuration.

```powershell
terraform init
terraform fmt -recursive
terraform validate
```

I generated an execution plan:

```powershell
terraform plan -out=tfplan
```

After reviewing the plan, I deployed the infrastructure:

```powershell
terraform apply tfplan
```

The deployment created the EC2 instance and security group.

## 4. Establishing the Initial Infrastructure State

Before introducing drift, I verified the actual AWS resource configuration.

I retrieved the EC2 instance ID:

```powershell
$instanceId = terraform output -raw instance_id
```

I then inspected the EC2 tags using AWS CLI:

```powershell
aws ec2 describe-tags `
  --filters "Name=resource-id,Values=$instanceId" `
  --region ap-south-2 `
  --query "Tags[].{Key:Key,Value:Value}" `
  --output table
```

The initial configuration was:

| Tag         | Value                           |
| ----------- | ------------------------------- |
| Name        | Terraform infrastructure drift  |
| Environment | development                     |
| ManagedBy   | Terraform                       |

I also ran:

```powershell
terraform plan
```

Terraform reported:

```text
No changes. Your infrastructure matches the configuration.
```

This established our baseline: the actual AWS infrastructure matched the declared Terraform configuration.

[Insert initial EC2 tags screenshot here]

## 5. Introducing Infrastructure Drift

To simulate a real-world manual infrastructure change, I modified the Environment tag directly through the AWS Management Console.

I navigated to:

EC2 → Instances → Select instance → Tags → Manage tags.

I changed:

```text
Environment = development
```

to:

```text
Environment = production
```

I did not modify the Terraform configuration.

This is important: the difference was introduced directly in AWS, not through Terraform.

I verified the updated tag using AWS CLI.

```powershell
aws ec2 describe-tags `
  --filters "Name=resource-id,Values=$instanceId" `
  --region ap-south-2 `
  --query "Tags[].{Key:Key,Value:Value}" `
  --output table
```

The actual AWS configuration now showed:

| Tag         | Value                           |
| ----------- | ------------------------------- |
| Name        | Terraform infrastructure drift  |
| Environment | production                      |
| ManagedBy   | Terraform                       |

The Terraform configuration still declared `Environment = development`.

We had successfully introduced infrastructure drift.

[Insert manual EC2 tag modification screenshot here]

## 6. Detecting Infrastructure Drift Using Terraform

The next step was to determine whether Terraform could identify the difference.

I executed:

```powershell
terraform plan
```

Terraform refreshed its view of the managed resource and compared the observed infrastructure with the declared configuration.

The plan identified an in-place update to the EC2 instance tags.

The relevant difference was:

```text
Environment = production -> development
```

The `~` symbol in Terraform's plan output indicates that the resource is being updated in place.

To preserve the execution plan, I generated a saved plan:

```powershell
terraform plan -out=drift-plan
```

I also exported the plan in JSON format:

```powershell
terraform show -json drift-plan |
  Out-File -Encoding utf8 ..\evidence\terraform-plan-drift.json
```

This demonstrated that Terraform had detected the difference between the actual AWS resource and the desired configuration.

[Insert Terraform drift detection screenshot here]

## 7. Investigating Manual Changes Using AWS CloudTrail

Detecting drift is important, but understanding how the change occurred is equally important.

For this, I used AWS CloudTrail.

When EC2 tags are created or modified through AWS APIs, CloudTrail records the `CreateTags` management event.

I queried the CloudTrail event history:

```powershell
aws cloudtrail lookup-events `
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateTags `
  --max-results 50 `
  --region ap-south-2 `
  --output json
```

I inspected the event associated with the EC2 instance.

The event provides information such as:

* Event name and time.
* AWS Region.
* Identity that performed the operation.
* Resource affected.
* Requested tag values.

The CloudTrail record provided an audit trail for the manual infrastructure modification.

By comparing the initial EC2 tag evidence with the CloudTrail event and the drifted configuration, I could establish what changed and investigate the corresponding API activity.

[Insert CloudTrail event screenshot here]

## 8. Remediating Infrastructure Drift

After identifying the difference, I reviewed the Terraform execution plan.

The proposed change was:

```text
Environment = production -> development
```

Since the desired configuration was `development`, I proceeded with the reviewed plan.

```powershell
terraform apply drift-plan
```

Terraform applied the proposed update and restored the Environment tag.

I verified the result using AWS CLI:

```powershell
aws ec2 describe-tags `
  --filters "Name=resource-id,Values=$instanceId" `
  --region ap-south-2 `
  --query "Tags[].{Key:Key,Value:Value}" `
  --output table
```

The Environment tag was restored to:

```text
Environment = development
```

The EC2 instance itself was not replaced. The correction was an in-place tag update.

## 9. Final Validation

To verify that the infrastructure was back in the desired state, I executed:

```powershell
terraform plan
```

Terraform reported:

```text
No changes. Your infrastructure matches the configuration.
```

This confirmed that the observed AWS configuration matched the Terraform configuration after remediation.

[Insert final Terraform no-drift screenshot here]

## 10. Key Learnings

Through this implementation, I gained practical experience with several important infrastructure management concepts.

**1. Infrastructure drift**

Manual changes outside Infrastructure as Code can cause differences between desired and actual infrastructure.

**2. Terraform state and refresh**

Terraform uses its state and refresh behavior to understand managed resources and compare them with the declared configuration.

**3. Drift detection**

`terraform plan` helps identify differences and presents proposed changes for review.

**4. CloudTrail auditing**

CloudTrail provides an audit trail of AWS API activity, helping engineers investigate infrastructure modifications.

**5. Controlled remediation**

Terraform does not automatically correct every detected difference. Engineers must review the proposed changes and explicitly apply them.

**6. Infrastructure governance**

Teams should establish clear processes for infrastructure changes and minimize unmanaged manual modifications.

## Conclusion

Infrastructure drift is a common challenge in cloud environments where infrastructure can be modified through multiple access paths.

In this demonstration, I provisioned an EC2 instance using Terraform, deliberately modified its tag through the AWS Console, detected the resulting drift using Terraform, investigated the API activity using AWS CloudTrail, and restored the desired configuration.

The final Terraform plan confirmed that the infrastructure matched the declared configuration again.

This exercise demonstrates how Terraform and CloudTrail can complement each other: Terraform helps identify and correct configuration differences, while CloudTrail provides an audit trail for investigating AWS API activity.

The complete Terraform implementation and sanitized evidence are available in my GitHub repository.

**GitHub repository:** [Insert your AWS Community Builders repository URL]

---
