# Lab2 implementation plan

## Goal and working approach

Provision servers from the Lab1 AMI, a launch template, an ASG, an NLB, and MariaDB Galera using Terraform and necessary utility scripts. Demonstrate three-to-five scale-out, replication, database access through the NLB, and controlled return to three.

- The user implements changes with step-by-step guidance. Ask before editing unless explicitly asked to apply changes. Updating documentation does not authorize infrastructure edits.
- The user runs AWS authentication, deployment, SSH, and live tests. Do not access credentials or call AWS without explicit permission.
- Keep code and README simple; follow the existing file organization and sibling demos.
- The solution uses Terraform, Bash, and a tiny Python test client. Ansible was discarded; ClusterControl was ruled out because the required features need licensing.
- External Terraform modules are an optional bonus. None is currently used.

## Completed and tested

The following live results were confirmed by the user, not independently inspected in AWS:

1. **Infrastructure and initial cluster**
   - Lab1 AMI lookup, launch template, default VPC/subnets, SSH key registration, and security groups.
   - ASG minimum/initial desired capacity three, maximum five; Terraform ignores runtime desired-capacity changes.
   - Startup installs MariaDB/Galera and common settings. `cluster.sh init` supplies identity/peers and bootstraps one fresh member once.
   - Fresh deployment, three synchronized members, matching cluster UUIDs, and replication passed.
2. **Database access and NLB test**
   - TCP/3306 NLB listener and target group attached to the ASG.
   - `setup-client.sh` creates/updates the replicated SELECT-only `lab2_client` account.
   - A separate EC2 test instance runs `scripts/client/test_database.py` using PyMySQL. No database client is installed on the laptop.
   - `test-load-balancer.sh` obtains Terraform outputs, connects by SSH, waits for startup, and runs the Python query through the NLB.
   - The public NLB permits the test instance's public IPv4 /32. Client-IP preservation remains at its default; the earlier self-connection workaround was removed.
   - SQL access through the NLB passed at three, four, and five members. The test verifies a connection, not distribution across all members.
3. **Scale-out and automatic joining**
   - Explicit three-to-five ASG growth and `cluster.sh join` passed, followed by health, UUID, replication, and NLB checks.
   - Shared helpers wait for SSH and cloud-init/package readiness. Join distinguishes SSH errors from an inactive MariaDB service and never bootstraps.
   - `watch-cluster.sh` polls membership every 30 seconds and invokes join on initial startup or changed instance IDs. It stops on discovery/join errors.
   - After controlled scale-in, the watcher successfully detected and joined new instances during another three-to-five scale-out without a manual join command.
4. **Controlled scale-in**
   - `scale-in.sh` removes one node per successful run, never below three.
   - It requires stable ASG membership and healthy databases/targets, selects from an AZ with spare members, drains the NLB target, stops MariaDB, checks the survivors, and terminates that exact instance while decrementing desired capacity.
   - Target-group deregistration delay is 120 seconds with connection termination enabled.
   - The health checker supports excluding the stopped candidate and requires the exact expected number of remaining nodes.
   - Five-to-four and four-to-three both passed, including replication and NLB access. Stop the watcher before scale-in; inspect failures before retrying because a candidate may already be drained or stopped.

## Why the watcher runs on the laptop

The student account could not obtain the IAM role/profile permissions needed by the proposed AWS-side discovery design, or create a dedicated IAM user. The laptop therefore uses its existing AWS login and SSH key for coordination; no personal AWS credentials are copied to instances. This is the accepted approach for the lab.

The laptop must stay awake and authenticated with one watcher running. The databases and load balancer continue to run without it, but new nodes will not join automatically while it is unavailable. It is not a recovery service and must never invoke init automatically.

## Remaining work, in order

1. **Next: simulated-load scaling trigger**
   - Add a Terraform-defined custom CloudWatch metric alarm and scale-out policy that increases desired capacity to five. Keep scale-in explicit through `scale-in.sh`; do not add automatic downscaling.
   - Add a small utility for publishing high/low simulated load with the laptop's existing AWS login. Confirm the required metric/alarm/scaling-policy permissions through user-run operations; do not create IAM resources.
   - Test from three members with the watcher running: publish high load, observe the alarm launch two nodes, and verify five synchronized members, replication, and NLB access.
   - Clear the high-load condition and wait for the alarm to return to OK before controlled scale-in, so the policy does not grow the group during removal.
2. **Readiness and failure handling**
   - TCP target health does not establish Galera readiness. Review how joining nodes are kept out of client traffic until Synced/ready, and test the chosen behavior. A separate Python HTTP readiness service was previously deferred to avoid premature complexity.
   - Test one failed instance being replaced and the watcher joining its fresh replacement. This replacement path has not yet been demonstrated.
   - Check continued SQL access during a single-node failure and readiness/timeout behavior on failed startup. Stop on unsafe states rather than repeatedly bootstrapping or restarting nodes.
3. **Restart, storage, and recovery limits**
   - Startup currently disables MariaDB; define and test normal reboot behavior separately from fresh initialization.
   - Document data-volume lifetime, backup/persistence limits, and full-outage recovery. No durable backup or automated full-outage recovery strategy is implemented. Never recommend init for an existing/stopped cluster.
