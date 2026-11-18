# Lab2 — MariaDB Galera on AWS

Terraform provisions a three-node Auto Scaling Group (ASG) from the Lab1 AMI, a Network Load Balancer (NLB), and an EC2 instance running a small Python database test client. CloudWatch simulated load triggers scale-out to five nodes; laptop scripts join new members and perform controlled scale-in to three.

## Deploy

Requirements: Terraform `>= 1.5, < 2.0`, AWS CLI v2, Bash, OpenSSH, OpenSSL, and `jq`. No database client is needed on the laptop. Run commands from the project root.

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` for first-time setup. Set the Lab1 AMI, region, and your public IPv4 `/32` in `ssh_cidr`. Keep existing keys and variable files when already configured. Default VPC subnets need internet access for package installation.

```bash
bash scripts/create-test-key.sh  # First-time key setup only.
export AWS_PROFILE=taltech
aws sso login --profile taltech
bash scripts/validate.sh
bash scripts/plan.sh
# Review the plan before applying.
terraform -chdir=terraform apply tfplan
```

Launch-template changes affect future database instances, not existing ones. Startup blocks scheduled automatic package upgrades for this short-lived lab and waits for maintenance already running to finish. Explicit package installation remains enabled.

## Initialize fresh instances

**Use `init` only for fresh instances, never to restart or recover an existing cluster.**

```bash
bash scripts/nodes/check-nodes.sh installation
bash scripts/nodes/cluster.sh init
bash scripts/nodes/test-replication.sh
bash scripts/nodes/setup-client.sh
bash scripts/nodes/test-load-balancer.sh
```

Wait and repeat installation checks if instances are still starting. Initialization bootstraps one member, joins the others, and enables MariaDB startup at boot after verification. Account setup creates the replicated, SELECT-only `lab2_client` account; repeat it after rebuilding the cluster. New joining members inherit the account.

## Scaling demo

Start with three healthy members. Stop any separate watcher or load publisher first.

```bash
bash scripts/demo-scaling.sh
```

Enter the client password once at the beginning. The script publishes high load, waits for AWS to launch five instances, joins fresh nodes, and tests replication and NLB access. It then publishes low load, waits for the alarm to clear, safely removes two nodes, and repeats the tests at three members. It waits for Galera checks before each removal and stops on failures.

Scale-out uses the CloudWatch alarm and ASG policy. Scale-in is coordinated by the laptop, one node at a time: drain NLB connections, stop MariaDB, verify survivors, then terminate the instance and reduce desired capacity. Do not reduce desired capacity directly for scale-in.

## Checks and standalone watcher

```bash
bash scripts/nodes/check-nodes.sh cluster 3  # Use 5 for five members.
bash scripts/nodes/test-replication.sh
bash scripts/nodes/test-load-balancer.sh
```

Cluster checks require matching membership counts and UUIDs plus Primary/Synced/ready/connected status. Replication tests retain their test rows. The NLB test runs Python on the AWS client instance; it verifies SQL access through the NLB, not distribution across every node. NLB health checks use the HTTP Galera readiness endpoint on port 9200; database traffic uses TCP 3306.

Outside the demo, use `bash scripts/nodes/watch-cluster.sh` to detect and join new instances. It waits for SSH, cloud-init, and Galera readiness. Keep one watcher running, the laptop awake, and the AWS login valid. Stop it before manual joining or scale-in. `bash scripts/nodes/scale-in.sh` removes one node per successful run, down to three, after the high-load alarm has cleared.

The watcher runs on the laptop because student IAM permissions prevent our AWS-hosted discovery approach and creation of a dedicated IAM user. It uses the laptop's existing AWS login and SSH key; no personal AWS credentials are copied to nodes. Existing databases continue running without the watcher, but fresh instances need it or an explicit join command to join the cluster.

## Limits and cleanup

Durable backups and automated full-outage recovery are not implemented. If a script fails, inspect the cluster before retrying; a scale-in candidate may already be drained or stopped. Never use `init` for recovery.

Stop the demo, watcher, and load publishers before cleanup:

```bash
terraform -chdir=terraform destroy
```

Destroy removes the database instances and their data. Keep state and SSH keys until cleanup succeeds. Earlier IAM resources removed from state may still require teacher-assisted cleanup; Terraform destroy will not remove them.
