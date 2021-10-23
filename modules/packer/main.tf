
variable "aws_access_key" { default = "" }
variable "aws_secret_key" { default = "" }
variable "aws_region" { default = "" }
variable "aws_key_name" { default = "" }
variable "aws_instance_type" { default = "" }

variable "do_token" { default = "" }
variable "digitalocean_region" { default = "" }
variable "digitalocean_image_size" { default = "" }
variable "digitalocean_image_name" { default = "" }

variable "active_env_provider" {}

variable "packer_config" {}
variable "build" {}



resource "null_resource" "build" {
    count = var.build ? 1 : 0

    triggers = {
        consul_version = var.packer_config.consul_version
        docker_version = var.packer_config.docker_version
        docker_compose_version = var.packer_config.docker_compose_version
        gitlab_version = var.packer_config.gitlab_version
        redis_version = var.packer_config.redis_version
        aws_key_name = var.aws_key_name
    }

    # TODO: Will need builder specific variables

    provisioner "local-exec" {

        command = <<-EOF

            export PACKER_FILE=${var.active_env_provider == "aws" ? "aws.json" : "digitalocean.pkr.hcl" }
            export CUR_DIR=$(realpath ${path.module})

            packer validate \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'docker_compose_version=${var.packer_config.docker_compose_version}' \
                --var 'gitlab_version=${var.packer_config.gitlab_version}' \
                --var 'redis_version=${var.packer_config.redis_version}' \
                --var 'aws_key_name=${var.aws_key_name}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_config.base_amis[var.aws_region]}' \
                --var 'aws_instance_type=${var.aws_instance_type}' \
                --var 'do_token=${var.do_token}' \
                --var 'digitalocean_image_os=${var.packer_config.digitalocean_image_os["main"]}' \
                --var 'digitalocean_region=${var.digitalocean_region}' \
                --var 'digitalocean_image_size=${var.digitalocean_image_size}' \
                --var 'digitalocean_image_name=${var.digitalocean_image_name}' \
                --var packer_dir=$CUR_DIR \
                $CUR_DIR/$PACKER_FILE


            packer build -timestamp-ui \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'docker_compose_version=${var.packer_config.docker_compose_version}' \
                --var 'gitlab_version=${var.packer_config.gitlab_version}' \
                --var 'redis_version=${var.packer_config.redis_version}' \
                --var 'aws_key_name=${var.aws_key_name}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_config.base_amis[var.aws_region]}' \
                --var 'aws_instance_type=${var.aws_instance_type}' \
                --var 'do_token=${var.do_token}' \
                --var 'digitalocean_image_os=${var.packer_config.digitalocean_image_os["main"]}' \
                --var 'digitalocean_region=${var.digitalocean_region}' \
                --var 'digitalocean_image_size=${var.digitalocean_image_size}' \
                --var 'digitalocean_image_name=${var.digitalocean_image_name}' \
                --var packer_dir=$CUR_DIR \
                $CUR_DIR/$PACKER_FILE
        EOF
    }
}
