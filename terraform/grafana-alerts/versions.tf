terraform {
  required_version = ">= 1.9"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.13"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_sa_token
}
