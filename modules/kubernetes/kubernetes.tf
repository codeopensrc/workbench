variable "ansible_hostfile" {}

variable "admin_servers" {}
variable "server_count" {}

variable "lead_public_ips" {}
variable "admin_private_ips" {}
variable "admin_public_ips" {}
variable "all_public_ips" {}

variable "gitlab_runner_tokens" {}
variable "root_domain_name" {}
variable "import_gitlab" {}
variable "vpc_private_iface" {}

variable "kubernetes_version" {}
variable "container_orchestrators" {}


resource "null_resource" "kubernetes_admin" {
    count = contains(var.container_orchestrators, "kubernetes") ? 1 : 0

    ##  digitaloceans private iface = eth1
    ##  aws private iface = ens5
    provisioner "file" {
        content = <<-EOF
            KUBE_SCRIPTS=$HOME/code/scripts/kube
            VERSION=${var.kubernetes_version}
            LEAD_IPS="${join(",", var.lead_public_ips)}"
            ADMIN_IP="${var.admin_servers > 0 ? element(var.admin_private_ips, 0) : ""}"
            RUNNER_ARGS="${var.gitlab_runner_tokens["service"] != "" ? "-t ${var.gitlab_runner_tokens["service"]}" : ""}"
            ## For now if no admin, use 'default' as production namespace
            NGINX_ARGS="${var.admin_servers == 0 ? "-p default" : ""}"

            bash $KUBE_SCRIPTS/startKubeCluster.sh -v $VERSION -i ${var.vpc_private_iface};
            bash $KUBE_SCRIPTS/nginxKubeProxy.sh -r ${var.root_domain_name} $NGINX_ARGS
            ${var.server_count == 1 ? "kubectl taint nodes --all node-role.kubernetes.io/master-;" : ""}
            if [[ ${var.admin_servers} -gt 0 ]]; then
                bash $KUBE_SCRIPTS/createClusterAccounts.sh -v $${VERSION//-00/} -d ${var.root_domain_name} -a $ADMIN_IP $RUNNER_ARGS -u;
                bash $KUBE_SCRIPTS/addClusterToGitlab.sh -d ${var.root_domain_name} -u -r;
            fi
        EOF
        destination = "/tmp/init_kubernetes.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/init_kubernetes.sh",
            "bash /tmp/init_kubernetes.sh"
        ]
    }

    connection {
        host = element(concat(var.admin_public_ips, var.lead_public_ips), 0)
        type = "ssh"
    }
}


resource "null_resource" "kubernetes_worker" {
    count = contains(var.container_orchestrators, "kubernetes") ? var.server_count - 1 : 0
    depends_on = [ null_resource.kubernetes_admin ]

    provisioner "file" {
        content = <<-EOF
            KUBE_SCRIPTS=$HOME/code/scripts/kube
            JOIN_COMMAND=$(consul kv get kube/joincmd)
            VERSION=${var.kubernetes_version}

            bash $KUBE_SCRIPTS/joinKubeCluster.sh -v $VERSION -j "$JOIN_COMMAND";
        EOF
        destination = "/tmp/init_kubernetes.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/init_kubernetes.sh",
            "bash /tmp/init_kubernetes.sh"
        ]
    }

    connection {
        ## TODO: Till refactor, this has an issue where it may reprovision the 
        ##  wrong ip (ips can get reordered) if we scale AFTER the initial bootstrapping
        host = element(tolist(setsubtract(var.all_public_ips, [var.admin_servers > 0 ? var.admin_public_ips[0] : var.lead_public_ips[0]] )), count.index)
        type = "ssh"
    }
}



resource "null_resource" "reboot_environments" {
    count = contains(var.container_orchestrators, "kubernetes") ? var.admin_servers : 0
    depends_on = [
        null_resource.kubernetes_admin,
        null_resource.kubernetes_worker,
    ]

    ## TODO: Move to s3 object storage using gitlab terraform state for file/info
    ## NOTE: ID of project containing snippet and snippet ID hardcoded
    provisioner "file" {
        content = <<-EOF
            #!/bin/bash

            IMPORT_GITLAB=${var.import_gitlab}
            if [ "$IMPORT_GITLAB" != "true" ]; then
                exit 0;
            fi

            FILENAME=ENVS.txt
            SNIPPET_PROJECT_ID=7
            SNIPPET_ID=33
            LOCAL_FILE="$HOME/code/backups/$FILENAME"
            DEFAULT_BRANCH="master"

            ## Download list of production environments
            curl "https://gitlab.${var.root_domain_name}/api/v4/projects/$SNIPPET_PROJECT_ID/snippets/$SNIPPET_ID/files/main/$FILENAME/raw" > $LOCAL_FILE
            ## Alternative without api
            ## curl -sL "https://gitlab.${var.root_domain_name}/os/workbench/-/snippets/$SNIPPET_ID/raw/main/$FILENAME -o $LOCAL_FILE"

            ## Gen tmp TOKEN to trigger deploy_prod job in each project listed
            TERRA_UUID=${uuid()}
            sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TERRA_UUID'); token.save!";

            ## Iterate over projects in $LOCAL_FILE and run pipeline for each
            while read PROJECT_ID; do
                echo $PROJECT_ID;

                ## Create trigger and get [token, id]
                TRIGGER_INFO=( $(curl -X POST -H "PRIVATE-TOKEN: $TERRA_UUID" --form description="reboot" \
                    "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/triggers" | jq -r '.token, .id') )

                ## Trigger pipeline
                curl -X POST --form "variables[ONLY_DEPLOY_PROD]=true" \
                "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/trigger/pipeline?token=$${TRIGGER_INFO[0]}&ref=$DEFAULT_BRANCH"

                ## Delete trigger
                curl -X DELETE -H "PRIVATE-TOKEN: $TERRA_UUID" "https://gitlab.${var.root_domain_name}/api/v4/projects/$PROJECT_ID/triggers/$${TRIGGER_INFO[1]}";

            done <$LOCAL_FILE

            ## Revoke token
            sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TERRA_UUID').revoke!";

        EOF
        destination = "/tmp/reboot_environments.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/reboot_environments.sh",
            "bash /tmp/reboot_environments.sh",
            "rm /tmp/reboot_environments.sh"
        ]
    }

    connection {
        host = element(var.admin_public_ips, 0)
        type = "ssh"
    }
}
