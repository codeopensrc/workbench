terraform {
    required_providers {
        kubectl = {
            source = "gavinbunney/kubectl"
        }
        kubernetes = {
            source = "kubernetes"
        }
    }
}

variable "local_kubeconfig_path" {}
variable "gitlab_runner_tokens" {}
variable "root_domain_name" {}
variable "contact_email" {}
variable "import_gitlab" {}
variable "vpc_private_iface" {}
variable "active_env_provider" {}

variable "kubernetes_version" {}
variable "buildkitd_version" {}
variable "cleanup_kube_volumes" {}

variable "cloud_provider" {}
variable "cloud_provider_token" {}
variable "csi_namespace" {}
variable "csi_version" {}

variable "kube_apps" {}
variable "kube_services" {}
variable "kubernetes_nginx_nodeports" {}

variable "oauth" {}
variable "subdomains" {}

variable "source_env_bucket_prefix" {}
variable "target_env_bucket_prefix" {}
variable "env_bucket_prefix" {}
variable "s3_access_key_id" {}
variable "s3_secret_access_key" {}
variable "s3_endpoint" {}
variable "s3_region" {}
variable "s3_backup_bucket" {}
variable "mattermost_backups_enabled" {}

locals {
    consul_srvdiscovery_enabled = false
    mattermost_version_matrix = {
        "1.0.4" = "10.12.0"
    }
    mattermost_enabled = var.kube_services["mattermost"].enabled
    allow_backups = terraform.workspace == "default"
    mattermost_backups_enabled = var.mattermost_backups_enabled && local.allow_backups
    postgres_tls = {
        name = "postgresql-tls"
        key = "tls.key"
        cert = "tls.crt"
    }
    mattermost_db_auth = {
        username = "mattermost"
        database = "mattermost"
        password = local.mattermost_enabled || var.kube_services["postgresql"].enabled ? random_password.mattermost_db["user"].result : ""
        postgresPassword = local.mattermost_enabled || var.kube_services["postgresql"].enabled ? random_password.mattermost_db["postgres"].result : ""
    }
    mattermost_version = (local.mattermost_enabled
        ? local.mattermost_version_matrix[var.kube_services["mattermost"].chart_version]
        : "")
    wekan_oauth = {
        enabled = lookup(var.oauth, "wekan", null) != null ? true : false
        client_id = lookup(var.oauth, "wekan", null) != null ? "OAUTH2_CLIENT_ID: ${var.oauth.wekan.application_id}" : ""
        secret = lookup(var.oauth, "wekan", null) != null ? "OAUTH2_SECRET: ${var.oauth.wekan.secret}" : ""
    }
    mattermost_oauth = {
        enabled = lookup(var.oauth, "mattermost", null) != null ? true : false
        client_id = lookup(var.oauth, "mattermost", null) != null ? var.oauth.mattermost.application_id : ""
        secret = lookup(var.oauth, "mattermost", null) != null ? var.oauth.mattermost.secret : ""
    }
    mattermost_integration_oauth = {
        enabled = lookup(var.oauth, "mattermost_integration", null) != null ? true : false
        client_id = lookup(var.oauth, "mattermost_integration", null) != null ? var.oauth.mattermost_integration.application_id : ""
        secret = lookup(var.oauth, "mattermost_integration", null) != null ? var.oauth.mattermost_integration.secret : ""
    }

    gitlab_filestore_secret = "gitlab-minio-secret"
    external_storage_enabled = (var.import_gitlab && var.env_bucket_prefix != ""
        && var.s3_access_key_id != "" && var.s3_secret_access_key != "" && var.s3_endpoint != "")

    mattermost_filestore = {
        secretname = "mattermost-filestore"
        url = local.external_storage_enabled ? replace(var.s3_endpoint, "https://", "") : "minio.${var.root_domain_name}"
        bucket = local.external_storage_enabled ? "${var.env_bucket_prefix}-mattermost" : "mattermost"
        accesskey = local.mattermost_enabled ? (local.external_storage_enabled ? base64encode(var.s3_access_key_id) : base64encode(data.kubernetes_secret_v1.gitlab_filestore[0].data.accesskey)) : ""
        secretkey = local.mattermost_enabled ? (local.external_storage_enabled ? base64encode(var.s3_secret_access_key) : base64encode(data.kubernetes_secret_v1.gitlab_filestore[0].data.secretkey)) : ""
    }

    mm_namespace = "mattermost"
    mm_env_vars = {
        MM_GITLABSETTINGS_ENABLE = true
        MM_GITLABSETTINGS_ID = local.mattermost_oauth.client_id
        MM_GITLABSETTINGS_SECRET = local.mattermost_oauth.secret
        MM_GITLABSETTINGS_USERAPIENDPOINT = "https://gitlab.${var.root_domain_name}/api/v4/user"
        MM_GITLABSETTINGS_AUTHENDPOINT = "https://gitlab.${var.root_domain_name}/oauth/authorize"
        MM_GITLABSETTINGS_TOKENENDPOINT = "https://gitlab.${var.root_domain_name}/oauth/token"
        MM_EMAILSETTINGS_ENABLESIGNUPWITHEMAIL = false
        MM_EMAILSETTINGS_ENABLESIGNINWITHEMAIL = false
    }
    ## https://docs.mattermost.com/administration-guide/configure/plugins-configuration-settings.html#installed-plugin-state
    mm_plugin_vars = {
        MM_PLUGINSETTINGS_PLUGINSTATES = jsonencode({"com.github.manland.mattermost-plugin-gitlab": {"Enable": true}})
        MM_PLUGINSETTINGS_PLUGINS = jsonencode({"com.github.manland.mattermost-plugin-gitlab": {
            "enablechildpipelinenotifications": true,
            "enablecodepreview": "public",
            "enableprivaterepo": true,
            "gitlaboauthclientid": local.mattermost_integration_oauth.client_id,
            "gitlaboauthclientsecret": local.mattermost_integration_oauth.secret,
            "gitlaburl": "https://gitlab.${var.root_domain_name}",
        }})
    }
    mattermost_file = {
        namespace = local.mm_namespace
        name = "mattermost"
        users = "100users" # Example: 5000users
        host = "${lookup(var.subdomains, "mattermost", "mattermost")}.${var.root_domain_name}"
        version = local.mattermost_version
        mm_env_vars = local.mm_env_vars
        mm_plugin_vars = local.mm_plugin_vars
        ingressclass = "nginx"
        filestore = local.mattermost_filestore
        db = {
            secretname = "mattermost-postgres"
            conn_string = base64encode("postgres://${local.mattermost_db_auth.username}:${local.mattermost_db_auth.password}@postgresql:5432/${local.mattermost_db_auth.database}")
        }
    }

    mattermost_filelist = ["install", "filestore", "database"]
    mattermost_files = {
        for ind, keyName in local.mattermost_filelist:
        keyName => 
            trimspace(split("---", templatefile("${path.module}/manifests/mattermost.yaml", local.mattermost_file))[ind])
        if local.mattermost_enabled
    }


    ## TODO: Have helm values come from apps.tf file ideally
    ## Tricky cause they wont be in vcs but meh
    tf_helm_values = {
        postgresql = <<-EOF
        image:
          repository: bitnamilegacy/postgresql
        volumePermissions:
          image:
            repository: bitnamilegacy/os-shell
        passwordUpdateJob:
          enabled: true
          #previousPasswords:
          #  existingSecret: postgresql
        auth:
          username: ${local.mattermost_db_auth.username}
          database: ${local.mattermost_db_auth.database}
          password: ${local.mattermost_db_auth.password}
          postgresPassword: ${local.mattermost_db_auth.postgresPassword}
        tls:
          enabled: ${local.mattermost_enabled || var.kube_services["postgresql"].enabled}
          certificatesSecret: ${local.postgres_tls.name}
          certFilename: ${local.postgres_tls.cert}
          certKeyFilename: ${local.postgres_tls.key}
          preferServerCiphers: false
          autoGenerated: false
        EOF
        prometheus = <<-EOF
        server:
          ingress:
            hosts:
            - prom.k8s-internal.${var.root_domain_name}
        EOF
        react = <<-EOF
        app:
          ingress:
            enabled: true
            ingressClassName: "nginx"
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: react.k8s.${var.root_domain_name}
            tls:
              - hosts:
                  - react.k8s.${var.root_domain_name}
                secretName: react-tls
        EOF
        wekan = <<-EOF
        db:
          enabled: true
        app:
          svcDiscovery:
            consul:
              enabled: ${local.consul_srvdiscovery_enabled}
              env:
                CONSUL_HOST: consul.${var.root_domain_name}
          ingress:
            enabled: true
            ingressClassName: "nginx"
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
            hosts:
              - host: ${lookup(var.subdomains, "wekan", "wekan")}.${var.root_domain_name}
            tls:
              - hosts:
                  - ${lookup(var.subdomains, "wekan", "wekan")}.${var.root_domain_name}
                secretName: wekan-tls
          configMapData:
            ROOT_URL: "https://${lookup(var.subdomains, "wekan", "wekan")}.${var.root_domain_name}"
            OAUTH2_SERVER_URL: "https://gitlab.${var.root_domain_name}/"
            OAUTH2_ENABLED: ${local.wekan_oauth.enabled}
          secretStringData:
            ${local.wekan_oauth.client_id}
            ${local.wekan_oauth.secret}
        EOF
    }
}

