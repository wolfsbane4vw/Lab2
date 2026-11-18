resource "aws_cloudwatch_metric_alarm" "simulated_load_high" {
  alarm_name        = "${var.project_name}-simulated-load-high"
  alarm_description = "Scale the database ASG to five under simulated load"

  namespace   = "Lab2"
  metric_name = "SimulatedLoad"
  unit        = "Percent"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.database.name
  }

  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 70
  treat_missing_data  = "notBreaching"

  alarm_actions = [
    aws_autoscaling_policy.database_scale_out.arn
  ]
}
