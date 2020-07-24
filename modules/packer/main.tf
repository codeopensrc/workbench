
variable "aws_access_key" { default = "" }
variable "aws_secret_key" { default = "" }
variable "aws_region" { default = "" }

variable "active_env_provider" {}

variable "consul_version" {}
variable "docker_compose_version" {}
variable "gitlab_version" {}
variable "redis_version" {}

variable "build_packer_image" { default = "" }
variable "packer_default_amis" { default = {} }

# TODO: Query our amis based on software versions
# If no mactching AMIs with all our tags, create a new image
# Otherwise just use that image

resource "null_resource" "build" {
    count = var.build_packer_image ? 1 : 0

    triggers = {
        consul_version = var.consul_version
        docker_compose_version = var.docker_compose_version
        gitlab_version = var.gitlab_version
        redis_version = var.redis_version
    }

    # TODO: Will need builder specific variables

    provisioner "local-exec" {

        command = <<-EOF

            export CUR_DIR=$(realpath ${path.module})

            packer validate \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.consul_version}' \
                --var 'docker_compose_version=${var.docker_compose_version}' \
                --var 'gitlab_version=${var.gitlab_version}' \
                --var 'redis_version=${var.redis_version}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_default_amis[var.aws_region]}' \
                $CUR_DIR/packer.json


            packer build -timestamp-ui \
                --var 'aws_access_key=${var.aws_access_key}' \
                --var 'aws_secret_key=${var.aws_secret_key}' \
                --var 'consul_version=${var.consul_version}' \
                --var 'docker_compose_version=${var.docker_compose_version}' \
                --var 'gitlab_version=${var.gitlab_version}' \
                --var 'redis_version=${var.redis_version}' \
                --var 'aws_region=${var.aws_region}' \
                --var 'ami_source=${var.packer_default_amis[var.aws_region]}' \
                $CUR_DIR/packer.json
        EOF
    }

}


#TODO: packer_image should always resolve to the correct type/id of image for the selected provider. Whether
#  its ami for aws, snapshot for digital ocean, azure/GCP buidler image output etc.

#TODO: Only if aws is provider
data "aws_ami" "latest" {
    depends_on = [ null_resource.build ]
    most_recent = true

    owners = ["self"]

    filter {
        name   = "tag:Type"
        values = [ "build" ]
    }
}

# TODO: Output newly built or most recent, based on `use_packer_image`
output "image_id" {
    value = var.active_env_provider == "aws" ? data.aws_ami.latest.id : ""
}
