terraform {
  backend "s3" {
    bucket         = "cloudops-tfstate-34f1854f9d"  # Replace with actual bucket name from bootstrap output
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile  = true
    encrypt        = true
  }
}