# Attach AdministratorAccess (narrow down for production)
resource "aws_iam_role_policy_attachment" "gh_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Cost Explorer access for FinOps
resource "aws_iam_role_policy" "gh_cost_explorer" {
  name = "gh-cost-explorer"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetDimensionValues",
          "ce:GetTags"
        ]
        Resource = "*"
      }
    ]
  })
}