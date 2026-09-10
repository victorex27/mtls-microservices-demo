# Deploying to AWS (Terraform + dokku)

Two ways to run this: GitHub Actions (recommended - your AWS credentials
never leave GitHub's secret store or touch your own machine), or fully
manual from your own machine. Both use the exact same Terraform and
scripts underneath.

## Prerequisites

- An AWS account and an IAM user/role with permission to create EC2
  instances, security groups, and key pairs (a scoped policy, not full
  admin, is safer - `AmazonEC2FullAccess` is enough if you don't want to
  hand-write a minimal policy).
- This repo pushed to your own GitHub repo.
- No domain required - the gateway is reached by the EC2 instance's public
  IP. (If you want a real domain + Let's Encrypt on the gateway later, see
  the note at the bottom.)

## Option A: GitHub Actions (recommended)

1. In your repo: **Settings → Secrets and variables → Actions**:
   - Under **Secrets**, add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
   - Under **Variables** (not Secrets - it's not sensitive), add
     `SSH_ALLOWED_CIDR` set to your own IP as a /32, e.g. `203.0.113.4/32`
     (find yours with `curl -s https://checkip.amazonaws.com`). This is
     required - `terraform/variables.tf` has no default for it on purpose,
     so the workflow fails fast with a clear error if you skip this rather
     than silently opening SSH and Vault's UI to the whole internet.
2. **Actions → Deploy to EC2 → Run workflow**, action = `apply`.

This runs `.github/workflows/deploy.yml`, which:
1. `terraform apply`s the EC2 instance (see `terraform/`).
2. Waits for the instance's `cloud-init`/user-data bootstrap to finish.
3. Runs `./scripts/deploy.sh`, which sets up Vault + PKI + dokku apps on
   the instance, then pushes each service's code via `git subtree` to its
   own dokku git remote (triggering a `Dockerfile`-based dokku build+deploy).
4. Issues itself a test-client cert from the freshly-deployed Vault and
   runs `scripts/test-mtls.sh` against the live gateway as a smoke test.

Watch the run in the Actions tab. On success, the job log prints the
gateway URL and Vault UI URL.

**To tear everything down:** run the same workflow with action = `destroy`.

## Option B: manual, from your own machine

Needs: `terraform` (>=1.5), `aws` CLI configured (`aws configure`), `git`,
`ssh`, `rsync`.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars - at minimum set ssh_allowed_cidr to "YOUR_IP/32"

terraform init
terraform apply
cd ..

# Wait ~1-2 min for the instance's user-data script to finish installing
# Docker/dokku/Vault before running deploy.sh, or it'll fail waiting on
# things that aren't installed yet:
ssh -i terraform/mtls-demo-key.pem ubuntu@$(cd terraform && terraform output -raw instance_public_ip) \
  'while [ ! -f /var/log/mtls-demo-bootstrap-done ]; do sleep 5; done; echo ready'

./scripts/deploy.sh
```

`deploy.sh` reads the instance IP and SSH key straight from
`terraform output`, so you don't need to pass them manually (see the
script header for the env var overrides if you do).

## Verifying the deployment

```bash
EC2_IP=$(cd terraform && terraform output -raw instance_public_ip)

# Issue yourself a client cert straight from the deployed Vault
(cd vault && VAULT_ADDR=https://$EC2_IP:8200 ./scripts/issue-test-client-cert.sh)

# Run the full mTLS test suite against the live gateway.
# Note the --resolve trick: the gateway's cert SAN is "api-gateway" (a
# stable identity, not the EC2 IP, which can change on stop/start), so we
# tell curl to connect to the real IP while still verifying/sending SNI
# "api-gateway". See scripts/test-mtls.sh header for details.
./scripts/test-mtls.sh https://api-gateway:3000 "$EC2_IP"
```

You should see the same 4 passing checks as the local test run.

## Redeploying after a code change

```bash
git add -A && git commit -m "change something"
./scripts/deploy.sh --push-only   # skips the Vault/dokku setup, just re-pushes app code
```

`--push-only` re-does the `git subtree split` + push for all 3 services.
dokku rebuilds and redeploys each one whose code actually changed
(dokku diffs the build).

## Rotating certs on the deployed instance

```bash
ssh -i terraform/mtls-demo-key.pem ubuntu@$EC2_IP \
  'cd /home/ubuntu/mtls-microservices && COMPOSE_FILE=vault/docker-compose.vault.yml sudo ./scripts/rotate-certs.sh'
```

## What Terraform actually creates

- 1x EC2 instance (Ubuntu 22.04, `t3.medium` by default - see
  `terraform/variables.tf`), bootstrapped via `user-data` to install
  Docker, dokku, and the Vault CLI (see `terraform/README.md` and
  `terraform/templates/user-data.sh.tpl`).
- 1x security group: SSH (22) and Vault (8200) restricted to
  `ssh_allowed_cidr` (defaults to open - **change this**), gateway (3000)
  and HTTP/HTTPS (80/443, unused by default but there for the
  Let's-Encrypt-later option below) open to the internet. Note
  users-service/orders-service's gRPC ports (50051/50052) are
  **deliberately not opened** in the security group at all - they're only
  reachable over the internal Docker network, never from the public
  internet, regardless of what the app-level mTLS would otherwise allow.
- 1x SSH key pair (generated by Terraform itself, private key saved
  locally as `terraform/mtls-demo-key.pem`, gitignored) - so there's no
  manual "create a key pair in the AWS console" step.

Everything else (Vault, its PKI setup, dokku apps, the actual application
containers) is configured by `scripts/remote-setup.sh` and
`scripts/deploy.sh`, run *after* Terraform, not baked into the AMI/user-data.
That split means fixing a deployment mistake is "edit a script and
re-run `deploy.sh`", never "destroy and recreate the EC2 instance."

## Adding a real domain + Let's Encrypt later

Out of scope for this default (IP-only) setup, but the path is: point a
DNS A record at the instance's public IP, set `dokku_vhost_enable = true`
and `domain_name` in `terraform.tfvars`, `dokku domains:set gateway
your.domain`, and use `dokku letsencrypt:enable gateway` - but only for a
*second*, separate public-facing listener, since dokku's Let's Encrypt
integration terminates TLS at dokku's nginx proxy, which is incompatible
with the app-level mTLS this repo relies on (see
[ARCHITECTURE.md](./ARCHITECTURE.md) for why `proxy:disable` is used on
`gateway`). In practice this means running the gateway on two ports: 443
behind nginx+Let's Encrypt for public plain-HTTPS traffic, 3000 direct for
mTLS-authenticated internal/partner traffic.
