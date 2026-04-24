

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~>20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  eks_managed_node_groups = var.node_groups

  # Enable OIDC provider for IRSA
  enable_irsa = true

  cluster_endpoint_private_access = false
  cluster_endpoint_public_access  = true

  

  tags = var.tags
}