4. **Optional bonus and submission**
   - Consider an external Terraform NLB module only after the main demonstration works. Review resource/state migration before replacing existing blocks; a local module or provider alone is not the external-module bonus.
   - Keep README/plan accurate, prepare a short demo, and publish required code/instructions when requested.
   - Confirm whether the original temporary test instance remains and clean it up when no longer needed.

## Resume next session

Last reported cluster size: five, after successful watcher-driven scale-out. Current AWS state and whether the watcher is still running must be confirmed by the user; do not assume resources still exist.

1. Renew the laptop AWS login if needed.
2. Check the expected current cluster size and run replication/NLB tests if state has changed or is uncertain. Do not rerun init on existing nodes.
3. Start implementing the simulated-load alarm, scale-out policy, and metric-publishing utility. Safely return to three with the watcher stopped before testing the new trigger.

Earlier IAM role/profile resources were removed from Terraform state and may still exist in AWS. They need separate teacher-assisted cleanup; Terraform destroy will not remove them. Keep state and SSH keys until infrastructure cleanup succeeds.

## Pre-submission code review assessment — 2026-11-18

The current working files have a sensible structure for this lab. Strengths include explicit separation of initialization and joining, Galera health and cluster-identity checks, and controlled scale-in that drains connections, stops MariaDB, verifies survivors, then terminates the selected instance. The following assessment reflects local code review, not a live AWS test. Some earlier progress notes above are stale; reconcile them before submission.

### Changes to prioritize

1. **High: keep the watcher alive during instance replacement.** `scripts/nodes/watch-cluster.sh` requires at least three running instances on every poll. If one of three instances fails and discovery temporarily returns two, the watcher exits before the replacement arrives. This was reproduced with mocked discovery. Poll through a bounded replacement window, report degraded capacity, and join the fresh replacement when it becomes available. Keep the refusal to bootstrap automatically.
2. **High: enforce the low-load condition inside standalone scale-in.** `scripts/nodes/scale-in.sh` never reads the CloudWatch alarm; only `scripts/demo-scaling.sh` waits for it to clear. Direct scale-in can therefore compete with the active scale-out policy. Require the alarm to be `OK` before draining and check again before termination. Refuse to proceed if the alarm is missing or cannot be read. This reduces the conflict risk but is not a lock against concurrent scaling activity.
3. **Medium: define application-failure handling.** The ASG uses EC2 health checks, so an instance with failed MariaDB or readiness service can remain in the group while the NLB rejects it. The watcher only reacts to changed instance IDs. Either document this limitation explicitly or implement deliberate application-failure handling. Do not simply enable ELB-based replacement without coordinating slow joins and intentional shutdowns during scale-in. AWS behavior reference: https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html.
4. **Medium: address stale peer addresses before claiming reliable reboot/rejoin.** `scripts/nodes/cluster.sh` writes seed IPs for fresh nodes but leaves existing running nodes' peer configuration unchanged. After enough replacements, a surviving node may have no reachable peer in its saved list when it restarts. Define a safe way to refresh peer configuration after membership changes and test reboot/rejoin after replacements. This is a code-derived risk, not a live reproduced failure. MariaDB reference: https://mariadb.com/docs/galera-cluster/reference/galera-cluster-system-variables.
5. **Medium: make script configuration consistent with Terraform.** Scripts default separately to ASG `lab2-database`, profile `taltech`, and region `eu-north-1`. Changing Terraform's `project_name` or `aws_region` does not change these defaults. Prefer Terraform outputs for the ASG name and region, or clearly document the required script arguments and environment variables, including `AWS_PROFILE` and `AWS_REGION`.
6. **Before submission: include all required source files and reconcile documentation.** At review time, essential files were untracked, including `terraform/cloudwatch.tf`, the readiness Python script/service, and scaling demo utilities. Ensure they are included in the submitted commit. Earlier sections of this plan still call implemented scaling/readiness features future work and describe a 120-second deregistration delay; the current code uses 30 seconds. Distinguish implemented behavior from behavior actually demonstrated live, and update the resume instructions accordingly.

### Folder structure and naming

- Keep `terraform/`, `terraform/templates/`, and `scripts/lib/`; more modules or directory layers are not necessary for this lab.
- Consider renaming `scripts/create-test-key.sh` to `create-ssh-key.sh`, since the key also serves database nodes.
- Consider renaming `scripts/nodes/setup-client.sh` to `configure-client-account.sh`, since it configures a database account rather than provisioning the client host.
- Optionally move replication and NLB checks into `scripts/checks/` to distinguish checks from node lifecycle operations. Update all callers and README commands if files move.
- Use one Terraform filename convention; `key_pair.tf` currently differs from the hyphenated filenames. Renaming a `.tf` file does not require renaming its resource blocks.

### Verification and remaining evidence

Local checks passed: Terraform formatting and validation, Bash syntax for all shell scripts, Python syntax, whitespace checks, and nine mocked readiness status/failure cases. A mocked watcher run confirmed that two discovered nodes cause it to exit. These checks do not establish live infrastructure resilience.

No real AWS API calls, SSH connections, load-metric publishing, demo execution, or infrastructure changes were performed during this review. Source code was not changed by the review.

Before submission, obtain live evidence for a complete three-to-five-to-three demo, a failed instance being replaced while the watcher remains running, SQL access during a single-node failure, and reboot/rejoin behavior. Keep full-outage recovery and durable-backup limitations explicit. The original assignment rubric was not available in the repository; confirm that simulated load and laptop-coordinated scale-in satisfy its automation requirements.
