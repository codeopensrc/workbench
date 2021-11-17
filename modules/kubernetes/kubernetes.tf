variable "ansible_hostfile" {}

##TODO: Remove these 2
variable "admin_servers" {}
variable "server_count" {}

variable "all_public_ips" {}
variable "all_names" {}

variable "gitlab_runner_tokens" {}
variable "root_domain_name" {}
variable "import_gitlab" {}
variable "vpc_private_iface" {}

variable "kubernetes_version" {}
variable "container_orchestrators" {}


resource "null_resource" "kubernetes_rm_nodes" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0

    triggers = {
        names = join(",", var.all_names)
        hostfile = var.ansible_hostfile
    }

    ## Copy old ansible file to preserve hosts before their destruction
    ### TODO: For operations that need to be run on destruction, need a more cohesive
    ###   and standardized way to handle old ansible hosts vs new ones
    ### Cant have multiple resources creating/duplicating files and removing them per resource/playbook
    provisioner "local-exec" {
        when = destroy
        command = "cp ${self.triggers.hostfile} ${self.triggers.hostfile}-before"
    }
    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ -f "${self.triggers.hostfile}-before" ]; then
                ansible-playbook ${path.module}/playbooks/kubernetes_rm.yml -i ${self.triggers.hostfile}-before \
                    --extra-vars 'all_names=${self.triggers.names}';
                rm ${self.triggers.hostfile}-before;
            fi
        EOF
    }
}

resource "null_resource" "kubernetes" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
    depends_on = [null_resource.kubernetes_rm_nodes]

    triggers = {
        names = join(",", var.all_names)
    }

    ##  digitaloceans private iface = eth1
    ##  aws private iface = ens5
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/kubernetes.yml -i ${var.ansible_hostfile} --extra-vars \
                'kubernetes_version=${var.kubernetes_version}
                gitlab_runner_tokens=${jsonencode(var.gitlab_runner_tokens)}
                vpc_private_iface=${var.vpc_private_iface}
                root_domain_name=${var.root_domain_name}
                admin_servers=${var.admin_servers}
                server_count=${var.server_count}
                import_gitlab=${var.import_gitlab}'
        EOF
    }
}

