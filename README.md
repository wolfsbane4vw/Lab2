# Lab2 — MariaDB Galera on AWS

Terraform provisions a three-node ASG from the Lab1 AMI, a Network Load Balancer (NLB), and a separate EC2 instance running a small Python test client. Startup scripts install MariaDB/Galera; laptop utilities initialize the cluster and join new members.

Tested: three-to-five scale-out with watcher-driven joining, controlled five-to-three scale-in, replication, and SQL access through the NLB. The simulated-load metric and automatic scaling policy are the next step. Full-outage recovery and durable backups are not implemented.

## Requirements and deployment

Use Terraform `>= 1.5, < 2.0`, AWS CLI v2, Bash, OpenSSH, OpenSSL, and `jq`. Database software and the Python test client run on AWS; no database client is needed on the laptop. Run commands from the project root.

For first-time setup, copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`. Set the Lab1 AMI ID, region, and your public IPv4 `/32` in `ssh_cidr`. Keep existing variable and key files when already configured. The default VPC/subnets must provide internet access for package installation.

```bash
bash scripts/create-test-key.sh
export AWS_PROFILE=taltech
aws sso login --profile taltech
terraform -chdir=terraform fmt
bash scripts/validate.sh
bash scripts/plan.sh
# Review the plan before applying; AWS resources incur charges.
terraform -chdir=terraform apply tfplan
```

Keep the SSH key pair and Terraform state. Regenerate the plan after configuration changes. Launch-template changes affect future instances; they do not rerun startup on existing database nodes. ASG desired capacity is ignored by Terraform so runtime scaling can manage it.

## Fresh cluster setup

**Run init only on fresh instances, never to restart or recover an existing cluster.**

```bash
bash scripts/nodes/check-nodes.sh installation
bash scripts/nodes/cluster.sh init
bash scripts/nodes/test-replication.sh
bash scripts/nodes/setup-client.sh
bash scripts/nodes/test-load-balancer.sh
```

`init` checks all nodes before changes, bootstraps one member, and joins the others. Account setup prompts for a password and creates `lab2_client` with SELECT access to the test database. Run it again after rebuilding the entire cluster or to change the password; joining nodes inherit the account.

## Checks

```bash
bash scripts/nodes/check-nodes.sh cluster 3  # Use 5 for a five-node cluster.
bash scripts/nodes/test-replication.sh
bash scripts/nodes/test-load-balancer.sh
```

Health checks verify expected membership, matching cluster UUIDs, and Primary/Synced/ready/connected status. Replication testing retains its test rows. The NLB test prompts for the client password and runs Python on the AWS test instance to read test data through the NLB. NLB TCP health checks alone do not verify Galera synchronization.

## Automatic joining: laptop watcher

The student account cannot create the IAM role/profile needed by our AWS-hosted discovery approach, or a dedicated IAM user. The watcher therefore uses the laptop's existing AWS login to discover ASG instances and SSH to configure them. No personal AWS credentials are copied to nodes.

After initial cluster setup, start the watcher in a separate terminal:

```bash
bash scripts/nodes/watch-cluster.sh
```

Keep the laptop awake, the terminal running, and the AWS login valid. The watcher checks membership every 30 seconds and joins new instances after waiting for SSH, cloud-init, and package installation. It never bootstraps and stops on errors. Run only one watcher; avoid running manual join operations alongside it. Stop it with Ctrl+C.

To demonstrate scale-out, leave the watcher running and run this in another terminal:

```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name lab2-database \
  --desired-capacity 5 \
  --profile taltech \
  --region eu-north-1
```

Wait for the watcher to verify five members, then run the replication and NLB tests. Capacity changes are currently explicit; CloudWatch-triggered scaling is not implemented yet.

## Controlled scale-in

**Stop the watcher first.** Run:

```bash
bash scripts/nodes/scale-in.sh
```

Each successful run removes one node, down to a minimum of three. It checks health, selects a node from an AZ with spare capacity, drains NLB connections, stops MariaDB, verifies the survivors, and terminates the selected instance while reducing desired capacity.

For five-to-three, run it twice, proceeding to the second run only after the first succeeds. Test replication and NLB access afterward. If scale-in fails, inspect the error before retrying: the candidate may already be drained or stopped. Do not reduce desired capacity directly for scale-in.

## Files and cleanup

- `terraform/`: AWS resources and startup templates.
- `scripts/lib/nodes.sh`: shared discovery, SSH, and readiness helpers.
- `scripts/nodes/`: cluster setup, watcher, checks, account setup, and scale-in.
- `scripts/client/test_database.py`: read-only Python test through the NLB.

For explicit joining without the watcher, use `bash scripts/nodes/cluster.sh join`. Optional address inspection: `bash scripts/nodes/discover-nodes.sh`.

Stop the watcher before cleanup:

```bash
terraform -chdir=terraform destroy
```

Review deletions and retain state until cleanup succeeds. Earlier IAM resources removed from state may still need teacher-assisted cleanup; this destroy will not remove them.
