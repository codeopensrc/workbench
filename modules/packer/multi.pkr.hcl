
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

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

source "amazon-ebs" "main" {
    access_key    = "${var.aws_access_key}"
    ami_name      = "packer-ami_${local.timestamp}-${substr(uuidv4(), 0, 4)}"
    instance_type = "${var.aws_instance_type}"
    region        = "${var.aws_region}"
    secret_key    = "${var.aws_secret_key}"
    source_ami    = "${var.ami_source}"
    ssh_username  = "ubuntu"
    tags = {
        Base_AMI_Name          = "{{ .SourceAMIName }}"
        OS_Version             = "Ubuntu"
        aws_key_name           = "${var.aws_key_name}"
        consul_version         = "${var.consul_version}"
        docker_compose_version = "${var.docker_compose_version}"
        docker_version         = "${var.docker_version}"
        gitlab_version         = "${var.gitlab_version}"
        redis_version          = "${var.redis_version}"
    }
}

source "digitalocean" "main" {
    api_token     = "${var.do_token}"
    image         = "${var.digitalocean_image_os}"
    region        = "${var.digitalocean_region}"
    size          = "${var.digitalocean_image_size}"
    snapshot_name = "${var.digitalocean_image_name}"
    ssh_username  = "root"
}

## Docs for build block
## https://www.packer.io/docs/templates/hcl_templates/blocks/build/provisioner
build {
    sources = [
        "source.digitalocean.main",
        "source.amazon-ebs.main"
    ]

    provisioner "shell" {
        inline = [ "mkdir -p /tmp/scripts" ]
    }

    provisioner "shell" {
        only = ["digitalocean.main"]
        inline = [ "mkdir -p /home/ubuntu/.ssh" ]
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
        only = ["digitalocean.main"]
        destination = "/root/.ssh/authorized_keys"
        source      = "${var.packer_dir}/ignore/authorized_keys"
    }

    provisioner "shell" {
        #max_retries = 5    #Can retry
        inline = [
            "chmod +x /tmp/scripts/init.sh",
            "chmod +x /tmp/scripts/install/install_docker.sh",
            "chmod +x /tmp/scripts/install/install_redis.sh",
            "chmod +x /tmp/scripts/move.sh",
            "sudo bash /tmp/scripts/init.sh -c ${var.consul_version} -d ${var.docker_compose_version} ${var.gitlab_version != "" ? "-g ${var.gitlab_version} -a" : ""}",
            "sudo bash /tmp/scripts/install/install_docker.sh -v ${var.docker_version}",
            "sudo bash /tmp/scripts/install/install_redis.sh -v ${var.redis_version}",
            "sudo bash /tmp/scripts/move.sh"
        ]
    }
}
