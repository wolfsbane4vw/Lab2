resource "aws_autoscaling_group" "database" {
  name = "${var.project_name}-database"

  min_size         = 3
  desired_capacity = 3
  max_size         = 5

  vpc_zone_identifier = sort(data.aws_subnets.default.ids)
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.database.id
    version = tostring(aws_launch_template.database.latest_version)
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
