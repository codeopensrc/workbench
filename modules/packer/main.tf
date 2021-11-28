variable "packer_image_name" { default = "" }
variable "packer_image_size" { default = "" }

variable "aws_access_key" { default = "" }
variable "aws_secret_key" { default = "" }
variable "aws_region" { default = "" }
variable "aws_key_name" { default = "" }

variable "do_token" { default = "" }
variable "digitalocean_region" { default = "" }

variable "active_env_provider" {}
variable "type" {}

variable "packer_config" {}


resource "null_resource" "build" {

    provisioner "local-exec" {

        command = <<-EOF

            export BUILDER_SOURCE=${var.active_env_provider == "aws" ? "amazon-ebs.*" : "digitalocean.*" }
            export CUR_DIR=$(realpath ${path.module})

            packer validate -only "$BUILDER_SOURCE" \
                --var 'packer_image_name=${var.packer_image_name}' \
                --var 'packer_image_size=${var.packer_image_size}' \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'docker_compose_version=${var.packer_config.docker_compose_version}' \
                --var 'gitlab_version=${var.type == "large" ? var.packer_config.gitlab_version : ""}' \
                --var 'redis_version=${var.packer_config.redis_version}' \
                --var 'aws_key_name=${var.aws_key_name}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_config.base_amis[var.aws_region]}' \
                --var 'do_token=${var.do_token}' \
                --var 'digitalocean_image_os=${var.packer_config.digitalocean_image_os["main"]}' \
                --var 'digitalocean_region=${var.digitalocean_region}' \
                --var packer_dir=$CUR_DIR \
                $CUR_DIR/multi.pkr.hcl


            packer build -timestamp-ui -only "$BUILDER_SOURCE" \
                --var 'packer_image_name=${var.packer_image_name}' \
                --var 'packer_image_size=${var.packer_image_size}' \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'docker_compose_version=${var.packer_config.docker_compose_version}' \
                --var 'gitlab_version=${var.type == "large" ? var.packer_config.gitlab_version : ""}' \
                --var 'redis_version=${var.packer_config.redis_version}' \
                --var 'aws_key_name=${var.aws_key_name}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_config.base_amis[var.aws_region]}' \
                --var 'do_token=${var.do_token}' \
                --var 'digitalocean_image_os=${var.packer_config.digitalocean_image_os["main"]}' \
                --var 'digitalocean_region=${var.digitalocean_region}' \
                --var packer_dir=$CUR_DIR \
                $CUR_DIR/multi.pkr.hcl
        EOF
    }
}
output "out" {
    depends_on = [ null_resource.build ]
    value = null_resource.build.id
}
