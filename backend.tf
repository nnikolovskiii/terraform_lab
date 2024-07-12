terraform {
  backend "s3" {
    bucket         = "finki-rasporedi-bucket"
    key            = "FinkiRasporedi/development/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
