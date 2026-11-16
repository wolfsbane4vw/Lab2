# Lab2 — MariaDB Galera on AWS

Terraform provisions three Ubuntu instances through an Auto Scaling Group using the Lab1 AMI. Laptop scripts configure and start a MariaDB Galera cluster over SSH, check its health, and test data replication.

The ASG allows up to five instances, but load balancing, automatic scaling/joining, controlled scale-in, and recovery automation are still pending. See [plan.md](plan.md) for the roadmap; some progress notes there may lag behind the code.

## Requirements

- Terraform `>= 1.5, < 2.0`, AWS CLI v2, Bash, OpenSSH, and `jq`.
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
export AWS_REGION=eu-north-1
export AWS_DEFAULT_REGION=eu-north-1
aws sso login --profile taltech

terraform -chdir=terraform fmt
bash scripts/validate.sh
bash scripts/plan.sh
# Review the successful plan before applying; this starts billable instances.
terraform -chdir=terraform apply tfplan
```

The key script creates `terraform/database-key.pem` and `.pem.pub`, preserving existing files. Keep both. State, keys, real variable files, and plans are Git-ignored; retain local state for future updates and cleanup.

Regenerate `tfplan` after code changes or a failed plan. Updating a launch template does not automatically update existing instances or rerun their startup scripts.

## Initialize a fresh cluster

Run this sequence only on fresh nodes with MariaDB stopped. **Bootstrap once, on one node only. Do not rerun bootstrap to restart or recover an existing cluster.**

```bash
bash scripts/nodes/discover-nodes.sh
bash scripts/nodes/check-nodes.sh installation
bash scripts/nodes/configure-cluster.sh
bash scripts/nodes/bootstrap-cluster.sh
bash scripts/nodes/join-cluster.sh
```

Discovery uses your laptop's AWS login. Configuration writes each node's Galera settings; bootstrap selects the first node by sorted instance ID. Joining starts the remaining members normally. All three should report `Primary`, `Synced`, `ON`, size `3`, and the same cluster UUID.

## Check a running cluster

```bash
bash scripts/nodes/check-nodes.sh cluster 3
bash scripts/nodes/test-replication.sh
```

Health checks separate node failures from size mismatches. Installation mode checks startup and packages regardless of service state. Use `cluster 5` only when expecting five members; checking does not scale the group.

The replication test writes a uniquely identified row on one node and reads it from every node. It retains its dedicated `lab2_replication_test` database/table and test rows.

Health checks use saved Terraform IP outputs. Refresh them after instances change:

```bash
terraform -chdir=terraform apply -refresh-only
terraform -chdir=terraform output database_public_ips
```

For manual access, replace `PUBLIC_IP` with a node address:

```bash
ssh -i terraform/database-key.pem ubuntu@PUBLIC_IP
# On the node, inspect startup failures with:
sudo tail -n 100 /var/log/cloud-init-output.log
```

## Script layout

- `scripts/`: key generation, Terraform validation, and planning.
- `scripts/nodes/`: laptop-side discovery, installation checks, and configuration coordination.
- `scripts/provisioning/`: scripts executed on EC2 nodes; do not run them locally.

IAM-based node discovery is disabled because of student-account permissions. Discovery and SSH coordination run on your laptop; no personal AWS credentials are copied to nodes. Any earlier IAM resources removed from state still need separate cleanup.

## Cleanup

```bash
terraform -chdir=terraform destroy
```

Review the deletions and retain state until cleanup succeeds. This removes tracked Lab2 infrastructure, not the Lab1 AMI, default VPC/subnets, local keys, or IAM resources previously removed from state. If deletion fails, inspect the reported dependency or permission error rather than deleting state files.
