variable "ansible_hostfile" {}
variable "server_count" {}

variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }

variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }

resource "null_resource" "s3" {
    triggers = {
        server_count = var.server_count
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/init.yml -i ${var.ansible_hostfile} \
                --extra-vars \
                'aws_bot_access_key=${var.aws_bot_access_key}
                aws_bot_secret_key=${var.aws_bot_secret_key}
                do_spaces_region=${var.do_spaces_region}
                do_spaces_access_key=${var.do_spaces_access_key}
                do_spaces_secret_key=${var.do_spaces_secret_key}'
        EOF
    }
}

