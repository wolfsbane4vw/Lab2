# Lab2 — MariaDB Galera infrastructure

Terraform and utility scripts for building a MariaDB Galera cluster in AWS using the base AMI created in Lab1.

## Current status

The current code creates a launch template, one Auto Scaling Group (ASG), an SSH key pair registration, and a security group. The ASG starts with three EC2 instances and has a minimum capacity of three and maximum of five. It uses the default subnets in the default VPC.

Each new instance installs `mariadb-server`, `mariadb-backup`, `galera-4`, and `rsync` through EC2 user data. The installation script then stops and disables MariaDB. **An inactive MariaDB service is currently the expected result. These machines do not yet form a working Galera cluster.**

Still to implement:

- Node discovery, Galera configuration, coordinated bootstrap, and node joining.
- Database credentials, storage/recovery behavior, and readiness checks.
- Network Load Balancer and database client access through it.
- Simulated-load metrics, scaling policies, and controlled scale-in.

The maximum capacity of five permits growth; no policy currently triggers it. EC2 health checks cover instance health, not Galera membership or readiness. See [plan.md](plan.md) for the intended implementation stages.

## Prerequisites

On the computer running the project, install:

- Terraform 1.5 or newer, below 2.0.
- AWS CLI v2, configured for the lab account.
- Bash, OpenSSH (`ssh` and `ssh-keygen`), and `jq`.
- `curl` if using the public-IP lookup below.

The AWS account needs an existing default VPC and default subnets with working internet access in the selected region. The intended three-AZ layout requires default subnets in three Availability Zones. Instances need outbound access to Ubuntu package repositories.

Reuse the Ubuntu x86_64 AMI built in Lab1. It must be available in the selected region and owned by the authenticated AWS account, as required by the AMI lookup. Lab2 does not rebuild the image or use Lab1's Terraform state.

Commands below run from the **Lab2 project root** unless stated otherwise. The user runs all AWS authentication, planning, deployment, and live node checks.

## 1. Configure Terraform inputs

For the first setup, copy the example without overwriting an existing configuration unintentionally:

```bash
cp -i terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
project_name  = "lab2"
aws_region    = "eu-north-1"
ami_id        = "ami-REPLACE_WITH_LAB1_AMI_ID"
instance_type = "t3.small"
ssh_cidr      = "YOUR_PUBLIC_IP/32"
```

Get the exact AMI ID from Lab1's Packer output or `manifest.json`. Find your current public IPv4 address with:

```bash
curl -4 https://checkip.amazonaws.com
```

Append `/32` to the returned address for `ssh_cidr`. Update it when your public IP changes, then plan and apply the change.

## 2. Create the local SSH key

```bash
bash scripts/create-test-key.sh
```

Despite its original script name, this creates the database key files:

```text
terraform/database-key.pem       Private key used for SSH
terraform/database-key.pem.pub   Public key registered with AWS
```

The script keeps existing files unchanged if either key file already exists. Both files must be present; restore a missing file from your existing key material rather than casually replacing a key used by running instances.

Terraform reads only the public key. Keep the private key for future SSH access. Key files, real variable files, state files, and saved plans are Git-ignored. Commit `.terraform.lock.hcl`.

## 3. Format and validate

```bash
terraform -chdir=terraform fmt
bash scripts/validate.sh
```

The validation script checks formatting, initializes providers with the backend disabled, and validates the configuration. It does not deploy infrastructure or require AWS authentication. Provider initialization may download packages from the Terraform registry.

## 4. Authenticate and create a plan

Use your configured lab profile; `taltech` is the profile used for this project:

```bash
export AWS_PROFILE=taltech
export AWS_REGION=eu-north-1
aws sso login --profile "$AWS_PROFILE"

bash scripts/plan.sh
```

Use the same region as `aws_region` and the Lab1 AMI. The script runs initialization, validation, and planning, saving the result as `terraform/tfplan`.

Review the proposed changes. A new deployment should include the key pair registration, security group, launch template, and ASG. The ASG launches the three instances; they are not individually declared as `aws_instance` resources. There is no standalone `lab2-test` instance in the current code.

If planning fails, resolve the first reported error and rerun the script. An incomplete plan cannot be applied. Regenerate the plan after changing configuration.

## 5. Deploy the current installation stage

This starts billable EC2 instances. It deploys the installation stage described above, not a functioning database cluster.

```bash
terraform -chdir=terraform apply tfplan
```

`tfplan` is the saved plan generated by the script. Being Git-ignored does not prevent Terraform from applying it. This command applies the reviewed plan without another approval prompt.

Terraform completing successfully does not mean cloud-init has finished installing packages. Check the nodes next.

