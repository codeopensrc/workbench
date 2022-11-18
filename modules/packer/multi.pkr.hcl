variable "packer_image_name" {
  type    = string
  default = ""
}
variable "packer_image_size" {
  type    = string
  default = ""
}
variable "ami_source" {
  type    = string
  default = ""
}
variable "aws_access_key" {
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
variable "digitalocean_image_os" {
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
variable "az_subscriptionId" {
  type    = string
  default = ""
}
variable "az_tenant" {
  type    = string
  default = ""
}
variable "az_appId" {
  type    = string
  default = ""
}
variable "az_password" {
  type    = string
  default = ""
}
variable "az_region" {
  type    = string
  default = ""
}
variable "az_resource_group" {
  type    = string
  default = ""
}
variable "az_image_publisher" {
  type    = string
  default = ""
}
variable "az_image_offer" {
  type    = string
  default = ""
}
variable "az_image_sku" {
  type    = string
  default = ""
}
variable "az_image_version" {
  type    = string
  default = ""
}
variable "docker_version" {
  type    = string
  default = ""
}
variable "buildctl_version" {
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
variable "kubernetes_version" {
  type    = string
  default = ""
}
variable "helm_version" {
  type    = string
  default = ""
}
variable "skaffold_version" {
  type    = string
  default = ""
}
variable "packer_dir" {
  type    = string
  default = ""
}


source "amazon-ebs" "main" {
    access_key    = "${var.aws_access_key}"
    ami_name      = "${var.packer_image_name}"
    instance_type = "${var.packer_image_size}"
    region        = "${var.aws_region}"
    secret_key    = "${var.aws_secret_key}"
    source_ami    = "${var.ami_source}"
    ssh_username  = "ubuntu"
    tags = {
        Base_AMI_Name          = "{{ .SourceAMIName }}"
        OS_Version             = "Ubuntu"
        aws_key_name           = "${var.aws_key_name}"
        consul_version         = "${var.consul_version}"
        docker_version         = "${var.docker_version}"
        gitlab_version         = "${var.gitlab_version}"
        redis_version          = "${var.redis_version}"
        kubernetes_version     = "${var.kubernetes_version}"
    }
}

source "digitalocean" "main" {
    api_token     = "${var.do_token}"
    image         = "${var.digitalocean_image_os}"
    region        = "${var.digitalocean_region}"
    size          = "${var.packer_image_size}"
    snapshot_name = "${var.packer_image_name}"
    ssh_username  = "root"
}

source "azure-arm" "main" {
    os_type            = "Linux"
    subscription_id    = var.az_subscriptionId
    tenant_id          = var.az_tenant
    client_id          = var.az_appId
    client_secret      = var.az_password
    location           = var.az_region
    managed_image_name = var.packer_image_name
    vm_size            = var.packer_image_size
    azure_tags = {
        image_name             = var.packer_image_name
        os_version             = var.az_image_sku
        consul_version         = var.consul_version
        docker_version         = var.docker_version
        gitlab_version         = var.gitlab_version
        redis_version          = var.redis_version
        kubernetes_version     = var.kubernetes_version
    }
    #
    image_publisher = var.az_image_publisher
    image_offer= var.az_image_offer
    image_sku = var.az_image_sku
    image_version = var.az_image_version
    managed_image_resource_group_name = "packer-${var.az_resource_group}"
    #os_disk_size_gb = var.az_image_os.os_disk_size_gb
    #capture_container_name = "images"
    #capture_name_prefix = "packer"
    #storage_account = "virtualmachines"
    #resource_group_name = "packerdemo"
}

## Docs for build block
## https://www.packer.io/docs/templates/hcl_templates/blocks/build/provisioner
build {
    sources = [
        "source.digitalocean.main",
        "source.amazon-ebs.main",
        "source.azure-arm.main"
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
        except = ["azure-arm.main"]
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
            "chmod +x /tmp/scripts/install/install_kubernetes.sh",
            "chmod +x /tmp/scripts/move.sh",
            "sudo bash /tmp/scripts/init.sh -b ${var.buildctl_version} -c ${var.consul_version} ${var.gitlab_version != "" ? "-g ${var.gitlab_version} -a" : ""}",
            "sudo bash /tmp/scripts/install/install_docker.sh -v ${var.docker_version}",
            "sudo bash /tmp/scripts/install/install_redis.sh -v ${var.redis_version}",
            "sudo bash /tmp/scripts/install/install_kubernetes.sh -v ${var.kubernetes_version} -h ${var.helm_version} -s ${var.skaffold_version}",
            "sudo bash /tmp/scripts/move.sh"
        ]
    }

    ## https://www.packer.io/docs/builders/azure/arm#deprovision
    provisioner "shell" {
        #skip_clean = true ### https://www.packer.io/docs/builders/azure/arm#skip_clean
        only = ["azure-arm.main"]
        execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
        inline = [ "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync" ]
        inline_shebang = "/bin/sh -x"
    }
}

## TODO: Conditionally add appropriate plugin for provider
packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.0.4"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}
