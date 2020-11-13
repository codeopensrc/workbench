
variable "aws_access_key" { default = "" }
variable "aws_secret_key" { default = "" }
variable "aws_region" { default = "" }
variable "aws_key_name" { default = "" }

variable "active_env_provider" {}

variable "packer_config" {}

# TODO: Query our amis based on software versions
# If no mactching AMIs with all our tags, create a new image
# Otherwise just use that image

data "aws_ami_ids" "latest" {
    owners = ["self"]

    filter {
        name   = "tag:Type"
        values = [ "build" ]
    }
    filter {
        name   = "tag:consul_version"
        values = [ var.packer_config.consul_version ]
    }
    filter {
        name   = "tag:docker_version"
        values = [ var.packer_config.docker_version ]
    }
    filter {
        name   = "tag:docker_compose_version"
        values = [ var.packer_config.docker_compose_version ]
    }
    filter {
        name   = "tag:gitlab_version"
        values = [ var.packer_config.gitlab_version ]
    }
    filter {
        name   = "tag:redis_version"
        values = [ var.packer_config.redis_version ]
    }
    filter {
        name   = "tag:aws_key_name"
        values = [ var.aws_key_name ]
    }
}


resource "null_resource" "build" {
    ## If we can find ami, dont build, count is 0. If we cant find ami, then build one so count is 1
    count = length(data.aws_ami_ids.latest.ids) >= 1 ? 0 : 1


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
                $CUR_DIR/packer.json


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
    filter {
        name   = "tag:consul_version"
        values = [ var.packer_config.consul_version ]
    }
    filter {
        name   = "tag:docker_version"
        values = [ var.packer_config.docker_version ]
    }
    filter {
        name   = "tag:docker_compose_version"
        values = [ var.packer_config.docker_compose_version ]
    }
    filter {
        name   = "tag:gitlab_version"
        values = [ var.packer_config.gitlab_version ]
    }
    filter {
        name   = "tag:redis_version"
        values = [ var.packer_config.redis_version ]
    }
    filter {
        name   = "tag:aws_key_name"
        values = [ var.aws_key_name ]
    }
}

output "image_id" {
    value = var.active_env_provider == "aws" ? data.aws_ami.latest.id : ""
}