### TODO: Adding/configuring additional users
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/#kubeconfig-additional-users
#resource "null_resource" "kubernetes" {
#    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
#    triggers = {
#        num_nodes = var.server_count
#        kubecfg_cluster = "${var.root_domain_name}"
#        kubecfg_context = "${var.root_domain_name}"
#        kubecfg_user = "${var.root_domain_name}-admin"
#    }
#
#    ## Run playbook with old ansible file and new names to find out the ones to be deleted, drain and removing them
#    #provisioner "local-exec" {
#    #    command = <<-EOF
#    #        if [ ${length(local.all_names)} -lt ${length(local.old_all_names)} ]; then
#    #            if [ -f "${var.predestroy_hostfile}" ]; then
#    #                ansible-playbook ${path.module}/playbooks/kubernetes_rm.yml -i ${var.predestroy_hostfile} --extra-vars \
#    #                    'all_names=${jsonencode(local.all_names)}
#    #                    admin_private_ips=${jsonencode(local.admin_private_ips)}
#    #                    lead_private_ips=${jsonencode(local.lead_private_ips)}';
#    #            fi
#    #        fi
#    #    EOF
#    #}
#    ##  digitaloceans private iface = eth1
#    ##  aws private iface = ens5
#    ##  azure private iface = eth0
#    #provisioner "local-exec" {
#    #    command = <<-EOF
#    #        ansible-playbook ${path.module}/playbooks/kubernetes.yml -i ${var.ansible_hostfile} \
#    #            --extra-vars \
#    #            'kubernetes_version=${var.kubernetes_version}
#    #            buildkitd_version=${var.buildkitd_version}
#    #            gitlab_runner_tokens=${jsonencode(var.gitlab_runner_tokens)}
#    #            vpc_private_iface=${var.vpc_private_iface}
#    #            root_domain_name=${var.root_domain_name}
#    #            contact_email=${var.contact_email}
#    #            admin_servers=${var.admin_servers}
#    #            server_count=${var.server_count}
#    #            active_env_provider=${var.active_env_provider}
#    #            import_gitlab=${var.import_gitlab}
#    #            cloud_provider=${var.cloud_provider}
#    #            cloud_provider_token=${var.cloud_provider_token}
#    #            cloud_controller_version=${var.cloud_controller_version}
#    #            csi_namespace=${var.csi_namespace}
#    #            csi_version=${var.csi_version}'
#    #    EOF
#    #}
#
#    ### Add cluster + context + user locally to kubeconfig
#    provisioner "local-exec" {
#        command = <<-EOF
#            if [ -f $HOME/.kube/${var.root_domain_name}-kubeconfig ]; then
#                sed -i "s/kube-cluster-endpoint/gitlab.${var.root_domain_name}/" $HOME/.kube/${var.root_domain_name}-kubeconfig
#                KUBECONFIG=${var.local_kubeconfig_path}:$HOME/.kube/${var.root_domain_name}-kubeconfig
#                kubectl config view --flatten > /tmp/kubeconfig
#                cp --backup=numbered ${var.local_kubeconfig_path} ${var.local_kubeconfig_path}.bak
#                mv /tmp/kubeconfig ${var.local_kubeconfig_path}
#                rm $HOME/.kube/${var.root_domain_name}-kubeconfig
#            else
#                echo "Could not find $HOME/.kube/${var.root_domain_name}-kubeconfig"
#            fi
#        EOF
#    }
#
#    ### Remove cluster + context + user locally from kubeconfig
#    ## Only runs on terraform destroy
#    provisioner "local-exec" {
#        when = destroy
#        command = <<-EOF
#            kubectl config delete-cluster ${self.triggers.kubecfg_cluster}
#            kubectl config delete-context ${self.triggers.kubecfg_context}
#            kubectl config delete-user ${self.triggers.kubecfg_user}
#        EOF
#    }
#}

