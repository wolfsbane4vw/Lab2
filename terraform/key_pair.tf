# Generate the local key first with: bash scripts/create-test-key.sh
resource "aws_key_pair" "database" {
  key_name   = "${var.project_name}-database-key"
  public_key = file("${path.module}/database-key.pem.pub")
}
