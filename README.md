# Lab2 — MariaDB Galera on AWS

Terraform provisions three Ubuntu instances through an Auto Scaling Group using the Lab1 AMI. Its user_data installs MariaDB/Galera and writes common settings. A laptop utility supplies node identities and peer addresses, initializes or joins the cluster over SSH, and separate utilities check health and replication.

An internet-facing Network Load Balancer (NLB) forwards TCP port 3306 to ASG instances. The ASG allows up to five instances; automatic scaling/joining, controlled scale-in, and recovery automation are still pending.

Terraform manages AWS infrastructure. After deployment, run the utility scripts to initialize the fresh cluster, configure the database client account, and verify health and replication. Run Terraform again when changing infrastructure; database operations use the scripts below.

## Requirements

- Terraform `>= 1.5, < 2.0`, AWS CLI v2, Bash, OpenSSH, OpenSSL, and `jq`.
- AWS lab access, the Lab1 Ubuntu x86_64 AMI in the same account/region, and a default VPC with internet-connected default subnets. Three-AZ placement requires subnets in three AZs.
- All commands below run from the **Lab2 project root**. You run AWS and SSH commands yourself.

## Configure and deploy

For first-time setup, copy the example and edit the values. Keep an existing configuration if already set up:

```bash
cp -i terraform/terraform.tfvars.example terraform/terraform.tfvars
```

```hcl
project_name  = "lab2"
aws_region    = "eu-north-1"
ami_id        = "ami-REPLACE_WITH_LAB1_AMI_ID"
instance_type = "t3.small"
ssh_cidr      = "YOUR_PUBLIC_IPV4/32"
```

Find your public IPv4 with `curl -4 https://checkip.amazonaws.com`. Keep `ssh_cidr` current.

```bash
bash scripts/create-test-key.sh
export AWS_PROFILE=taltech
aws sso login --profile taltech

terraform -chdir=terraform fmt
bash scripts/validate.sh
bash scripts/plan.sh
# Review the successful plan before applying; this starts billable instances.
terraform -chdir=terraform apply tfplan
```

The key script creates `terraform/database-key.pem` and `.pem.pub`, preserving existing files. Keep both. State, keys, real variable files, and plans are Git-ignored; retain local state for future updates and cleanup.

Regenerate `tfplan` after code changes or a failed plan. Updating the launch template affects future instances; it does not replace existing instances or rerun startup scripts. Existing healthy clusters can continue running. New setup expects the common configuration supplied by the updated template.

## Initialize a fresh cluster

Run this sequence only on fresh nodes with MariaDB stopped. **Bootstrap once, on one node only. Do not rerun bootstrap to restart or recover an existing cluster.**

```bash
bash scripts/nodes/discover-nodes.sh
bash scripts/nodes/check-nodes.sh installation
bash scripts/nodes/cluster.sh init
```

`init` checks all nodes for previous Galera state before configuring any, bootstraps one node, then starts the others. It is for fresh setup, not recovery. It waits for readiness and runs the cluster checks afterward.

To add fresh instances to an already healthy cluster:

```bash
bash scripts/nodes/cluster.sh join
```

`join` requires a healthy existing member and never bootstraps. It configures stopped fresh nodes and starts them normally. Running members are retained. It does not recover stopped nodes with previous Galera state. Both operations accept an optional ASG name as their second argument.

## Check a running cluster

```bash
bash scripts/nodes/check-nodes.sh cluster 3
bash scripts/nodes/test-replication.sh
```

Health checks separate node failures from size mismatches. Installation mode checks startup and packages regardless of service state. Use `cluster 5` only when expecting five members; checking does not scale the group.

The replication test writes a uniquely identified row on one node and reads it from every node. It retains its dedicated `lab2_replication_test` database/table and test rows.

## Configure the database client account

After initializing a fresh cluster, run:

```bash
bash scripts/nodes/setup-client.sh
```

The script checks cluster health, prompts for a password twice without displaying it, and creates or updates `lab2_client` through SSH on one node. Galera replicates the account to the other members. The account receives `SELECT` access to `lab2_replication_test`; run the replication test above to create that database and its test rows.

The password is not saved in project files or Terraform state. Rerunning the script sets the account password to the value entered. Run it after rebuilding the entire cluster or to change the password; joining nodes receive the account through Galera without rerunning setup.

## Database load balancer

Get the database hostname with:

```bash
terraform -chdir=terraform output -raw database_endpoint
```

Connect on port 3306. The NLB security group restricts client access to `ssh_cidr`, and the ASG automatically registers and deregisters its instances. TCP health checks verify that port 3306 accepts connections; use `check-nodes.sh cluster` separately to verify Galera synchronization and membership. Client connection testing through the NLB is still pending.

## Node discovery and manual access

All node utilities now discover current instances directly from AWS using your laptop login. No Terraform refresh is needed for their address lists. Terraform outputs remain available as saved snapshots.

For manual access, replace `PUBLIC_IP` with a node address:

```bash
ssh -i terraform/database-key.pem ubuntu@PUBLIC_IP
# On the node, inspect startup failures with:
sudo tail -n 100 /var/log/cloud-init-output.log
```

## Script layout

- `scripts/`: key generation, Terraform validation, and planning.
- `terraform/templates/`: startup script and common Galera configuration supplied by Terraform.
- `scripts/lib/nodes.sh`: shared discovery, validation, and SSH helpers.
- `scripts/nodes/`: cluster initialization/joining, client account setup, health and replication checks, and discovery.

IAM-based node discovery is disabled because of student-account permissions. Discovery and SSH coordination run on your laptop; no personal AWS credentials are copied to nodes. Any earlier IAM resources removed from state still need separate cleanup.

## Cleanup

```bash
terraform -chdir=terraform destroy
```

Review the deletions and retain state until cleanup succeeds. This removes tracked Lab2 infrastructure, not the Lab1 AMI, default VPC/subnets, local keys, or IAM resources previously removed from state. If deletion fails, inspect the reported dependency or permission error rather than deleting state files.
