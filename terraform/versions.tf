terraform {
  required_version = ">= 1.9"

  # State backend: currently LOCAL (terraform.tfstate on disk — back it up).
  # To move to HCP later: uncomment the cloud {} block below, create the
  # "norviq" org + "norviq-prod" workspace (Execution Mode: Local), then run
  # `terraform login && terraform init -migrate-state`.
  #
  # cloud {
  #   organization = "norviq"
  #   workspaces {
  #     name = "norviq-prod"
  #   }
  # }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}