#resource "null_resource" "apps" {
#    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0
#    depends_on = [
#        #null_resource.kubernetes,
#        null_resource.managed_kubernetes,
#    ]
#    triggers = {
#        num_nodes = var.server_count
#        num_apps = length(keys(var.kube_apps))
#        enabled_apps = join(",", [for a in var.kube_apps: "${a.release_name}:${a.enabled}"])
#        values_sha = local.app_helm_value_files_sha
#    }
#    provisioner "local-exec" {
#        command = <<-EOF
#            ansible-playbook ${path.module}/playbooks/apps.yml -i ${var.ansible_hostfile} --extra-vars \
#                'root_domain_name=${var.root_domain_name}
#                kube_apps=${jsonencode(var.kube_apps)}'
#        EOF
#    }
#}

resource "random_password" "mattermost_db" {
    for_each = {
        for ind, key in ["user", "postgres"]: key => key
        if local.mattermost_enabled || var.kube_services["postgresql"].enabled
    }
    length           = 20
    special          = false
}
resource "tls_private_key" "postgres" {
    count = local.mattermost_enabled || var.kube_services["postgresql"].enabled ? 1 : 0
    algorithm = "RSA"
}
resource "tls_self_signed_cert" "postgres" {
    count = local.mattermost_enabled || var.kube_services["postgresql"].enabled ? 1 : 0
    private_key_pem = tls_private_key.postgres[0].private_key_pem
    # Certificate expires after ~40000 days.
    validity_period_hours = 999999
    allowed_uses = [
        "key_encipherment",
        "digital_signature",
        "server_auth",
    ]
}
resource "kubernetes_namespace" "mattermost" {
    count = local.mattermost_enabled || var.kube_services["postgresql"].enabled ? 1 : 0
    metadata {
        name = local.mm_namespace
    }
}
resource "kubernetes_secret_v1" "postgres_tls" {
    count = local.mattermost_enabled || var.kube_services["postgresql"].enabled ? 1 : 0
    depends_on = [
        tls_private_key.postgres,
        tls_self_signed_cert.postgres,
        kubernetes_namespace.mattermost
    ]
    metadata {
        name = local.postgres_tls.name
        namespace = local.mm_namespace
    }
    type = "kubernetes.io/tls"
    data = {
        "${local.postgres_tls.key}" = tls_private_key.postgres[0].private_key_pem
        "${local.postgres_tls.cert}" = tls_self_signed_cert.postgres[0].cert_pem 
    }
}

