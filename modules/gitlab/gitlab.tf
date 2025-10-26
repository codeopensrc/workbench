variable "local_init_filepath" {}
variable "local_kubeconfig_path" {}
variable "root_domain_name" {}
variable "contact_email" {}

variable "gitlab_enabled" {}
variable "import_gitlab" {}
variable "import_gitlab_version" {}

variable "use_gpg" {}
variable "bot_gpg_name" {}

#variable "s3alias" {}
#variable "s3bucket" {}

variable "source_env_bucket_prefix" {}
variable "target_env_bucket_prefix" {}
variable "gitlab_backups_enabled" {}
variable "gitlab_dump_name" {}
variable "imported_runner_token" {}
variable "gitlab_secrets_body" {}
variable "env_bucket_prefix" {}
variable "s3_region" {}
variable "s3_access_key_id" {}
variable "s3_secret_access_key" {}
variable "s3_endpoint" {}
variable "s3_backup_bucket" {}

variable "mattermost_subdomain" {}
variable "wekan_subdomain" {}

##NOTE: Testing trying to create dependency from gitlab to gitlab provider
## and feed it through terraform so we can use the gitlab data source
## and get gitlab oauth app info and feed it into wekan/other helm charts
output "gitlab_pat" {
    ## Gitlab provider does not work on first apply with a non-static token
    ##   so we provide a static init token that expires in a day (TODO: Test under 24 hours exp time)
    value = (fileexists(var.local_init_filepath) && var.gitlab_enabled
        ? random_password.gitlab_tf_api_pat[0].result
        : "init-fresh-terra-token")
    depends_on = [
        helm_release.services,
        random_password.gitlab_tf_api_pat,
        null_resource.create_tf_gitlab_pat,
    ]
}

locals {
    allow_backups = terraform.workspace == "default"
    gitlab_backups_enabled = var.gitlab_backups_enabled && local.allow_backups
    gitlab_rails_secret = "gitlab-rails-secret"
    gitlab_objectstore_secret = "gitlab-objectstore-secret"
    gitlab_toolbox_objectstore_secret = "gitlab-toolbox-objectstore-secret"
    gitlab_registry_objectstore_secret = "gitlab-registry-objectstore-secret"
    gitlab_runner_secret = "${local.charts["gitlab"].release_name}-gitlab-runner-secret"

    external_storage_enabled = (var.gitlab_enabled && var.env_bucket_prefix != ""
        && var.s3_region != "" && var.s3_access_key_id != "" && var.s3_secret_access_key != ""
        && var.s3_endpoint != "")

    restore_gitlab = var.gitlab_enabled && var.import_gitlab && local.external_storage_enabled && var.gitlab_secrets_body != ""

    gitlab_secrets_json = jsondecode(local.restore_gitlab ? var.gitlab_secrets_body : "{}")

    num_gitlab_sidekiq_pods = 1
    num_gitlab_webservice_pods = 2
    gitlab_dump_name = var.gitlab_dump_name != "" ? var.gitlab_dump_name : "dump_gitlab_backup"

    global_object_store = chomp(local.global_object_store_heredoc)
    global_object_store_heredoc = <<-EOF
    enabled: ${local.external_storage_enabled}
    proxy_download: true
    connection:
      secret: ${local.gitlab_objectstore_secret}
      key: connection
    EOF

    toolbox_objectstore_configs = chomp(local.toolbox_objectstore_configs_heredoc)
    toolbox_objectstore_configs_heredoc = <<-EOF
    backups:
      objectStorage:
        config:
          secret: ${local.gitlab_toolbox_objectstore_secret}
          key: config
    EOF

    registry_objectstore_bucket = "${var.env_bucket_prefix}-gitlab-registry"
    registry_objectstore_config = chomp(local.registry_objectstore_config_heredoc)
    registry_objectstore_config_heredoc = <<-EOF
    storage:
      secret: ${local.gitlab_registry_objectstore_secret}
      key: config
    EOF

    pages_cfg = <<-EOF
    global:
      pages:  #pages bucket to be added with connection
        enabled: false
        host: <hostname>
        artifactsServer: true
        objectStore:
          ${local.global_object_store}
          bucket: ${var.env_bucket_prefix}-gitlab-pages
    EOF

    global_objectstore_appConfig = chomp(local.global_objectstore_appConfig_heredoc)
    global_objectstore_appConfig_heredoc = <<-EOF
    appConfig:
      object_store:
        ${indent(4, local.global_object_store)}
      lfs:
        enabled: ${local.external_storage_enabled}
        proxy_download: false
        bucket: ${var.env_bucket_prefix}-gitlab-lfs
      artifacts:
        enabled: ${local.external_storage_enabled}
        proxy_download: true
        bucket: ${var.env_bucket_prefix}-gitlab-artifacts
      uploads:
        enabled: ${local.external_storage_enabled}
        proxy_download: true
        bucket: ${var.env_bucket_prefix}-gitlab-uploads
      packages:
        enabled: ${local.external_storage_enabled}
        proxy_download: true
        bucket: ${var.env_bucket_prefix}-gitlab-packages
      externalDiffs:
        enabled: ${local.external_storage_enabled}
        proxy_download: true
        bucket: ${var.env_bucket_prefix}-gitlab-mr-diffs
      terraformState:
        enabled: ${local.external_storage_enabled}
        bucket: ${var.env_bucket_prefix}-gitlab-terraform-state
      ciSecureFiles:
        enabled: ${local.external_storage_enabled}
        bucket: ${var.env_bucket_prefix}-gitlab-ci-secure-files
      dependencyProxy:
        enabled: ${local.external_storage_enabled}
        proxy_download: true
        bucket: ${var.env_bucket_prefix}-gitlab-dep-proxy
      backups:
        bucket: ${var.s3_backup_bucket}
        tmpBucket: ${var.env_bucket_prefix}-gitlab-tmp-backups
    EOF

    charts = {
        #TODO: Need external postgres, redis, and possibly gitaly
        gitlab = {
            "enabled"          = var.gitlab_enabled
            "release_name"     = "gitlab"
            "chart"            = "gitlab"
            "namespace"        = "gitlab"
            "create_namespace" = false
            "chart_url"        = "https://charts.gitlab.io"
            "chart_version"    = "9.4.1"
            "wait"             = true
            "replace"          = false
            "timeout"          = 1200
            "opt_value_files"  = []
        }
    }
    gitlab_nodeselector = chomp(local.gitlab_nodeselector_heredoc)
    gitlab_nodeselector_heredoc= <<-EOF
    nodeSelector:
      type: gitlab
    tolerations:
      - key: "type"
        operator: "Equal"
        value: "gitlab"
        effect: "NoSchedule"
    EOF

    gitlab_affinity = chomp(local.gitlab_affinity_heredoc)
    gitlab_affinity_heredoc = <<-EOF
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: type
              operator: NotIn
              values:
              - main
    EOF

    tf_helm_values = {
        gitlab = <<-EOF
        global:
          minio:
            enabled: ${!local.external_storage_enabled}
          ${indent(2, local.global_objectstore_appConfig)}
          registry:
            bucket: ${local.registry_objectstore_bucket}
          edition: ce
          hosts:
            domain: ${var.root_domain_name}
          ingress:
            class: "nginx"
            configureCertmanager: false
            tls:
              enabled: true
            annotations:
              cert-manager.io/cluster-issuer: letsencrypt-prod
        installCertmanager: false
        nginx-ingress:
          enabled: false
        gitlab:
          gitaly:
            ${indent(4, local.gitlab_nodeselector)}
          toolbox:
            ${indent(4, local.gitlab_nodeselector)}
            ${local.external_storage_enabled ? indent(4, local.toolbox_objectstore_configs) : ""}
          gitlab-shell:
            ${indent(4, local.gitlab_nodeselector)}
          gitlab-exporter:
            ${indent(4, local.gitlab_nodeselector)}
          webservice:
            ingress:
              tls:
                secretName: ${local.charts["gitlab"].release_name}-gitlab-tls
            nodeSelector:
              type: gitlab-web
            tolerations:
              - key: "type"
                operator: "Equal"
                value: "gitlab-web"
                effect: "NoSchedule"
          kas:
            ${indent(4, local.gitlab_nodeselector)}
            ingress:
              tls:
                secretName: ${local.charts["gitlab"].release_name}-kas-tls
        registry:
          ${local.external_storage_enabled ? indent(2, local.registry_objectstore_config) : ""}
          ${indent(2, local.gitlab_nodeselector)}
          ingress:
            tls:
              secretName: ${local.charts["gitlab"].release_name}-registry-tls
        minio:
          ${indent(2, local.gitlab_nodeselector)}
          ingress:
            tls:
              secretName: ${local.charts["gitlab"].release_name}-minio-tls
        gitlab-runner:
          ${indent(2, local.gitlab_affinity)}
        prometheus:
          server:
            ${indent(4, local.gitlab_affinity)}
        redis:
          master:
            ${indent(4, local.gitlab_affinity)}
        postgresql:
          ${indent(2, local.gitlab_affinity)}
        EOF
    }
}


