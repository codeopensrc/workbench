
variable "ami_source" {
  type    = string
  default = ""
}
variable "aws_access_key" {
  type    = string
  default = ""
}
variable "aws_instance_type" {
  type    = string
  default = ""
}
variable "aws_key_name" {
  type    = string
  default = ""
}
variable "aws_region" {
  type    = string
  default = ""
}
variable "aws_secret_key" {
  type    = string
  default = ""
}
variable "consul_version" {
  type    = string
  default = ""
}
variable "digitalocean_image_name" {
  type    = string
  default = ""
}
variable "digitalocean_image_os" {
  type    = string
  default = ""
}
variable "digitalocean_image_size" {
  type    = string
  default = ""
}
variable "digitalocean_region" {
  type    = string
  default = ""
}
variable "do_token" {
  type    = string
  default = ""
}
variable "docker_compose_version" {
  type    = string
  default = ""
}
variable "docker_version" {
  type    = string
  default = ""
}
variable "gitlab_version" {
  type    = string
  default = ""
}
variable "redis_version" {
  type    = string
  default = ""
}
variable "packer_dir" {
  type    = string
  default = ""
}

source "digitalocean" "main" {
    api_token     = "${var.do_token}"
    image         = "${var.digitalocean_image_os}"
    region        = "${var.digitalocean_region}"
    size          = "${var.digitalocean_image_size}"
    snapshot_name = "${var.digitalocean_image_name}"
    ssh_username  = "root"
}

build {
    sources = ["source.digitalocean.main"]

    provisioner "shell" {
        inline = [
            "mkdir -p /tmp/scripts",
            "mkdir -p /home/ubuntu/.ssh"
        ]
    }

    provisioner "file" {
        destination = "/tmp/scripts"
        source      = "${var.packer_dir}/scripts/"
    }

    provisioner "file" {
        destination = "/home/ubuntu/.ssh/authorized_keys"
        source      = "${var.packer_dir}/ignore/authorized_keys"
    }

    provisioner "file" {
        destination = "/root/.ssh/authorized_keys"
        source      = "${var.packer_dir}/ignore/authorized_keys"
    }

    provisioner "shell" {
        inline = [
            "chmod +x /tmp/scripts/init.sh",
            "chmod +x /tmp/scripts/install/install_docker.sh",
            "chmod +x /tmp/scripts/install/install_redis.sh",
            "chmod +x /tmp/scripts/move.sh",
            "sudo bash /tmp/scripts/init.sh -c ${var.consul_version} -d ${var.docker_compose_version} -g ${var.gitlab_version} ${var.gitlab_version != "" ? "-a" : ""}",
            "sudo bash /tmp/scripts/install/install_docker.sh -v ${var.docker_version}",
            "sudo bash /tmp/scripts/install/install_redis.sh -v ${var.redis_version}",
            "sudo bash /tmp/scripts/move.sh"
        ]
    }
}