## TODO: Probably separate and create helm module
resource "helm_release" "services" {
    for_each = {
        for servicename, service in var.kube_services:
        servicename => service
        if service.enabled
    }
    depends_on = [ kubernetes_secret_v1.postgres_tls ]
    name              = each.key
    chart             = each.value.chart
    namespace         = lookup(each.value, "namespace", "default")
    create_namespace  = each.value.create_namespace
    repository        = each.value.chart_url
    version           = each.value.chart_version
    timeout           = lookup(each.value, "timeout", 300)
    force_update      = false
    recreate_pods     = false
    dependency_update = true
    wait              = lookup(each.value, "wait", true)
    replace           = lookup(each.value, "replace", false)
    values            = concat(
        [for f in each.value.opt_value_files: templatefile("${path.module}/helm_values/${f}", {host=var.root_domain_name})],
        [for key, values in local.tf_helm_values: values if key == each.key]
    )
}

data "kubernetes_secret_v1" "gitlab_filestore" {
    count = local.mattermost_enabled && !local.external_storage_enabled ? 1 : 0
    ## Create dependency to wait for gitlab to be launched before trying to read secret
    depends_on = [ helm_release.services["mattermost"] ]
    metadata {
        name = local.gitlab_filestore_secret
        namespace = "gitlab"
    }
}

