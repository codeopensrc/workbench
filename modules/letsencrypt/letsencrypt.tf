#  *Nginx proxies require an nginx config change/hup once we get certs
# Boils down to, the server/ip var.root_domain_name points to, needs a proxy for port 80/http initially
# After getting certs, restart then supports https and http -> https
# TODO: Better support potential downtime when replacing certs
variable "ansible_hosts" {}
variable "ansible_hostfile" {}

variable "is_only_leader_count" {}
variable "lead_servers" {}
variable "admin_servers" {}

variable "app_definitions" {}
variable "additional_ssl" {}

variable "root_domain_name" {}
variable "contact_email" {}

locals {
    admin_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "admin")
    ]
    lead_public_ips = [
        for HOST in var.ansible_hosts:
        HOST.ip
        if contains(HOST.roles, "lead")
    ]
}


# TODO: Turn this into an ansible playbook
resource "null_resource" "setup_letsencrypt" {
    count = var.lead_servers > 0 ? 1 : 0

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
    }

    provisioner "file" {
        content = templatefile("${path.module}/templates/letsencrypt_vars.tmpl", {
            app_definitions = var.app_definitions,
            fqdn = var.root_domain_name,
            email = var.contact_email,
            dry_run = false,
            additional_ssl = var.additional_ssl
        })
        destination = "/root/code/scripts/letsencrypt_vars.sh"
    }

    provisioner "file" {
        content = file("${path.module}/templates/letsencrypt.tmpl")
        destination = "/root/code/scripts/letsencrypt.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /root/code/scripts/letsencrypt.sh",
            "export RUN_FROM_CRON=true; bash /root/code/scripts/letsencrypt.sh",
            "sed -i \"s|#ssl_certificate|ssl_certificate|\" /etc/nginx/conf.d/*.conf",
            "sed -i \"s|#ssl_certificate_key|ssl_certificate_key|\" /etc/nginx/conf.d/*.conf",
            "sed -i \"s|#listen 443 ssl|listen 443 ssl|\" /etc/nginx/conf.d/*.conf",
            (var.admin_servers > 0 ? "gitlab-ctl reconfigure" : "echo 0"),
        ]
        ## If we find reconfigure screwing things up, maybe just try hup nginx
        ## "gitlab-ctl hup nginx"
    }

    connection {
        host = element(concat(local.admin_public_ips, local.lead_public_ips), 0)
        type = "ssh"
    }

}


# TODO: Turn this into an ansible playbook
# Restart service, re-fetching ssl keys
resource "null_resource" "add_keys" {
    count = var.is_only_leader_count
    depends_on = [ null_resource.setup_letsencrypt ]

    triggers = {
        num_apps = length(keys(var.app_definitions))
        num_ssl = length(var.additional_ssl)
    }

    provisioner "file" {
        content = <<-EOF
            LETSENCRYPT_DIR=/etc/letsencrypt/live/${var.root_domain_name}
            mkdir -p $LETSENCRYPT_DIR
            consul kv get ssl/fullchain > $LETSENCRYPT_DIR/fullchain.pem;
            consul kv get ssl/privkey > $LETSENCRYPT_DIR/privkey.pem;
        EOF
        destination = "/tmp/fetch_ssl_certs.sh"
    }
    provisioner "remote-exec" {
        inline = [
            "sed -i \"s|#ssl_certificate|ssl_certificate|\" /etc/nginx/conf.d/*.conf",
            "sed -i \"s|#ssl_certificate_key|ssl_certificate_key|\" /etc/nginx/conf.d/*.conf",
            "sed -i \"s|#listen 443 ssl|listen 443 ssl|\" /etc/nginx/conf.d/*.conf",
            "bash /tmp/fetch_ssl_certs.sh",
            "sudo systemctl reload nginx",
        ]
    }
    connection {
        ##TODO: tolist(setsubtract()) will always create an unpredictable ip order no matter previous sort until ansible
        host = element(tolist(setsubtract(local.lead_public_ips, local.admin_public_ips)), count.index)
        type = "ssh"
    }
}
