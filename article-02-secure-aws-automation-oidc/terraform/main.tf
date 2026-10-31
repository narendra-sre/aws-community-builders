data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "AllowSpecificGitHubRepositoryBranch"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions_read_reports" {
  name                 = "github-actions-read-reports"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
  description          = "Short-lived GitHub Actions role restricted to one repository branch."
}

data "aws_iam_policy_document" "read_reports" {
  statement {
    sid       = "ListOnlyReportsPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.demo_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["reports/", "reports/*"]
    }
  }

  statement {
    sid       = "ReadOnlyReportsObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.demo_bucket_name}/reports/*"]
  }
}

resource "aws_iam_role_policy" "read_reports" {
  name   = "read-approved-s3-reports-prefix"
  role   = aws_iam_role.github_actions_read_reports.id
  policy = data.aws_iam_policy_document.read_reports.json
}

output "github_actions_role_arn" {
  description = "Set this value as the AWS_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.github_actions_read_reports.arn
}
