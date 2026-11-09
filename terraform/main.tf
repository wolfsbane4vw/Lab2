data "aws_ami" "lab1" {
  owners = ["self"]

  filter {
    name   = "image-id"
    values = [var.ami_id]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
