locals {
  oidc_url = replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "irsa" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = var.role_name })
}

resource "aws_iam_policy" "secretsmanager" {
  count = var.attach_secretsmanager_policy ? 1 : 0

  name = var.policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "*"
    }]
  })

  tags = merge(var.tags, { Name = var.policy_name })
}

resource "aws_iam_role_policy_attachment" "secretsmanager" {
  count      = var.attach_secretsmanager_policy ? 1 : 0
  role       = aws_iam_role.irsa.name
  policy_arn = aws_iam_policy.secretsmanager[0].arn
}