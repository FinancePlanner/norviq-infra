variable "hcloud_token" {
  description = "Hetzner Cloud API token (set via HCP workspace variable or TF_VAR_hcloud_token)"
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Name (and hostname / k8s node name) of the k3s server"
  type        = string
  default     = "norviq-green"
}

variable "server_type" {
  description = "Hetzner server type. cx22 = 2 vCPU / 4 GB (amd64 — backend images are linux/amd64 only)"
  type        = string
  default     = "cx22"
}

variable "location" {
  description = "Hetzner location"
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key" {
  description = "SSH public key for root access"
  type        = string
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach SSH (22) and the Kubernetes API (6443). Set to your home/VPN IP."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"] # tighten after first apply
}

variable "k3s_version" {
  description = "Pinned k3s version"
  type        = string
  default     = "v1.35.6+k3s1"
}

variable "pg_volume_size" {
  description = "Size (GB) of the detachable volume holding Postgres data"
  type        = number
  default     = 10
}

variable "rdns_domain" {
  description = "Reverse-DNS hostname for the primary IP"
  type        = string
  default     = "api.norviqa.io"
}
