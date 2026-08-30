variable "region" {
  default = "us-east-1"
}

variable "github_repo" {
  description = "Your GitHub repository in format 'owner/repo'"
  type        = string
  default     = "nanafilbert/cloudops_control_plane"
}