## 6. Display node addresses and check installation

```bash
terraform -chdir=terraform output database_public_ips
bash scripts/nodes/check-nodes.sh
```

The check script reads the saved public IP output and connects to each node as `ubuntu` using `terraform/database-key.pem`. It checks:

1. Cloud-init finishes successfully, waiting up to five minutes per node.
2. The MariaDB version command works.
3. All four required packages are installed.
4. MariaDB's service is `inactive`, as expected at this stage.

It prints `PASS` or `FAIL` for each node, reports the failure count, and returns a nonzero exit status if any node fails. It automatically remembers new SSH host keys and rejects changed keys. It does not refresh IP addresses or check Galera replication.

Outputs are snapshots. After ASG instances change, refresh the saved information before checking them:

```bash
terraform -chdir=terraform apply -refresh-only
terraform -chdir=terraform output database_public_ips
bash scripts/nodes/check-nodes.sh
```

Review and confirm the refresh. Refresh-only updates Terraform state and outputs without changing AWS resources. It requires AWS access; simply reading saved outputs does not.

## Manual SSH and troubleshooting

Select an address from the output and replace `PUBLIC_IP` below:

```bash
ssh -i terraform/database-key.pem ubuntu@PUBLIC_IP
```

If SSH reports overly open key permissions, run this locally:

```bash
chmod 600 terraform/database-key.pem
```

For a connection timeout, check the instance's public IP, your current `ssh_cidr`, and subnet internet routing. For authentication failures, check that the private key matches the public key used when the instance launched.

Run these commands **on the EC2 instance** to inspect installation:

```bash
sudo cloud-init status --wait
mariadb --version
dpkg -l mariadb-server mariadb-backup galera-4 rsync
sudo systemctl is-active mariadb
sudo tail -n 100 /var/log/cloud-init-output.log
```

`systemctl is-active mariadb` prints `inactive` and returns a nonzero status at this stage. That result is expected.

The security group allows SSH only from `ssh_cidr`. Database port 3306 and Galera ports 4567 TCP/UDP, 4568 TCP, and 4444 TCP are allowed between members of the database security group. Direct database access from your laptop is not configured.

## Updating and removing infrastructure

After local changes, format, validate, generate a fresh plan, and review it before applying:

```bash
terraform -chdir=terraform fmt
bash scripts/validate.sh
bash scripts/plan.sh
terraform -chdir=terraform apply tfplan
```

Changing user data creates a new launch template version. Updating the ASG's template version does not automatically rerun startup scripts or replace existing instances. A deliberate replacement/refresh procedure is still needed when deploying new startup behavior to existing nodes.

Desired capacity is ignored by Terraform after initial creation so future runtime scaling can manage it. Changing `desired_capacity` alone in the code will not reset an existing group's capacity.

To remove the resources tracked by this project's state:

```bash
terraform -chdir=terraform destroy
```

Review the deletions before confirming. Keep the local state until cleanup succeeds. This operation does not remove Lab1's AMI, the pre-existing default VPC/subnets, or local SSH keys.

If security group deletion reports `DependencyViolation`, inspect network interfaces using that group and rules in other groups referencing it. Wait for the current Terraform operation to finish before starting another. Repeating a deletion does not remove its dependency; deleting state files does not clean up AWS resources.

## File guide

| File | Purpose |
| --- | --- |
| `terraform/providers.tf` | Terraform/provider versions, region, shared tags |
| `terraform/variables.tf` | Input declarations and validation |
| `terraform/terraform.tfvars.example` | Example inputs |
| `terraform/main.tf` | Lookup of the exact Lab1 AMI |
| `terraform/network.tf` | Default VPC and subnet lookups |
| `terraform/security-groups.tf` | SSH and private cluster traffic rules |
| `terraform/key_pair.tf` | Registration of the local public key |
| `terraform/launch-template.tf` | Instance settings and startup script reference |
| `terraform/autoscaling.tf` | ASG capacity and launch template selection |
| `terraform/outputs.tf` | AMI details and discovery of running-node public IPs |
| `scripts/create-test-key.sh` | Local database SSH key generation |
| `scripts/provisioning/install-database.sh` | EC2 startup script; do not run it on your laptop |
| `scripts/validate.sh` | Formatting, provider initialization, and validation |
| `scripts/plan.sh` | Generation of a saved Terraform plan |
| `scripts/nodes/check-nodes.sh` | Laptop script for SSH checks of the current installation stage |
| `scripts/nodes/discover-nodes.sh` | Laptop script that queries AWS for the ASG nodes and their addresses |
| `plan.md` | Planned cluster, load balancing, and scaling work |
