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

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
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