resource "kubernetes_namespace" "gitlab" {
    count = var.gitlab_enabled ? 1 : 0
    metadata {
        name = "gitlab"
    }
}
resource "kubernetes_secret_v1" "gitlab_objectstore_secret" {
    count = var.gitlab_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [ kubernetes_namespace.gitlab ]
    metadata {
        name = local.gitlab_objectstore_secret
        namespace = "gitlab"
    }
    data = {
        connection = yamlencode({
            provider = "AWS"
            region = var.s3_region
            aws_access_key_id = var.s3_access_key_id
            aws_secret_access_key = var.s3_secret_access_key
            endpoint = var.s3_endpoint
        })
    }
}
resource "kubernetes_secret_v1" "gitlab_registry_objectstore_secret" {
    count = var.gitlab_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [ kubernetes_namespace.gitlab ]
    metadata {
        name = local.gitlab_registry_objectstore_secret
        namespace = "gitlab"
    }
    data = {
        config = yamlencode({
            s3 = {
                bucket = local.registry_objectstore_bucket
                accesskey = var.s3_access_key_id
                secretkey = var.s3_secret_access_key
                region = var.s3_region
                regionendpoint = var.s3_endpoint
            }
        })
    }
}
resource "kubernetes_secret_v1" "gitlab_toolbox_objectstore_secret" {
    count = var.gitlab_enabled && local.external_storage_enabled ? 1 : 0
    depends_on = [ kubernetes_namespace.gitlab ]
    metadata {
        name = local.gitlab_toolbox_objectstore_secret
        namespace = "gitlab"
    }
    data = {
        config = <<-EOF
        [default]
        access_key = ${var.s3_access_key_id}
        secret_key = ${var.s3_secret_access_key}
        host_base = ${replace(var.s3_endpoint, "https://", "")}
        host_bucket = ${replace(var.s3_endpoint, "https://", "")}
        use_https = True
        EOF
    }
}

