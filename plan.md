# Lab2 implementation plan

## Scope

Build a MariaDB Galera cluster in AWS using Terraform and utility/startup scripts. Reuse the Ubuntu base AMI built in Lab1. No frontend or backend application is required.

The cluster starts with three database nodes and scales out to five when simulated load increases. Use a launch template, one Auto Scaling Group (ASG), and a Network Load Balancer (NLB).

## Assignment and design

- Provision servers, an Auto Scaling Group, and a load balancer using Terraform in AWS.
- Reference the AMI built in Lab1 from the launch template.
- Use cloud-init/user_data to configure clustered software and coordinate new nodes joining.
- Publish the Terraform code and utility scripts or deployment instructions on GitHub and present a short live demo.
- Set ASG minimum and initial desired capacity to three, and maximum capacity to five. Spread instances across three Availability Zones.
- Simulate load with a custom CloudWatch metric and use a scaling policy to increase capacity from three to five. This demonstrates scaling without requiring a large database workload.
- Three database nodes allow the two survivors to retain quorum after one unexpected failure. Two nodes can run, but cannot provide that same failure tolerance on their own.
- Additional Galera nodes can add read capacity; write throughput does not automatically grow with node count because writes are replicated across the cluster.
- Develop controlled scale-in after successful scale-out. Initial work must prevent uncoordinated automatic scale-in.

## Working approach

- Build and explain one stage at a time, keeping the configuration simple.
- The user implements infrastructure changes with guidance. Edit project files only when explicitly requested or approved; updating this plan does not authorize infrastructure changes.
- Ask before implementing the next stage unless it has already been approved.
- The user runs AWS authentication, planning, deployment, and live checks. Do not access credentials or call external systems without explicit permission.
- Use Lab1 and the sibling demos as local references.

## Steps

1. **Verify the test instance**
   - Completed: the user launched the test instance from the Lab1 AMI and successfully connected over SSH.
   - Keep it temporarily as a reference for the AMI, instance settings, networking, and SSH access.

2. **Define the launch template and ASG structure**
   - Reuse the tested AMI, instance type, SSH key, and security group settings in a launch template.
   - Choose subnets across three Availability Zones and configure restricted SSH and private cluster traffic.
   - Define one ASG with minimum/desired capacity three and maximum capacity five.
   - Agree on the startup/join procedure before deploying the full group. Developing the Terraform structure does not require launching unfinished database nodes.
   - Do not expand the standalone aws_instance resources into the final cluster; the ASG will create the cluster instances.
   - Keep the test instance separate until it can be removed. A launch template does not automatically adopt it into the ASG.
   - Checkpoint: the local configuration describes the intended ASG and launch template, and the user reviews its Terraform plan.

3. **Install MariaDB Galera automatically**
   - Supply startup scripts through Terraform user_data.
   - Install the required packages and configure each node's identity and cluster settings.
   - Decide how database storage and credentials will be managed.
   - Define node identity for dynamically created instances rather than relying on fixed db1/db2/db3 instance resources.
   - Checkpoint: a fresh node configures itself without manual package installation.

4. **Form the cluster**
   - Design discovery of existing members through their private addresses and coordinate the first bootstrap when ASG instances start concurrently.
   - Bootstrap the initial cluster once, then join the other nodes.
   - Define safe behavior for restarts, replacement nodes, and recovery after a full cluster outage.
   - Avoid accidentally bootstrapping an independent cluster during a restart or replacement.
   - Allow replacement and scale-out nodes to discover, join, and synchronize with the existing cluster.
   - Checkpoint: three ASG-managed nodes report healthy membership and replicate database changes.

5. **Add database load balancing**
   - Design database routing and health checks before implementing them.
   - Use a Network Load Balancer with a TCP listener and attach its target group to the ASG. An Application Load Balancer cannot carry MariaDB connections.
   - Ensure health checks account for whether a node is ready to serve database requests, beyond an open TCP port.
   - Checkpoint: database clients can connect through the load-balancing endpoint and unhealthy nodes stop receiving new connections.

6. **Demonstrate simulated load and scale-out**
   - Add a utility script for the user to publish a simulated load metric to CloudWatch.
   - Configure alarms and a scaling policy that grows the group from three to five nodes when the metric is high, respecting the maximum capacity.
   - Account for startup and synchronization time so new nodes receive database connections only when ready.
   - Ensure Terraform configuration and runtime scaling do not fight over desired capacity.
   - Checkpoint: raising the metric triggers scaling, both new nodes join, and all five nodes replicate data and are eligible for traffic.

7. **Implement controlled scale-in and test failures**
   - Define how nodes stop receiving new connections, leave the cluster gracefully, and complete termination. Decide whether lifecycle hooks are needed.
   - Return from five nodes to three using the agreed scale-in procedure while preserving quorum.
   - Verify a failed instance is replaced and the replacement joins the existing cluster.
   - Verify replication and database access through the load-balancing endpoint.
   - Verify continued service after one node fails and safe recovery afterward.
   - Check storage behavior and document the full-cluster recovery procedure in script comments or utility instructions.
   - Remove temporary test resources once they are no longer needed.
   - Checkpoint: the live demo shows three healthy nodes, scale-out to five, controlled return to three, and recovery after a node failure.

## Current progress and next step

- Terraform creates the ASG and supplies installation/common Galera settings through startup templates.
- IAM profile/user creation is blocked by the student account. Discovery and coordination currently run on the laptop using its existing AWS session; no personal credentials are copied to nodes.
- Shared helpers are in `scripts/lib/nodes.sh`. Use `cluster.sh init` only for fresh setup and `cluster.sh join` to add fresh nodes to an existing healthy cluster.
- Health checks support installation and running-cluster modes, with separate size/identity checks. A replication test writes on one node and reads from every member.
- Next: validate the refactored utilities, then add an NLB with a basic Terraform-defined TCP health check. Galera-aware load-balancer readiness can follow.
- Automatic joining during scaling still needs a running laptop coordinator or a supported node-side discovery mechanism. Full outage recovery, persistent-storage strategy, client credentials, simulated-load policies, and controlled scale-in remain unfinished.
- Earlier IAM resources removed from Terraform state still require separate cleanup. Commented IAM experiments have been removed from the project configuration.

