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
  description = "CIDR allowed to SSH into the instance. Restrict this to your own IP in production use."
  type        = string
  default     = "0.0.0.0/0"
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