resource "kubectl_manifest" "mattermost" {
    for_each = {
        for key, file in local.mattermost_files:
        key => file
        if local.mattermost_enabled
    }
    depends_on = [ helm_release.services["mattermost"] ]
    yaml_body = each.value
}

## TODO: Retore gitlab/mattermost opt
## TODO: Kubernetes jobs using kubectl image instead of null_resource.local_exec
resource "null_resource" "restore_mattermost_scaledown" {
    count = local.mattermost_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [
        helm_release.services["mattermost"],
        kubectl_manifest.mattermost,
    ]
    provisioner "local-exec" {
        ## Scale mattermost down
        command = "kubectl -n mattermost-operator scale deploy mattermost-operator --replicas=0; kubectl -n mattermost scale deploy mattermost --replicas=0 || true"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}

resource "null_resource" "restore_mattermost_newdb" {
    count = local.mattermost_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubectl_manifest.mattermost,
        null_resource.restore_mattermost_scaledown,
    ]
    provisioner "local-exec" {
        ## DROP DB
        command = "echo \"${local.mattermost_db_auth.password}\" | kubectl -n mattermost exec postgresql-0 -it -- dropdb -U ${local.mattermost_db_auth.username} -h postgresql ${local.mattermost_db_auth.database}"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
    provisioner "local-exec" {
        ## CREATE DB
        command = "echo \"${local.mattermost_db_auth.password}\" | kubectl -n mattermost exec postgresql-0 -it -- createdb -U ${local.mattermost_db_auth.username} -h postgresql ${local.mattermost_db_auth.database}"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}

resource "kubernetes_config_map_v1" "restore_mattermost_script" {
    count = local.mattermost_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubectl_manifest.mattermost,
        null_resource.restore_mattermost_scaledown,
        null_resource.restore_mattermost_newdb,
    ]
    metadata {
        name = "restore-script"
        namespace = "mattermost"
    }
    data = {
        "restore_mattermost.sh" = "${file("${path.module}/scripts/restore_mattermost.sh")}"
    }
}

resource "kubernetes_job_v1" "restore_mattermost_refreshdb" {
    count = local.mattermost_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubectl_manifest.mattermost,
        null_resource.restore_mattermost_scaledown,
        null_resource.restore_mattermost_newdb,
        kubernetes_config_map_v1.restore_mattermost_script,
    ]
    metadata {
        name = "restore-mattermost"
        namespace = "mattermost"
    }
    spec {
        template {
            metadata {}
            spec {
                volume {
                    name = "mattermost-restore"
                    config_map {
                        name = kubernetes_config_map_v1.restore_mattermost_script[0].metadata[0].name
                        default_mode = "0777"
                    }
                }
                container {
                    name    = "restore"
                    image   = "ubuntu"
                    ## TODO: Configurable alias
                    command = ["bash", "-c", "/tmp/mm/restore_mattermost.sh -a spaces -b ${var.s3_backup_bucket} -k ${var.s3_access_key_id} -s ${var.s3_secret_access_key} -u ${local.mattermost_db_auth.username} -p ${local.mattermost_db_auth.password} -r ${var.s3_region} -n ${local.mattermost_filestore.bucket}"]
                    volume_mount {
                        name       = "mattermost-restore"
                        mount_path = "/tmp/mm"
                    }
                }
                restart_policy = "Never"
            }
        }
        backoff_limit = 0
    }
    wait_for_completion = true
    timeouts {
        create = "2m"
        update = "2m"
    }
}

resource "null_resource" "restore_mattermost_scaleup" {
    count = local.mattermost_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubectl_manifest.mattermost,
        null_resource.restore_mattermost_scaledown,
        null_resource.restore_mattermost_newdb,
        kubernetes_config_map_v1.restore_mattermost_script,
        kubernetes_job_v1.restore_mattermost_refreshdb,
    ]
    provisioner "local-exec" {
        ## Scale mattermost-operator back up (takes care of mattermost deployment)
        command = "kubectl -n mattermost-operator scale deploy mattermost-operator --replicas=1;"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}

