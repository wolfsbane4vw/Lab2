resource "aws_lb" "database" {
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"

  subnets         = sort(data.aws_subnets.default.ids)
  security_groups = [aws_security_group.load_balancer.id]
}

resource "aws_lb_target_group" "database" {
  name        = "${var.project_name}-database"
  port        = 3306
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id
  # Short grace period for the lab's brief test queries.
  deregistration_delay   = 30
  connection_termination = true


  health_check {
    protocol            = "HTTP"
    port                = "9200"
    path                = "/ready"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "database" {
  load_balancer_arn = aws_lb.database.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.database.arn
  }
}
