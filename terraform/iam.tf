resource "aws_iam_role" "database" {
  name = "${var.project_name}-database"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "discovery" {
  name = "${var.project_name}-discovery"
  role = aws_iam_role.database.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ec2:DescribeInstances"
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "database" {
  provider = aws.untagged

  name = "${var.project_name}-database"
  role = aws_iam_role.database.name
}
