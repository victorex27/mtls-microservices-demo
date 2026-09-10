# Terraform: mTLS demo infra

Provisions ONE EC2 instance (Ubuntu 22.04) that will run:
- dokku (application platform - deploys gateway/users-service/orders-service)
- Docker + Docker Compose (runs Vault + its 3 Vault Agent sidecars)
- Everything needed to build the app containers on push (herokuish deps)

The instance is bootstrapped via `user_data` (templates/user-data.sh.tpl):
installs Docker, Docker Compose plugin, dokku, and the Vault CLI, then
creates the 3 dokku apps and the shared internal Docker network they'll
attach to. It does NOT deploy your application code - that's
`../scripts/deploy.sh`, run after `terraform apply` completes.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# ssh_allowed_cidr has no default - terraform will refuse to plan/apply
# until you set it. Find your IP with: curl -s https://checkip.amazonaws.com
# then set e.g. ssh_allowed_cidr = "203.0.113.4/32" in terraform.tfvars

terraform init
terraform plan
terraform apply
```

`ssh_allowed_cidr` gates BOTH SSH (22) and Vault's UI/API (8200) in the
security group - see `main.tf`. There's no insecure default here on
purpose: if you want it open to the world, you set "0.0.0.0/0" yourself,
as a deliberate choice, not because that's what came out of the box.

On success, `terraform output` gives you the public IP, an `ssh_command`,
and the generated SSH private key path (`<project_name>-key.pem`, gitignored).

Next: see ../docs/DEPLOYMENT.md for the full deploy walkthrough.

## Destroying

```bash
terraform destroy
```
This does not delete anything from GitHub or locally - only the AWS
resources (EC2 instance, security group, key pair).
