variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}
variable "remote_state_hosts" {}

variable "admin_servers" {}
variable "server_count" {}

variable "gitlab_runner_tokens" {}
variable "root_domain_name" {}
variable "import_gitlab" {}
variable "vpc_private_iface" {}
variable "active_env_provider" {}

variable "kubernetes_version" {}
variable "buildkitd_version" {}
variable "container_orchestrators" {}
variable "cleanup_kube_volumes" {}

variable "cloud_provider" {}
variable "cloud_provider_token" {}
variable "csi_namespace" {}
variable "csi_version" {}

variable "additional_ssl" {}

locals {
    all_names = flatten([for role, hosts in var.ansible_hosts: hosts[*].name])
    old_all_names = flatten([for role, hosts in var.remote_state_hosts: hosts[*].name])
    admin_private_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.private_ip
            if contains(HOST.roles, "admin")
        ]
    ])
    lead_private_ips = flatten([
        for role, hosts in var.ansible_hosts: [
            for HOST in hosts: HOST.private_ip
            if contains(HOST.roles, "lead")
        ]
    ])
    kube_services = [
        for app in var.additional_ssl:
        { subdomain = format("%s.%s", app.subdomain_name, var.root_domain_name), name = app.service_name }
        if app.create_ssl_cert == true
    ]
}

### TODO: Adding/configuring additional users
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#kubeconfig-additional-users
resource "null_resource" "kubernetes" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
    triggers = {
        num_nodes = var.server_count
        kubecfg_cluster = "${var.root_domain_name}"
        kubecfg_context = "${var.root_domain_name}-admin@kubernetes"
        kubecfg_user = "${var.root_domain_name}-admin"
    }

    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
    provisioner "local-exec" {
        command = <<-EOF
            if [ ${length(local.all_names)} -lt ${length(local.old_all_names)} ]; then
                if [ -f "${var.predestroy_hostfile}" ]; then
                    ansible-playbook ${path.module}/playbooks/kubernetes_rm.yml -i ${var.predestroy_hostfile} --extra-vars \
                        'all_names=${jsonencode(local.all_names)}
                        admin_private_ips=${jsonencode(local.admin_private_ips)}
                        lead_private_ips=${jsonencode(local.lead_private_ips)}';
                fi
            fi
        EOF
    }
    ##  digitaloceans private iface = eth1
    ##  aws private iface = ens5
    ##  azure private iface = eth0
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/kubernetes.yml -i ${var.ansible_hostfile} --extra-vars \
                'kubernetes_version=${var.kubernetes_version}
                buildkitd_version=${var.buildkitd_version}
                gitlab_runner_tokens=${jsonencode(var.gitlab_runner_tokens)}
                vpc_private_iface=${var.vpc_private_iface}
                root_domain_name=${var.root_domain_name}
                admin_servers=${var.admin_servers}
                server_count=${var.server_count}
                active_env_provider=${var.active_env_provider}
                import_gitlab=${var.import_gitlab}
                cloud_provider=${var.cloud_provider}
                cloud_provider_token=${var.cloud_provider_token}
                csi_namespace=${var.csi_namespace}
                csi_version=${var.csi_version}'
        EOF
    }

    ### Add cluster + context + user locally to kubeconfig
    provisioner "local-exec" {
        command = <<-EOF
            sed -i "s/kube-cluster-endpoint/gitlab.${var.root_domain_name}/" $HOME/.kube/${var.root_domain_name}-kubeconfig
            KUBECONFIG=$HOME/.kube/config:$HOME/.kube/${var.root_domain_name}-kubeconfig
            kubectl config view --flatten > /tmp/kubeconfig
            cp --backup=numbered $HOME/.kube/config $HOME/.kube/config.bak
            mv /tmp/kubeconfig $HOME/.kube/config
            rm $HOME/.kube/${var.root_domain_name}-kubeconfig
        EOF
    }

    ### Remove cluster + context + user locally from kubeconfig
    ## Only runs on terraform destroy
    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            kubectl config delete-cluster ${self.triggers.kubecfg_cluster}
            kubectl config delete-context ${self.triggers.kubecfg_context}
            kubectl config delete-user ${self.triggers.kubecfg_user}
        EOF
    }
}

resource "null_resource" "managed_kubernetes" {
    count = contains(var.container_orchestrators, "managed_kubernetes") ? 1 : 0
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/managed_kubernetes.yml -i ${var.ansible_hostfile} --extra-vars \
                'root_domain_name=${var.root_domain_name}
                kube_services=${jsonencode(local.kube_services)}'
        EOF
    }
}


## Goal is to only cleanup kubernetes volumes on 'terraform destroy'
## TODO: Forgot to test with attached volumes/volumes attached to pods..
resource "null_resource" "cleanup_cluster_volumes" {
    count = contains(var.container_orchestrators, "kubernetes") && var.cleanup_kube_volumes ? 1 : 0
    ## Untested/Unsure how to handle with managed kubernetes atm
    #count = contains(var.container_orchestrators, "managed_kubernetes") ? 1 : 0

    depends_on = [
        null_resource.kubernetes,
        null_resource.managed_kubernetes,
    ]

    triggers = {
        predestroy_hostfile = var.predestroy_hostfile
    }

    provisioner "local-exec" {
        when = destroy
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/cleanup_kube_volumes.yml -i ${self.triggers.predestroy_hostfile}
        EOF
    }
}
