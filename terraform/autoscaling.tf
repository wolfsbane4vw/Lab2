resource "aws_autoscaling_group" "database" {
  name = "${var.project_name}-database"

  min_size         = 3
  desired_capacity = 3
  max_size         = 5

  vpc_zone_identifier = sort(data.aws_subnets.default.ids)
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.database.arn]

  launch_template {
    id      = aws_launch_template.database.id
    version = tostring(aws_launch_template.database.latest_version)
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "database_scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.database.name

  policy_type        = "SimpleScaling"
  adjustment_type    = "ExactCapacity"
  scaling_adjustment = 5
  cooldown           = 60
}
