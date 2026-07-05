terraform {
  required_version = ">= 1.9"

  # State + locking only. Execution mode must be set to "Local" in the HCP
  # workspace settings so the hcloud token never leaves this machine/CI.
  cloud {
    organization = "norviq"

    workspaces {
      name = "norviq-prod"
    }
  }

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
