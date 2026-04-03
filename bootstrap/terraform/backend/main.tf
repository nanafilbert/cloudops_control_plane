resource "aws_s3_bucket" "terraform_state" {
  bucket = "cloudops_control_plane-tf-state-${var.account_id}" # Unique name

  lifecycle {
    prevent_destroy = true # Safety first!
  }
}

resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}