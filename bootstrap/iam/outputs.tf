output "github_actions_role_arn" {
  description = "Role ARN — add as GH_OIDC_ROLE_ARN in GitHub Secrets"
  value       = aws_iam_role.github_actions_role.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}