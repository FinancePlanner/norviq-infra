output "server_ipv4" {
  description = "Point A records here (api.norviqa.io, dev-api.norviqa.io, norviq.org, staging.norviq.org)"
  value       = hcloud_primary_ip.main_v4.ip_address
}

output "server_ipv6" {
  description = "AAAA records"
  value       = hcloud_primary_ip.main_v6.ip_address
}

output "pg_volume_id" {
  value = hcloud_volume.pg_data.id
}

output "kubeconfig_hint" {
  value = "ssh root@${hcloud_primary_ip.main_v4.ip_address} 'cat /etc/rancher/k3s/k3s.yaml' — replace 127.0.0.1 with the IP"
}
