variable "ansible_hosts" {}
variable "ansible_hostfile" {}
variable "predestroy_hostfile" {}
variable "remote_state_hosts" {}

variable "admin_servers" {}
variable "server_count" {}

variable "gitlab_runner_tokens" {}
variable "root_domain_name" {}
variable "contact_email" {}
variable "import_gitlab" {}
variable "vpc_private_iface" {}
variable "active_env_provider" {}

variable "kubernetes_version" {}
variable "buildkitd_version" {}
variable "container_orchestrators" {}
variable "cleanup_kube_volumes" {}

variable "cloud_provider" {}
variable "cloud_provider_token" {}
variable "cloud_controller_version" {}
variable "csi_namespace" {}
variable "csi_version" {}

variable "additional_ssl" {}

variable "local_kubeconfig_path" {}
variable "kube_apps" {}
variable "kube_services" {}
variable "kubernetes_nginx_nodeports" {}
#variable "lb_name" {}
#variable "lb_id" {}

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
    kube_app_services = [
        for app in var.additional_ssl:
        { subdomain = format("%s.%s", app.subdomain_name, var.root_domain_name), name = app.service_name }
        if app.create_ssl_cert == true
    ]
    app_helm_value_files_dir = "${path.module}/playbooks/ansiblefiles/helm_values"
    app_helm_value_files = fileset("${local.app_helm_value_files_dir}/", "*[^.swp]")
    app_helm_value_files_sha = sha1(join("", [for f in local.app_helm_value_files: filesha1("${local.app_helm_value_files_dir}/${f}")]))

    kube_formatted_udp_ports = join("\n  ", [
        for port, dest in lookup(var.kubernetes_nginx_nodeports, "udp", {}):
        "${port}: ${dest}"
    ])
    kube_formatted_tcp_ports = join("\n  ", [
        for port, dest in lookup(var.kubernetes_nginx_nodeports, "tcp", {}):
        "${port}: ${dest}"
    ])
    tf_helm_values = {
        prometheus = <<-EOF
        server:
          ingress:
            hosts:
            - prom.k8s-internal.${var.root_domain_name}
        EOF
        ###TODO: _maybe_ tell nginx to use our lb based on id when more 1+ workers
        ###   or make an api call to change DNS to our new nginx loadbalancer ip without pre-provisioning it
        ### atm digital ocean removes/wont assign droplets to lb if its a control-plane
        #service:
        #  type: LoadBalancer
        #  annotations: 
        #    kubernetes.digitalocean.com/load-balancer-id: "${var.lb_id}"
        nginx = <<-EOF
        tcp:
          ${local.kube_formatted_tcp_ports}
        udp:
          ${local.kube_formatted_udp_ports}
        controller:
          service:
            nodePorts:
              http: ${var.kubernetes_nginx_nodeports.http}
              https: ${var.kubernetes_nginx_nodeports.https}
        EOF
    }
}

### TODO: Adding/configuring additional users
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#kubeconfig-additional-users
resource "null_resource" "kubernetes" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
    triggers = {
        num_nodes = var.server_count
        kubecfg_cluster = "${var.root_domain_name}"
        kubecfg_context = "${var.root_domain_name}"
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
            ansible-playbook ${path.module}/playbooks/kubernetes.yml -i ${var.ansible_hostfile} \
                --extra-vars \
                'kubernetes_version=${var.kubernetes_version}
                buildkitd_version=${var.buildkitd_version}
                gitlab_runner_tokens=${jsonencode(var.gitlab_runner_tokens)}
                vpc_private_iface=${var.vpc_private_iface}
                root_domain_name=${var.root_domain_name}
                contact_email=${var.contact_email}
                admin_servers=${var.admin_servers}
                server_count=${var.server_count}
                active_env_provider=${var.active_env_provider}
                import_gitlab=${var.import_gitlab}
                cloud_provider=${var.cloud_provider}
                cloud_provider_token=${var.cloud_provider_token}
                cloud_controller_version=${var.cloud_controller_version}
                csi_namespace=${var.csi_namespace}
                csi_version=${var.csi_version}'
        EOF
    }

    ### Add cluster + context + user locally to kubeconfig
    provisioner "local-exec" {
        command = <<-EOF
            if [ -f $HOME/.kube/${var.root_domain_name}-kubeconfig ]; then
                sed -i "s/kube-cluster-endpoint/gitlab.${var.root_domain_name}/" $HOME/.kube/${var.root_domain_name}-kubeconfig
                KUBECONFIG=${var.local_kubeconfig_path}:$HOME/.kube/${var.root_domain_name}-kubeconfig
                kubectl config view --flatten > /tmp/kubeconfig
                cp --backup=numbered ${var.local_kubeconfig_path} ${var.local_kubeconfig_path}.bak
                mv /tmp/kubeconfig ${var.local_kubeconfig_path}
                rm $HOME/.kube/${var.root_domain_name}-kubeconfig
            else
                echo "Could not find $HOME/.kube/${var.root_domain_name}-kubeconfig"
            fi
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

resource "null_resource" "apps" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
    depends_on = [
        null_resource.kubernetes,
        null_resource.managed_kubernetes,
    ]
    triggers = {
        num_nodes = var.server_count
        num_apps = length(keys(var.kube_apps))
        enabled_apps = join(",", [for a in var.kube_apps: "${a.release_name}:${a.enabled}"])
        values_sha = local.app_helm_value_files_sha
    }
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/apps.yml -i ${var.ansible_hostfile} --extra-vars \
                'root_domain_name=${var.root_domain_name}
                kube_apps=${jsonencode(var.kube_apps)}'
        EOF
    }
}

## TODO: Probably separate and create helm module
resource "helm_release" "services" {
    for_each = {
        for servicename, service in var.kube_services:
        servicename => service
        if service.enabled && (contains(var.container_orchestrators, "kubernetes") ? 1 : 0) == 1
    }
    depends_on = [
        null_resource.kubernetes,
        null_resource.managed_kubernetes,
    ]
    name             = each.key
    chart            = each.value.chart
    namespace        = each.value.namespace != "" ? each.value.namespace : "default"
    create_namespace = each.value.create_namespace
    repository       = each.value.chart_url
    version          = each.value.chart_version
    values           = concat(
        [for f in each.value.opt_value_files: file("${path.module}/helm_values/${f}")],
        [for key, values in local.tf_helm_values: values if key == each.key]
    )
}

resource "null_resource" "managed_kubernetes" {
    count = contains(var.container_orchestrators, "managed_kubernetes") ? 1 : 0
    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/managed_kubernetes.yml -i ${var.ansible_hostfile} --extra-vars \
                'root_domain_name=${var.root_domain_name}
                kube_app_services=${jsonencode(local.kube_app_services)}'
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
        null_resource.apps,
        helm_release.services,
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
