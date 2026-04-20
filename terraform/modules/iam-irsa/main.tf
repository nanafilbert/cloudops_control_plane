

module "irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.20"

  role_name = "${var.namespace}-${var.service_account}-irsa"

  # Use the correct argument name (no "_manager" suffix)
  attach_external_secrets_policy = var.attach_secretsmanager_policy

  # These can be left as defaults (allow all secrets in the account)
  # external_secrets_ssm_parameter_arns = var.parameter_arns
  # external_secrets_secrets_manager_arns = var.secrets_manager_arns
  # external_secrets_kms_key_arns = var.kms_key_arns

  oidc_providers = {
    ex = {
      provider_arn = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account}"]
    }
  }

  tags = var.tags
}