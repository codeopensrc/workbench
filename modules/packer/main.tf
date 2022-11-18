variable "packer_image_name" { default = "" }
variable "packer_image_size" { default = "" }

variable "aws_access_key" { default = "" }
variable "aws_secret_key" { default = "" }
variable "aws_region" { default = "" }
variable "aws_key_name" { default = "" }

variable "do_token" { default = "" }
variable "digitalocean_region" { default = "" }

variable "az_subscriptionId" { default = "" }
variable "az_tenant" { default = "" }
variable "az_appId" { default = "" }
variable "az_password" { default = "" }
variable "az_region" { default = "" }
variable "az_resource_group" { default = "" }


variable "active_env_provider" {}
variable "type" {}

variable "packer_config" {}


resource "null_resource" "build" {

    provisioner "local-exec" {

        command = <<-EOF
            if [ "${var.active_env_provider}" = "aws" ]; then BUILDER_SOURCE="amazon-ebs.*"; fi
            if [ "${var.active_env_provider}" = "digital_ocean" ]; then BUILDER_SOURCE="digitalocean.*"; fi
            if [ "${var.active_env_provider}" = "azure" ]; then BUILDER_SOURCE="azure-arm.*"; fi
            export BUILDER_SOURCE
            export CUR_DIR=$(realpath ${path.module})

            packer validate -only "$BUILDER_SOURCE" \
                --var 'packer_image_name=${var.packer_image_name}' \
                --var 'packer_image_size=${var.packer_image_size}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'buildctl_version=${var.packer_config.buildctl_version}' \
                --var 'gitlab_version=${var.type == "large" ? var.packer_config.gitlab_version : ""}' \
                --var 'redis_version=${var.packer_config.redis_version}' \
                --var 'kubernetes_version=${var.packer_config.kubernetes_version}' \
                --var 'helm_version=${var.packer_config.helm_version}' \
                --var 'skaffold_version=${var.packer_config.skaffold_version}' \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'aws_key_name=${var.aws_key_name}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_config.base_amis[var.aws_region]}' \
                --var 'do_token=${var.do_token}' \
                --var 'digitalocean_image_os=${var.packer_config.digitalocean_image_os[var.digitalocean_region]}' \
                --var 'digitalocean_region=${var.digitalocean_region}' \
                --var 'az_subscriptionId=${var.az_subscriptionId}' \
                --var 'az_tenant=${var.az_tenant}' \
                --var 'az_appId=${var.az_appId}' \
                --var 'az_password=${var.az_password}' \
                --var 'az_region=${var.az_region}' \
                --var 'az_resource_group=${var.az_resource_group}' \
                --var 'az_image_publisher=${var.packer_config.azure_image_os[var.az_region].publisher}' \
                --var 'az_image_offer=${var.packer_config.azure_image_os[var.az_region].offer}' \
                --var 'az_image_sku=${var.packer_config.azure_image_os[var.az_region].sku}' \
                --var 'az_image_version=${var.packer_config.azure_image_os[var.az_region].version}' \
                --var packer_dir=$CUR_DIR \
                $CUR_DIR/multi.pkr.hcl


            packer build -timestamp-ui -only "$BUILDER_SOURCE" \
                --var 'packer_image_name=${var.packer_image_name}' \
                --var 'packer_image_size=${var.packer_image_size}' \
                --var 'consul_version=${var.packer_config.consul_version}' \
                --var 'docker_version=${var.packer_config.docker_version}' \
                --var 'buildctl_version=${var.packer_config.buildctl_version}' \
                --var 'gitlab_version=${var.type == "large" ? var.packer_config.gitlab_version : ""}' \
                --var 'redis_version=${var.packer_config.redis_version}' \
                --var 'kubernetes_version=${var.packer_config.kubernetes_version}' \
                --var 'helm_version=${var.packer_config.helm_version}' \
                --var 'skaffold_version=${var.packer_config.skaffold_version}' \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'aws_key_name=${var.aws_key_name}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_config.base_amis[var.aws_region]}' \
                --var 'do_token=${var.do_token}' \
                --var 'digitalocean_image_os=${var.packer_config.digitalocean_image_os[var.digitalocean_region]}' \
                --var 'digitalocean_region=${var.digitalocean_region}' \
                --var 'az_subscriptionId=${var.az_subscriptionId}' \
                --var 'az_tenant=${var.az_tenant}' \
                --var 'az_appId=${var.az_appId}' \
                --var 'az_password=${var.az_password}' \
                --var 'az_region=${var.az_region}' \
                --var 'az_resource_group=${var.az_resource_group}' \
                --var 'az_image_publisher=${var.packer_config.azure_image_os[var.az_region].publisher}' \
                --var 'az_image_offer=${var.packer_config.azure_image_os[var.az_region].offer}' \
                --var 'az_image_sku=${var.packer_config.azure_image_os[var.az_region].sku}' \
                --var 'az_image_version=${var.packer_config.azure_image_os[var.az_region].version}' \
                --var packer_dir=$CUR_DIR \
                $CUR_DIR/multi.pkr.hcl
        EOF
    }
}
output "out" {
    depends_on = [ null_resource.build ]
    value = null_resource.build.id
}
