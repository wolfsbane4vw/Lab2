output "base_ami" {
  description = "Verified Lab1 base image for the future servers and launch templates."
  value = {
    id           = data.aws_ami.lab1.id
    name         = data.aws_ami.lab1.name
    architecture = data.aws_ami.lab1.architecture
    region       = var.aws_region
  }
}

data "aws_instances" "database" {
  instance_state_names = ["running"]

  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.database.name]
  }
  depends_on = [aws_autoscaling_group.database]
}

output "database_public_ips" {
  description = "Public IP addresses of running database ASG instances"
  value       = data.aws_instances.database.public_ips
}

output "database_endpoint" {
  description = "NLB hostname for MariaDB connections on port 3306"
  value       = aws_lb.database.dns_name
}

output "test_client_public_ip" {
  description = "Public IP of the Python test client"
  value       = aws_instance.test_client.public_ip
}


