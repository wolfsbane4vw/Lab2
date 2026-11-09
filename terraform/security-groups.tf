resource "aws_security_group" "database" {
  name        = "${var.project_name}-database"
  description = "SSH and private MariaDB Galera cluster traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "MariaDB between cluster members"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Galera replication TCP"
    from_port   = 4567
    to_port     = 4567
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Galera replication TCP"
    from_port   = 4567
    to_port     = 4567
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "Galera incremental state transfer"
    from_port   = 4568
    to_port     = 4568
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Galera full state transfer"
    from_port   = 4444
    to_port     = 4444
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
