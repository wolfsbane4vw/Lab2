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
    description     = "MariaDB through the NLB"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
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

  ingress {
    description     = "Galera readiness checks from the NLB"
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "load_balancer" {
  name        = "${var.project_name}-nlb"
  description = "MariaDB access through the load balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "MariaDB from the Python test client"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.test_client.public_ip}/32"]

  }

  egress {
    description = "MariaDB traffic to database nodes"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
  egress {
    description = "Galera readiness checks"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_security_group" "test_client" {
  name        = "${var.project_name}-test-client"
  description = "SSH access to the Python database test client"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
