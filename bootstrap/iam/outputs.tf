output "github_oidc_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}