resource "helm_release" "services" {
    for_each = {
        for servicename, service in local.charts:
        servicename => service
        if service.enabled && lookup(service, "chart", "") != ""
    }
    depends_on        = [ kubernetes_namespace.gitlab ]
    name              = each.value.release_name
    chart             = each.value.chart
    namespace         = lookup(each.value, "namespace", "default")
    create_namespace  = each.value.create_namespace
    repository        = each.value.chart_url
    version           = lookup(each.value, "chart_version", null)
    timeout           = lookup(each.value, "timeout", 300)
    force_update      = true
    recreate_pods     = false
    dependency_update = true
    wait              = lookup(each.value, "wait", true)
    replace           = lookup(each.value, "replace", false)
    values            = concat(
        [for f in each.value.opt_value_files: file("${path.module}/helm_values/${f}")],
        [for key, values in local.tf_helm_values: values if key == each.key]
    )
}

resource "kubernetes_secret_v1_data" "gitlab_rails_secret" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [ helm_release.services["gitlab"] ]
    metadata {
        name = local.gitlab_rails_secret
        namespace = "gitlab"
    }
    force = true
    data = {
        "secrets.yml" = yamlencode({
            "production": lookup(local.gitlab_secrets_json, "gitlab_rails", "")
        })
    }
}

## Not the most ideal way but simplest way to get it working using local kubectl command
## Creating a new job/pod with all the configs of the running toolbox is a little extra for now

###TODO: Turn these local-exec provisioners into remote kubernetes jobs
resource "null_resource" "restore_gitlab_restart_pods" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret
    ]
    provisioner "local-exec" {
        command = "kubectl delete pods -n gitlab -lapp=sidekiq,release=gitlab; kubectl delete pods -n gitlab -lapp=webservice,release=gitlab; kubectl delete pods -n gitlab -lapp=toolbox,release=gitlab"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}
resource "null_resource" "restore_gitlab_scale_down" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
    ]
    provisioner "local-exec" {
        command = "kubectl scale deploy -lapp=sidekiq,release=gitlab -n gitlab --replicas=0; kubectl scale deploy -lapp=webservice,release=gitlab -n gitlab --replicas=0"
        ##kubectl scale deploy -lapp=prometheus,release=gitlab -n gitlab --replicas=0
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}
resource "null_resource" "restore_gitlab_toolbox_restore" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
    ]
    provisioner "local-exec" {
        command = "POD=$(kubectl get pods -n ${local.charts.gitlab.namespace} -lapp=toolbox --no-headers -o custom-columns=NAME:.metadata.name); kubectl exec -n gitlab $POD -it -- backup-utility --restore -t ${local.gitlab_dump_name} --skip-restore-prompt"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}
resource "null_resource" "restore_gitlab_scale_up" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
    ]
    provisioner "local-exec" {
        command = "kubectl scale deploy -lapp=sidekiq,release=gitlab -n gitlab --replicas=${local.num_gitlab_sidekiq_pods}; kubectl scale deploy -lapp=webservice,release=gitlab -n gitlab --replicas=${local.num_gitlab_webservice_pods}"
        #kubectl scale deploy -lapp=prometheus,release=<helm release name> -n <namespace> --replicas=<value>
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}
resource "null_resource" "restore_gitlab_wait" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
        null_resource.restore_gitlab_scale_up,
    ]
    provisioner "local-exec" {
        command = "kubectl rollout status deploy -lapp=webservice,release=gitlab -n gitlab"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}
resource "kubernetes_secret_v1_data" "gitlab_runner_secret" {
    count = local.restore_gitlab ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
        null_resource.restore_gitlab_scale_up,
        null_resource.restore_gitlab_wait,
    ]
    metadata {
        name = local.gitlab_runner_secret
        namespace = "gitlab"
    }
    force = true
    data = {
        "runner-registration-token" = var.imported_runner_token
        "runner-token" = ""
    }
}

resource "random_password" "gitlab_tf_api_pat" {
    count = var.gitlab_enabled ? 1 : 0
    length           = 20
    special          = false
}
resource "null_resource" "create_tf_gitlab_pat" {
    count = var.gitlab_enabled ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
        null_resource.restore_gitlab_scale_up,
        null_resource.restore_gitlab_wait,
    ]
    triggers = {
        forced_update_trigger_var = ""
    }
    provisioner "local-exec" {
        command = "POD=$(kubectl get pods -n ${local.charts.gitlab.namespace} -lapp=toolbox --no-headers -o custom-columns=NAME:.metadata.name); kubectl exec -n ${local.charts.gitlab.namespace} -it -c toolbox $POD -- gitlab-rails runner \"inittoken = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'INIT TF API PAT', expires_at: 1.days.from_now); inittoken.set_token('init-fresh-terra-token'); inittoken.save; token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'TF API PAT', expires_at: 363.days.from_now); token.set_token('${random_password.gitlab_tf_api_pat[0].result}'); token.save!\""
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}

resource "kubernetes_config_map_v1" "backup_gitlab_script" {
    count = var.gitlab_enabled && local.gitlab_backups_enabled ? 1 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
        null_resource.restore_gitlab_scale_up,
        null_resource.restore_gitlab_wait,
    ]
    metadata {
        name = "backup-gitlab"
        namespace = "gitlab"
    }
    data = {
        "backup_gitlab.sh" = "${file("${path.module}/scripts/backup_gitlab.sh")}"
    }
}

