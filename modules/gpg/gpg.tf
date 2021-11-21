variable "ansible_hosts" {}
variable "ansible_hostfile" {}

variable "admin_servers" {}
variable "db_servers" {}

variable "s3alias" {}
variable "s3bucket" {}
variable "bot_gpg_name" { default = "" }
variable "bot_gpg_passphrase" { default = "" }
variable "tmp_pubkeylist" { default = "pubkeylist.asc" }


resource "null_resource" "gpg_download" {
    triggers = {
        num_admin = var.admin_servers
        num_db = var.db_servers
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/gpg_fetch.yml -i ${var.ansible_hostfile} --tags untagged --extra-vars \
                "bot_gpg_name=${var.bot_gpg_name} s3alias=${var.s3alias} s3bucket=${var.s3bucket}"
        EOF
    }

    provisioner "local-exec" {
        command = <<-EOF
            ### Prompt user to decrypt file using command to continue, loop X times until done or exit

            check_for_keyfile() {
                if [ -f "${var.bot_gpg_name}.asc" ]; then
                    echo "Found decrypted keyfile, continuing";
                    exit 0;
                else
                    echo "==================================================================="
                    echo "==================================================================="
                    echo "Decrypted unattended key not found."
                    echo "In order to prevent an automated prompt for gpg passphase during apply and instead be a conscious action,"
                    echo "    please decrypt the file and place at it the location specified in config."
                    echo "Both local encrypted and decrypted files will be deleted upon successful upload to the server(s)."
                    echo "Current expected keyfile name is ${var.bot_gpg_name}.asc"
                    echo "Command to run from the correct env directory should roughly be:"
                    echo " gpg --decrypt ${var.bot_gpg_name}.asc.gpg > ${var.bot_gpg_name}.asc"
                    echo "==================================================================="
                    echo "==================================================================="
                    echo "Checking again in 40 seconds"

                    sleep 40;
                    check_for_keyfile
                fi
            }

            check_for_keyfile
        EOF
    }

    provisioner "local-exec" {
        command = "ansible-playbook ${path.module}/playbooks/gpg_fetch.yml -i ${var.ansible_hostfile} --tags rm --extra-vars 'bot_gpg_name=${var.bot_gpg_name}'"
    }
}


resource "null_resource" "gpg_upload" {
    depends_on = [
        null_resource.gpg_download
    ]

    triggers = {
        num_admin = var.admin_servers
        num_db = var.db_servers
    }

    #Used in playbook. Its run here to limit output masking
    provisioner "local-exec" {
        command = "echo \"bot_gpg_passphrase: ${var.bot_gpg_passphrase}\" > ${var.bot_gpg_name}.yml"
    }

    provisioner "local-exec" {
        command = <<-EOF
            ansible-playbook ${path.module}/playbooks/gpg_upload.yml -i ${var.ansible_hostfile} --extra-vars \
                "bot_gpg_name=${var.bot_gpg_name} s3alias=${var.s3alias} s3bucket=${var.s3bucket} tmp_pubkeylist=${var.tmp_pubkeylist}"
        EOF
    }

    provisioner "local-exec" {
        command = "rm ${var.bot_gpg_name}.yml"
    }
}

resource "null_resource" "gpg_clean_files" {
    depends_on = [
        null_resource.gpg_download,
        null_resource.gpg_upload
    ]

    triggers = {
        num_admin = var.admin_servers
        num_db = var.db_servers
    }

    provisioner "local-exec" {
        command = <<-EOF
            echo "Removing local keyfiles"
            rm ${var.bot_gpg_name}.asc
            rm ${var.bot_gpg_name}.asc.gpg
        EOF
    }
}
