terraform {
  backend "s3" {
    bucket         = "cloudops-tfstate-eaf05ade5d"  # Replace with actual bucket name from bootstrap output
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudops-terraform-lock"
  }
}