variable "public_ip" { default = "" }

variable "aws_access_key_id" { default = "" }
variable "aws_secret_access_key" { default = "" }
variable "aws_bot_access_key" { default = "" }
variable "aws_bot_secret_key" { default = "" }

variable "do_spaces_region" { default = "" }
variable "do_spaces_access_key" { default = "" }
variable "do_spaces_secret_key" { default = "" }


# Temporarily disable for initial install - can lock dkpg file if enabled
resource "null_resource" "disable_autoupgrade" {
    provisioner "remote-exec" {
        inline = [
            "sed -i \"s|1|0|\" /etc/apt/apt.conf.d/20auto-upgrades",
            "cat /etc/apt/apt.conf.d/20auto-upgrades"
        ]
    }
    connection {
        host = var.public_ip
        type = "ssh"
    }
}


resource "null_resource" "update_s3" {
    depends_on = [
        null_resource.disable_autoupgrade,
    ]

    provisioner "file" {
        content = <<-EOF
            [default]
            aws_access_key_id = ${var.aws_bot_access_key}
            aws_secret_access_key = ${var.aws_bot_secret_key}
        EOF
        destination = "/root/.aws/credentials"
    }

    provisioner "remote-exec" {
        inline = [
            (var.aws_bot_access_key != "" ? "mc alias set s3 https://s3.amazonaws.com ${var.aws_bot_access_key} ${var.aws_bot_secret_key}" : "echo 0;"),
            (var.do_spaces_access_key != "" ? "mc alias set spaces https://${var.do_spaces_region}.digitaloceanspaces.com ${var.do_spaces_access_key} ${var.do_spaces_secret_key}" : "echo 0;"),
        ]
    }

    connection {
        host = var.public_ip
        type = "ssh"
    }
}


