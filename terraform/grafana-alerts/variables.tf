variable "grafana_url" {
  description = "Grafana Cloud stack URL, e.g. https://<stack>.grafana.net"
  type        = string
}

variable "grafana_sa_token" {
  description = "Grafana Cloud service account token with Alerting:Write (create in Administration > Service accounts)"
  type        = string
  sensitive   = true
}

variable "loki_datasource_uid" {
  description = "UID of the Grafana Cloud Loki datasource (Connections > Data sources > Loki > UID in URL)"
  type        = string
}
