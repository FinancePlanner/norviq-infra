resource "hcloud_ssh_key" "admin" {
  name       = "norviq-admin"
  public_key = var.ssh_public_key
}

# Decoupled from the server: future rebuilds keep this IP, so DNS never
# changes again after the initial cutover.
resource "hcloud_primary_ip" "main_v4" {
  name        = "norviq-main-v4"
  type        = "ipv4"
  datacenter  = "${var.location}-dc14"
  auto_delete = false
}

resource "hcloud_primary_ip" "main_v6" {
  name        = "norviq-main-v6"
  type        = "ipv6"
  datacenter  = "${var.location}-dc14"
  auto_delete = false
}

resource "hcloud_firewall" "k3s" {
  name = "norviq-k3s"

  rule {
    description = "SSH (admin only)"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.admin_cidrs
  }

  rule {
    description = "HTTP"
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "HTTPS"
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "HTTP/3 (QUIC)"
    direction   = "in"
    protocol    = "udp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "Kubernetes API (admin only)"
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = var.admin_cidrs
  }
}

# Postgres data lives here: survives server destruction and re-attaches to a
# rebuilt server. Formatted/mounted at /data by cloud-init.
resource "hcloud_volume" "pg_data" {
  name     = "norviq-pg-data"
  size     = var.pg_volume_size
  location = var.location
  format   = "ext4"
}

resource "hcloud_server" "k3s" {
  name         = var.server_name
  server_type  = var.server_type
  image        = "ubuntu-24.04"
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.k3s.id]

  public_net {
    ipv4 = hcloud_primary_ip.main_v4.id
    ipv6 = hcloud_primary_ip.main_v6.id
  }

  user_data = templatefile("${path.module}/cloud-init/k3s-node.yaml.tftpl", {
    k3s_version = var.k3s_version
    volume_id   = hcloud_volume.pg_data.id
  })

  # Volume is attached after boot; cloud-init waits for the device.
  lifecycle {
    ignore_changes = [user_data] # user_data changes force replacement; bump deliberately
  }
}

resource "hcloud_volume_attachment" "pg_data" {
  volume_id = hcloud_volume.pg_data.id
  server_id = hcloud_server.k3s.id
  automount = false
}

resource "hcloud_rdns" "main_v4" {
  primary_ip_id = hcloud_primary_ip.main_v4.id
  ip_address    = hcloud_primary_ip.main_v4.ip_address
  dns_ptr       = var.rdns_domain
}