### TODO: To test
## X Restore using current backup
## X Backup helm deployed mattermost using below backup method
## X Delete/destroy running mattermost
## Empty mattermost bucket - forgot this step
## X Restore using backup from the helm deployed mattermost, not the original restore

## Also try to do with gitlab similarly as well, restore, backup helm deployed version, then restore from that backup
## Once backup and restore from helm deployed version work, I say send it

## a db dump and download data, tar, and send to backup bucket
resource "kubernetes_config_map_v1" "backup_mattermost_script" {
    count = local.mattermost_enabled && local.mattermost_backups_enabled ? 1 : 0
    depends_on = [
        null_resource.restore_mattermost_scaleup
    ]
    metadata {
        name = "backup-mattermost"
        namespace = "mattermost"
    }
    data = {
        "backup_mattermost.sh" = "${file("${path.module}/scripts/backup_mattermost.sh")}"
    }
}

resource "kubernetes_job_v1" "backup_mattermost" {
    ## TODO: Disabled until cronjob
    count = local.mattermost_enabled && local.mattermost_backups_enabled ? 0 : 0
    depends_on = [
        null_resource.restore_mattermost_scaleup,
        kubernetes_config_map_v1.backup_mattermost_script
    ]
    metadata {
        name = "backup-mattermost"
        namespace = "mattermost"
    }
    ### TODO: Cron schedule
    spec {
        template {
            metadata {}
            spec {
                volume {
                    name = "backup-mattermost"
                    config_map {
                        name = kubernetes_config_map_v1.backup_mattermost_script[0].metadata[0].name
                        default_mode = "0777"
                    }
                }
                container {
                    name    = "backup"
                    image   = "ubuntu"
                    command = ["bash", "-c", "/tmp/mattermost/backup_mattermost.sh -a spaces -b ${var.s3_backup_bucket} -k ${var.s3_access_key_id} -s ${var.s3_secret_access_key} -r ${var.s3_region} -m ${var.source_env_bucket_prefix} -n ${var.target_env_bucket_prefix} -u ${local.mattermost_db_auth.username} -p ${local.mattermost_db_auth.password}"]
                    volume_mount {
                        name       = "backup-mattermost"
                        mount_path = "/tmp/mattermost/backup_mattermost.sh"
                        sub_path   = "backup_mattermost.sh"
                    }
                }
                restart_policy = "Never"
            }
        }
        backoff_limit = 0
    }
    wait_for_completion = true
    timeouts {
        create = "2m"
        update = "2m"
    }
}


#resource "null_resource" "managed_kubernetes" {
#    count = contains(var.container_orchestrators, "managed_kubernetes") ? 1 : 0
#    provisioner "local-exec" {
#        command = <<-EOF
#            ansible-playbook ${path.module}/playbooks/managed_kubernetes.yml -i ${var.ansible_hostfile} --extra-vars \
#                'root_domain_name=${var.root_domain_name}
#                kube_app_services=${jsonencode(local.kube_app_services)}'
#        EOF
#    }
#}


## Goal is to only cleanup kubernetes volumes on 'terraform destroy'
## TODO: Forgot to test with attached volumes/volumes attached to pods..
#resource "null_resource" "cleanup_cluster_volumes" {
#    count = contains(var.container_orchestrators, "kubernetes") && var.cleanup_kube_volumes ? 1 : 0
#    ## Untested/Unsure how to handle with managed kubernetes atm
#    #count = contains(var.container_orchestrators, "managed_kubernetes") ? 1 : 0
#
#    depends_on = [
#        null_resource.kubernetes,
#        null_resource.managed_kubernetes,
#        null_resource.apps,
#        helm_release.services,
#    ]
#
#    triggers = {
#        predestroy_hostfile = var.predestroy_hostfile
#    }
#
#    provisioner "local-exec" {
#        when = destroy
#        command = <<-EOF
#            ansible-playbook ${path.module}/playbooks/cleanup_kube_volumes.yml -i ${self.triggers.predestroy_hostfile}
#        EOF
#    }
#}
