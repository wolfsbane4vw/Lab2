resource "aws_instance" "test_client" {
  ami           = data.aws_ami.lab1.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.database.key_name

  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.test_client.id]

  user_data = templatefile(
    "${path.module}/templates/test-client-user-data.sh.tftpl",
    {
      client_script_base64 = filebase64(
        "${path.module}/../scripts/client/test_database.py"
      )
    }
  )
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-test-client"
  }
}
