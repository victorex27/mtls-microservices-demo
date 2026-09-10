provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Generated here (rather than requiring a pre-existing AWS key pair) so
# `terraform apply` is fully self-contained. The private key is written
# locally by local-file (gitignored) - see outputs.tf for how to use it.
resource "tls_private_key" "deploy_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deploy_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.deploy_key.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/${var.project_name}-key.pem"
  content         = tls_private_key.deploy_key.private_key_openssh
  file_permission = "0600"
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "mTLS demo: SSH, dokku git+http(s) deploy, gateway, Vault UI/API"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP (dokku app routing / Let's Encrypt HTTP-01, if used)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS - the mTLS-enforcing API Gateway, publicly reachable"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Gateway direct port (used when dokku_vhost_enable = false, e.g. https://IP:3000)"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Vault's own UI/API. Restrict this to your own IP in anything beyond a
  # demo - it's exposed here only so you can watch/administer Vault from
  # outside the box while testing. users-service/orders-service gRPC ports
  # (50051/50052) are deliberately NOT opened here: they're only reachable
  # over the internal dokku docker network, never from the public internet.
  ingress {
    description = "Vault UI/API (restrict to your IP for anything beyond a demo)"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deploy_key.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/templates/user-data.sh.tpl", {
    dokku_version = "v0.35.15"
    vault_version = "1.17.6"
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project_name}" }
}
