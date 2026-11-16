resource "aws_launch_template" "database" {
  name_prefix   = "${var.project_name}-database-"
  image_id      = data.aws_ami.lab1.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.database.key_name
  user_data     = filebase64("${path.module}/../scripts/provisioning/install-database.sh")

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.database.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-database"
      Role = "database"
    }
  }

  #iam_instance_profile {
  #  name = aws_iam_instance_profile.database.name
  #}
}
