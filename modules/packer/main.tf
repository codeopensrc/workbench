
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
variable "role" {}

variable "packer_config" {}
variable "build" {}

### TODO: Multiple images built if none are found and launching multiple machines that would all use that image
# Example: Leader machine, DB machine, Build machine want to use img-14234, but isn't found
# This will cause the module.packer.build to build their own img-14234 for each instance
# Need to create a more core data.image to query and only build ONE of that type of image
#  while still allowing multiple types (admin w/gitlab, smaller w/o gitlab) of images to build in parallel

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

            export BUILDER_SOURCE=${var.active_env_provider == "aws" ? "amazon-ebs.*" : "digitalocean.*" }
            export CUR_DIR=$(realpath ${path.module})

            packer validate -only "$BUILDER_SOURCE" \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'docker_compose_version=${var.packer_config.docker_compose_version}' \
                --var 'gitlab_version=${var.role == "admin" ? var.packer_config.gitlab_version : ""}' \
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
                $CUR_DIR/multi.pkr.hcl


            packer build -timestamp-ui -only "$BUILDER_SOURCE" \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'docker_compose_version=${var.packer_config.docker_compose_version}' \
                --var 'gitlab_version=${var.role == "admin" ? var.packer_config.gitlab_version : ""}' \
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
                $CUR_DIR/multi.pkr.hcl
        EOF
    }
}