## TODO: cronjob on same schedule minus about 10 minutes
### TODO: Toolbox has cron backup built-in!
## https://docs.gitlab.com/charts/charts/gitlab/toolbox/#configuration
## https://docs.gitlab.com/charts/backup-restore/backup/#cron-based-backup
resource "null_resource" "gitlab_toolbox_backup" {
    ## Working standalone backup
    ## TODO: Disabled until cronjob
    count = var.gitlab_enabled && local.gitlab_backups_enabled ? 0 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
        null_resource.restore_gitlab_scale_up,
        null_resource.restore_gitlab_wait,
        kubernetes_config_map_v1.backup_gitlab_script,
    ]
    provisioner "local-exec" {
        ##TODO: try  -t TIMESTAMP      Timestamp (part before '_gitlab_backup.tar' in archive name),
        ##                             can be used to specify backup source or target name.
        command = "POD=$(kubectl get pods -n ${local.charts.gitlab.namespace} -lapp=toolbox --no-headers -o custom-columns=NAME:.metadata.name); kubectl exec -n gitlab $POD -it -- backup-utility --rsyncable --skip artifacts --skip external_diffs --skip lfs --skip uploads --skip packages --skip terraform_state --skip ci_secure_files --skip pages --skip registry"
        interpreter = ["/bin/bash", "-c"]
        environment = {
            KUBECONFIG = var.local_kubeconfig_path
        }
    }
}
## TODO: cronjob on same schedule plus about 10 minutes
resource "kubernetes_job_v1" "backup_gitlab" {
    ## Working standalone backup
    ## TODO: Disabled until cronjob
    count = var.gitlab_enabled && local.gitlab_backups_enabled ? 0 : 0
    depends_on = [
        helm_release.services["gitlab"],
        kubernetes_secret_v1_data.gitlab_rails_secret,
        null_resource.restore_gitlab_restart_pods,
        null_resource.restore_gitlab_scale_down,
        null_resource.restore_gitlab_toolbox_restore,
        null_resource.restore_gitlab_scale_up,
        null_resource.restore_gitlab_wait,
        kubernetes_config_map_v1.backup_gitlab_script,
        null_resource.gitlab_toolbox_backup,
    ]
    metadata {
        name = "backup-gitlab"
        namespace = "gitlab"
    }
    ### TODO: Cron schedule
    spec {
        template {
            metadata {}
            spec {
                volume {
                    name = "backup-gitlab"
                    config_map {
                        name = kubernetes_config_map_v1.backup_gitlab_script[0].metadata[0].name
                        default_mode = "0777"
                    }
                }
                volume {
                    name = "rails-secret"
                    secret {
                        secret_name = local.gitlab_rails_secret
                        default_mode = "0777"
                    }
                }
                container {
                    name    = "backup"
                    image   = "ubuntu"
                    ## TODO: Configurable alias
                    command = ["bash", "-c", "/tmp/gitlab/backup_gitlab.sh -a spaces -b ${var.s3_backup_bucket} -k ${var.s3_access_key_id} -s ${var.s3_secret_access_key} -r ${var.s3_region} -m ${var.source_env_bucket_prefix} -n ${var.target_env_bucket_prefix}"]
                    volume_mount {
                        name       = "backup-gitlab"
                        mount_path = "/tmp/gitlab/backup_gitlab.sh"
                        sub_path   = "backup_gitlab.sh"
                    }
                    volume_mount {
                        name       = "rails-secret"
                        mount_path = "/tmp/gitlab/secrets.yml"
                        sub_path   = "secrets.yml"
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

#resource "null_resource" "prometheus_targets" {
#    count = var.admin_servers
#
#    triggers = {
#        num_targets = var.server_count
#    }
#
#    ## 9107 is consul exporter
#    provisioner "file" {
#            #{
#            #    "targets": ["localhost:9107"]
#            #}
#        content = <<-EOF
#        [
#        %{ for ind, HOST in local.hosts }
#            {
#                "targets": ["${contains(HOST.roles, "admin") ? "localhost" : HOST.private_ip}:9100"],
#                "labels": {
#                    "hostname": "${contains(HOST.roles, "admin") ? "gitlab.${var.root_domain_name}" : HOST.name}",
#                    "public_ip": "${HOST.ip}",
#                    "private_ip": "${HOST.private_ip}",
#                    "nodename": "${HOST.name}"
#                }
#            }${ind < length(local.hosts) - 1 ? "," : ""}
#        %{ endfor }
#        ]
#        EOF
#        destination = "/var/opt/gitlab/prometheus/targets.json"
#    }
#
#    provisioner "file" {
#        content = <<-EOF
#        {
#            "service": {
#                "name": "consulexporter",
#                "port": 9107
#            }
#        }
#        EOF
#        destination = "/etc/consul.d/conf.d/consulexporter.json"
#    }
#
#    provisioner "remote-exec" {
#        inline = [ "consul reload" ]
#    }
#
#    connection {
#        host = element(local.admin_public_ips, 0)
#        type = "ssh"
#    }
#}


### NOTE: GITLAB MEMORY
###  https://techoverflow.net/2020/04/18/how-i-reduced-gitlab-memory-consumption-in-my-docker-based-setup/
###  https://docs.gitlab.com/omnibus/settings/memory_constrained_envs.html
#resource "null_resource" "install_gitlab" {
#    count = var.admin_servers
#
#    # # After renewing certs possibly
#    # sudo gitlab-ctl hup nginx
#
#    # sudo mkdir -p /etc/gitlab/ssl/${var.root_domain_name};
#    # sudo chmod 600 /etc/gitlab/ssl/${var.root_domain_name};
#
#    ### Streamlined in 13.9
#    ### sudo gitlab-rake "gitlab:password:reset[root]"
#    # Ruby helper cmd: Reset Password
#    # gitlab-rails console -e production
#    # user = User.where(id: 1).first
#    # user.password = 'mytemp'
#    # user.password_confirmation = 'secret_pass'
#    # user.save!
#
#    ###! Mattermost defaults
#    ###! /var/opt/gitlab/mattermost   mattermost dir
#    ###! /var/opt/gitlab/mattermost/config.json   for server settings
#    ###! /var/opt/gitlab/mattermost/*plugins      for plugins
#    ###! /var/opt/gitlab/mattermost/data          for server data
#
#    ###! Grafana data located at /var/opt/gitlab/grafana/data/
#    ###! Loaded prometheus config at /var/opt/gitlab/prometheus/prometheus.yml managed by gitlab.rb
#
#    provisioner "remote-exec" {
#        ## KAS url default: wss://gitlab.example.com/-/kubernetes-agent/
#        inline = [
#            <<-EOF
#                sudo gitlab-ctl restart
#                sed -i "s|external_url 'http://[0-9a-zA-Z.-]*'|external_url 'https://gitlab.${var.root_domain_name}'|" /etc/gitlab/gitlab.rb
#                sed -i "s|https://registry.example.com|https://registry.${var.root_domain_name}|" /etc/gitlab/gitlab.rb
#                sed -i "s|# registry_external_url|registry_external_url|" /etc/gitlab/gitlab.rb
#                sed -i "s|# letsencrypt\['enable'\] = nil|letsencrypt\['enable'\] = true|" /etc/gitlab/gitlab.rb
#                sed -i "s|# letsencrypt\['contact_emails'\] = \[\]|letsencrypt\['contact_emails'\] = \['${var.contact_email}'\]|" /etc/gitlab/gitlab.rb
#                sed -i "s|# letsencrypt\['auto_renew'\]|letsencrypt\['auto_renew'\]|" /etc/gitlab/gitlab.rb
#                sed -i "s|# letsencrypt\['auto_renew_hour'\]|letsencrypt\['auto_renew_hour'\]|" /etc/gitlab/gitlab.rb
#                sed -i "s|# letsencrypt\['auto_renew_minute'\] = nil|letsencrypt\['auto_renew_minute'\] = 30|" /etc/gitlab/gitlab.rb
#                sed -i "s|# letsencrypt\['auto_renew_day_of_month'\]|letsencrypt\['auto_renew_day_of_month'\]|" /etc/gitlab/gitlab.rb
#                sed -i "s|# nginx\['custom_nginx_config'\]|nginx\['custom_nginx_config'\]|" /etc/gitlab/gitlab.rb
#                sed -i "s|\"include /etc/nginx/conf\.d/example\.conf;\"|\"include /etc/nginx/conf\.d/\*\.conf;\"|" /etc/gitlab/gitlab.rb
#                sed -i "s|# gitlab_kas\['enable'\] = true|gitlab_kas\['enable'\] = true|" /etc/gitlab/gitlab.rb
#                sed -i "s|# grafana\['enable'\] = false|grafana\['enable'\] = true|" /etc/gitlab/gitlab.rb
#
#                ### Optimization
#                sed -i "s|# puma\['worker_processes'\] = 2|puma\['worker_processes'\] = 0|" /etc/gitlab/gitlab.rb
#                sed -i "s|# sidekiq\['max_concurrency'\] = 50|sidekiq\['max_concurrency'\] = 10|" /etc/gitlab/gitlab.rb
#                sed -i "s|# prometheus_monitoring\['enable'\] = true|prometheus_monitoring\['enable'\] = false|" /etc/gitlab/gitlab.rb
#                sed -i "s|# prometheus\['enable'\] = true|prometheus\['enable'\] = true|" /etc/gitlab/gitlab.rb
#                sed -i "s|# node_exporter\['enable'\] = true|node_exporter\['enable'\] = true|" /etc/gitlab/gitlab.rb
#
#                CONFIG="prometheus['scrape_configs'] = [
#                    {
#                        'job_name': 'node-file',
#                        'honor_labels': true,
#                        'file_sd_configs' => [
#                            'files' => ['/var/opt/gitlab/prometheus/targets.json']
#                        ],
#                    },
#                    {
#                        'job_name': 'consul-exporter',
#                        'honor_labels': true,
#                        'consul_sd_configs' => [
#                            'server': 'localhost:8500',
#                            'services' => ['consulexporter']
#                        ]
#                    },
#                    {
#                        'job_name': 'federate',
#                        'honor_labels': true,
#                        'scrape_interval': '10s',
#                        'metrics_path': '/federate',
#                        'params' => {
#                          'match[]' => ['{app_kubernetes_io_name=\"kube-state-metrics\"}']
#                        },
#                        'static_configs' => [
#                            'targets' => ['prom.k8s-internal.${var.root_domain_name}']
#                        ]
#                    }
#                ]"
#                printf '%s\n' "/# prometheus\['scrape_configs'\]" ".,+7c" "$CONFIG" . wq | ed -s /etc/gitlab/gitlab.rb
#
#
#                sleep 5;
#
#                sed -i "s|# mattermost_external_url 'https://[0-9a-zA-Z.-]*'|mattermost_external_url 'https://${var.mattermost_subdomain}.${var.root_domain_name}'|" /etc/gitlab/gitlab.rb;
#                echo "alias mattermost-cli=\"cd /opt/gitlab/embedded/service/mattermost && sudo /opt/gitlab/embedded/bin/chpst -e /opt/gitlab/etc/mattermost/env -P -U mattermost:mattermost -u mattermost:mattermost /opt/gitlab/embedded/bin/mattermost --config=/var/opt/gitlab/mattermost/config.json $1\"" >> ~/.bashrc
#
#                sleep 5;
#                sudo gitlab-ctl reconfigure;
#            EOF
#        ]
#
#
#        # Enable pages
#        # pages_external_url "http://pages.example.com/"
#        # gitlab_pages['enable'] = false
#    }
#    # sudo chmod 755 /etc/gitlab/ssl;
#
#    # ln -s /etc/letsencrypt/live/registry.${var.root_domain_name}/privkey.pem /etc/gitlab/ssl/registry.${var.root_domain_name}.key
#    # ln -s /etc/letsencrypt/live/registry.${var.root_domain_name}/fullchain.pem /etc/gitlab/ssl/registry.${var.root_domain_name}.crt
#    # "cp /etc/letsencrypt/live/${var.root_domain_name}/privkey.pem /etc/letsencrypt/live/${var.root_domain_name}/fullchain.pem /etc/gitlab/ssl/",
#
#    connection {
#        host = element(local.admin_public_ips, 0)
#        type = "ssh"
#    }
#}


### TODO: Add Temp PAT token once and ensure removed at end of provisioning
### Can be found by searching 'sudo gitlab-rails runner'
### ATM actively used in 5 locations -
###  module.gitlab - restore_gitlab, gitlab_plugins, rm_imported_runners
###  module.kubernetes - addClusterToGitlab script, reboot_envs
#resource "null_resource" "restore_gitlab" {
#    count = var.admin_servers
#    depends_on = [
#        null_resource.install_gitlab,
#    ]
#
#    # NOTE: Sleep is for internal api, takes a second after a restore
#    # Otherwise git clones and docker pulls won't work in the next step
#    # TODO: Hardcoded repo and SNIPPET_ID/filename for remote mirrors file
#    provisioner "remote-exec" {
#        inline = [
#            <<-EOF
#                chmod +x /root/code/scripts/misc/importGitlab.sh;
#
#                TERRA_WORKSPACE=${terraform.workspace}
#                IMPORT_GITLAB=${var.import_gitlab}
#                PASSPHRASE_FILE="${var.use_gpg ? "-p $HOME/${var.bot_gpg_name}" : "" }"
#                if [ ! -z "${var.import_gitlab_version}" ]; then IMPORT_GITLAB_VERSION="-v ${var.import_gitlab_version}"; fi
#
#                if [ "$IMPORT_GITLAB" = "true" ]; then
#                    bash /root/code/scripts/misc/importGitlab.sh -a ${var.s3alias} -b ${var.s3bucket} $PASSPHRASE_FILE $IMPORT_GITLAB_VERSION;
#                    echo "=== Wait 20s for restore ==="
#                    sleep 20
#
#                    if [ "$TERRA_WORKSPACE" != "default" ]; then
#                        echo "WORKSPACE: $TERRA_WORKSPACE, removing remote mirrors"
#                        SNIPPET_ID=34
#                        FILENAME="PROJECTS.txt"
#                        LOCAL_PROJECT_FILE="/tmp/$FILENAME"
#                        LOCAL_MIRROR_FILE="/tmp/MIRRORS.txt"
#
#                        ## Get list of projects with remote mirrors
#                        curl -sL "https://gitlab.${var.root_domain_name}/os/workbench/-/snippets/$SNIPPET_ID/raw/main/$FILENAME" -o $LOCAL_PROJECT_FILE
#
#                        ## Create token to modify all projects
#                        TERRA_UUID=${uuid()}
#                        sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!";
#
#                        ## Iterate through project ids
#                        while read PROJECT_ID; do
#                            ## Get list of projects remote mirror ids
#                            ##  https://docs.gitlab.com/ee/api/remote_mirrors.html#list-a-projects-remote-mirrors
#                            curl -s -H "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/remote_mirrors" | jq ".[].id" > $LOCAL_MIRROR_FILE
#
#                            ## Iterate through remote mirror ids per project
#                            while read MIRROR_ID; do
#                                ## Update each remote mirror attribute --enabled=false
#                                ##  https://docs.gitlab.com/ee/api/remote_mirrors.html#update-a-remote-mirrors-attributes
#                                curl -X PUT --data "enabled=false" -H "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/remote_mirrors/$MIRROR_ID"
#                                sleep 1;
#                            done <$LOCAL_MIRROR_FILE
#
#                        done <$LOCAL_PROJECT_FILE
#
#                        ## Revoke token
#                        sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!";
#                    fi
#
#                fi
#
#                exit 0;
#            EOF
#        ]
#
#        connection {
#            host = element(local.admin_public_ips, 0)
#            type = "ssh"
#        }
#    }
#
#    # Change known_hosts to new imported ssh keys from gitlab restore
#    provisioner "local-exec" {
#        command = <<-EOF
#            ssh-keygen -f ~/.ssh/known_hosts -R "${element(local.admin_public_ips, 0)}"
#            ssh-keygen -f ~/.ssh/known_hosts -R "gitlab.${var.root_domain_name}"
#            ssh-keygen -f ~/.ssh/known_hosts -R "${var.root_domain_name}"
#            ssh-keyscan -H "${element(local.admin_public_ips, 0)}" >> ~/.ssh/known_hosts
#            ssh-keyscan -H "gitlab.${var.root_domain_name}" >> ~/.ssh/known_hosts
#            ssh-keyscan -H "${var.root_domain_name}" >> ~/.ssh/known_hosts
#
#        EOF
#    }
#}

#resource "null_resource" "gitlab_plugins" {
#    count = var.admin_servers
#    depends_on = [
#        null_resource.install_gitlab,
#        null_resource.restore_gitlab,
#    ]
#
#    ###! TODO: Conditionally deal with plugins if the subdomains are present etc.
#    ###! ex: User does not want mattermost or wekan
#
#    ###! TODO: Would be nice if unauthenticated users could view certain channels in mattermost
#    ###! Might be possible if we can create a custom role?
#    ###!   https://docs.mattermost.com/onboard/advanced-permissions-backend-infrastructure.html
#
#    ###! TODO: If we run plugins, then run import again, plugins are messed up
#    ###!  We also need to be able to correctly sed replace grafana (its not rerunnable atm)
#    provisioner "remote-exec" {
#        inline = [
#            <<-EOF
#                PLUGIN1_NAME="WekanPlugin";
#                PLUGIN2_NAME="MattermostPlugin";
#                PLUGIN3_NAME="GrafanaPlugin";
#                PLUGIN3_INIT_NAME="GitLab Grafana";
#                TERRA_UUID=${uuid()}
#                echo $TERRA_UUID;
#
#                ## To initially access grafana as admin, must enable login using user/pass
#                ## https://docs.gitlab.com/omnibus/settings/grafana.html#enable-login-using-username-and-password
#                ## grafana['disable_login_form'] = false
#
#                ## Also MUST change admin password using: `gitlab-ctl set-grafana-password`
#                ## Modifying "grafana['admin_password'] = 'foobar'" will NOT work (multiple reconfigures have occured)
#                ## https://docs.gitlab.com/omnibus/settings/grafana.html#resetting-the-admin-password
#
#                echo "=== Wait 20s for gitlab api for oauth plugins ==="
#                sleep 20;
#
#                sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!";
#
#                PLUGIN1_ID=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN1_NAME\")) | .id");
#                curl --request DELETE --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications/$PLUGIN1_ID";
#
#                sleep 5;
#                OAUTH=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
#                    --data "name=$PLUGIN1_NAME&redirect_uri=https://${var.wekan_subdomain}.${var.root_domain_name}/_oauth/oidc&scopes=openid%20profile%20email" \
#                    "https://gitlab.${var.root_domain_name}/api/v4/applications");
#
#                APP_ID=$(echo $OAUTH | jq -r ".application_id");
#                APP_SECRET=$(echo $OAUTH | jq -r ".secret");
#
#                consul kv put wekan/app_id $APP_ID
#                consul kv put wekan/secret $APP_SECRET
#
#
#
#                FOUND_CORRECT_ID2=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN2_NAME\")) | select(.callback_url | contains (\"${var.root_domain_name}\")) | .id");
#
#                if [ -z "$FOUND_CORRECT_ID2" ]; then
#                    PLUGIN2_ID=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN2_NAME\")) | .id");
#                    curl --request DELETE --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications/$PLUGIN2_ID";
#
#                    OAUTH2=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
#                        --data "name=$PLUGIN2_NAME&redirect_uri=https://${var.mattermost_subdomain}.${var.root_domain_name}/plugins/com.github.manland.mattermost-plugin-gitlab/oauth/complete&scopes=api%20read_user" \
#                        "https://gitlab.${var.root_domain_name}/api/v4/applications");
#
#                    APP_ID2=$(echo $OAUTH2 | jq -r ".application_id");
#                    APP_SECRET2=$(echo $OAUTH2 | jq -r ".secret");
#
#                    sed -i "s|\"gitlaburl\": \"https://[0-9a-zA-Z.-]*\"|\"gitlaburl\": \"https://gitlab.${var.root_domain_name}\"|" /var/opt/gitlab/mattermost/config.json
#                    sed -i "s|\"gitlaboauthclientid\": \"[0-9a-zA-Z.-]*\"|\"gitlaboauthclientid\": \"$APP_ID2\"|" /var/opt/gitlab/mattermost/config.json
#                    sed -i "s|\"gitlaboauthclientsecret\": \"[0-9a-zA-Z.-]*\"|\"gitlaboauthclientsecret\": \"$APP_SECRET2\"|" /var/opt/gitlab/mattermost/config.json
#
#                    sudo gitlab-ctl restart mattermost;
#                fi
#
#                FOUND_CORRECT_ID3=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN3_INIT_NAME\")) | select(.callback_url | contains (\"${var.root_domain_name}\")) | .id");
#
#                ## If we dont find "GitLab Grafana" (initial grafana oauth app), we have to update /etc/gitlab/gitlab.rb every time with our own
#                ## Wish there was a way to revert to the original oauth version after deleting it but not sure how
#                if [ -z "$FOUND_CORRECT_ID3" ]; then
#                    PLUGIN3_ID=$(curl --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications" | jq ".[] | select(.application_name | contains (\"$PLUGIN3_NAME\")) | .id");
#                    curl --request DELETE --header "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/applications/$PLUGIN3_ID";
#
#                    OAUTH3=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
#                        --data "name=$PLUGIN3_NAME&redirect_uri=https://gitlab.${var.root_domain_name}/-/grafana/login/gitlab&scopes=read_user" \
#                        "https://gitlab.${var.root_domain_name}/api/v4/applications");
#
#                    APP_ID3=$(echo $OAUTH3 | jq -r ".application_id");
#                    APP_SECRET3=$(echo $OAUTH3 | jq -r ".secret");
#
#                    sed -i "s|# grafana\['gitlab_application_id'\] = 'GITLAB_APPLICATION_ID'|grafana\['gitlab_application_id'\] = '$APP_ID3'|" /etc/gitlab/gitlab.rb
#                    sed -i "s|# grafana\['gitlab_secret'\] = 'GITLAB_SECRET'|grafana\['gitlab_secret'\] = '$APP_SECRET3'|" /etc/gitlab/gitlab.rb
#
#                    sudo gitlab-ctl reconfigure;
#                fi
#
#                ### Some good default admin settings
#                OUTBOUND_ARR="chat.${var.root_domain_name},10.0.0.0%2F8"
#                curl --request PUT --header "PRIVATE-TOKEN: $TERRA_UUID" \
#                    "https://gitlab.${var.root_domain_name}/api/v4/application/settings?signup_enabled=false&usage_ping_enabled=false&outbound_local_requests_allowlist_raw=$OUTBOUND_ARR"
#
#
#                sleep 3;
#                sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!";
#
#            EOF
#        ]
#    }
#
#    connection {
#        host = element(local.admin_public_ips, 0)
#        type = "ssh"
#    }
#}

## On import, rm all imported runners with tags matching: root_domain_name
## We only rm those matching our root_domain_name due to the "possibility" of external runners registered
## This should suffice until we can successfully fully migrate gitlab without downtime
#resource "null_resource" "rm_imported_runners" {
#    count = var.admin_servers
#    depends_on = [
#        null_resource.install_gitlab,
#        null_resource.restore_gitlab,
#        null_resource.gitlab_plugins,
#    ]
#    provisioner "local-exec" {
#        command = <<-EOF
#            ansible-playbook ${path.module}/playbooks/gitlab.yml -i ${var.ansible_hostfile} --extra-vars \
#                'root_domain_name="${var.root_domain_name}"
#                import_gitlab=${var.import_gitlab}'
#        EOF
#    }
#}

# NOTE: Used to re-authenticate mattermost with gitlab
#resource "null_resource" "reauthorize_mattermost" {
#    count = 0
#    depends_on = [
#        null_resource.install_gitlab,
#        null_resource.restore_gitlab,
#    ]
#
#    provisioner "remote-exec" {
#        ###! Below is necessary for re-authenticating mattermost with gitlab (if initial auth doesnt work)
#        ###! Problem is the $'' style syntax used to preserve \n doesnt like terraform variable expression
#        inline = [
#            <<-EOF
#
#                PLUGIN_NAME="Gitlab Mattermost";
#                TERRA_UUID=${uuid()}
#                echo $TERRA_UUID;
#
#                sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!"
#
#                OAUTH=$(curl --request POST --header "PRIVATE-TOKEN: $TERRA_UUID" \
#                    --data $'name=$PLUGIN_NAME&redirect_uri=https://${var.mattermost_subdomain}.${var.root_domain_name}/signup/gitlab/complete\nhttps://${var.mattermost_subdomain}.${var.root_domain_name}/login/gitlab/complete&scopes=' \
#                    "https://gitlab.${var.root_domain_name}/api/v4/applications");
#
#                APP_ID=$(echo $OAUTH | jq ".application_id");
#                APP_SECRET=$(echo $OAUTH | jq ".secret");
#
#                sed -i "s|# mattermost\['enable'\] = false|mattermost\['enable'\] = true|" /etc/gitlab/gitlab.rb;
#                sed -i "s|# mattermost\['gitlab_enable'\] = false|mattermost\['gitlab_enable'\] = true|" /etc/gitlab/gitlab.rb;
#                sed -i "s|# mattermost\['gitlab_id'\] = \"12345656\"|mattermost\['gitlab_id'\] = $APP_ID|" /etc/gitlab/gitlab.rb;
#                sed -i "s|# mattermost\['gitlab_secret'\] = \"123456789\"|mattermost\['gitlab_secret'\] = $APP_SECRET|" /etc/gitlab/gitlab.rb;
#                sed -i "s|# mattermost\['gitlab_scope'\] = \"\"|mattermost\['gitlab_scope'\] = \"\"|" /etc/gitlab/gitlab.rb;
#                sed -i "s|# mattermost\['gitlab_auth_endpoint'\] = \"http://gitlab.example.com/oauth/authorize\"|mattermost\['gitlab_auth_endpoint'\] = \"https://gitlab.${var.root_domain_name}/oauth/authorize\"|" /etc/gitlab/gitlab.rb
#                sed -i "s|# mattermost\['gitlab_token_endpoint'\] = \"http://gitlab.example.com/oauth/token\"|mattermost\['gitlab_token_endpoint'\] = \"https://gitlab.${var.root_domain_name}/oauth/token\"|" /etc/gitlab/gitlab.rb
#                sed -i "s|# mattermost\['gitlab_user_api_endpoint'\] = \"http://gitlab.example.com/api/v4/user\"|mattermost\['gitlab_user_api_endpoint'\] = \"https://gitlab.${var.root_domain_name}/api/v4/user\"|" /etc/gitlab/gitlab.rb
#
#                sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!"
#
#            EOF
#        ]
#    }
#
#    connection {
#        host = element(local.admin_public_ips, 0)
#        type = "ssh"
#    }
#}
