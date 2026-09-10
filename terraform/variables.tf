variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to tag/name all resources"
  type        = string
  default     = "mtls-demo"
}

variable "instance_type" {
  description = "EC2 instance type. All 3 services + Vault run on this one box."
  type        = string
  default     = "t3.medium"
}

variable "ssh_allowed_cidr" {
  description = <<-EOT
    CIDR allowed to reach SSH (22) and Vault's UI/API (8200) on the
    instance. Deliberately has NO default - this repo does not ship a
    "0.0.0.0/0 by default, tighten it later" posture. Set it explicitly,
    e.g. "203.0.113.4/32" (find your IP: curl -s https://checkip.amazonaws.com).
    If you genuinely need it open to the world (rare - e.g. SSH from a
    dynamic IP with no VPN), set "0.0.0.0/0" explicitly so that's a decision
    you made, not a default you inherited.
  EOT
  type = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR, e.g. \"203.0.113.4/32\"."
  }
}

variable "dokku_vhost_enable" {
  description = "Whether to configure dokku VHOST-based routing (needs a domain). false = IP:port routing only."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Optional domain/subdomain pointed at the instance (only used if dokku_vhost_enable = true)."
  type        = string
  default     = ""
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB (dokku + docker images + vault raft data all live here)"
  type        = number
  default     = 30
}
