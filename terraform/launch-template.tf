resource "aws_launch_template" "database" {
  name_prefix   = "${var.project_name}-database-"
  image_id      = data.aws_ami.lab1.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.database.key_name

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    galera_config = templatefile("${path.module}/templates/galera.cnf.tftpl", {
      cluster_name = "${var.project_name}-galera"
    })

    readiness_script_base64 = filebase64(
      "${path.module}/../scripts/server/galera_readiness.py"
    )

    readiness_service_base64 = filebase64(
      "${path.module}/templates/galera-readiness.service"
    )
  }))


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

}
