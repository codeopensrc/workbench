variable "s3alias" {}
variable "s3bucket" {}
variable "bot_gpg_name" { default = "" }
variable "bot_gpg_passphrase" { default = "" }
variable "tmp_pubkeylist" { default = "pubkeylist.asc" }

variable "admin_public_ips" { default = [] }
variable "db_public_ips" { default = [] }
variable "admin_servers" { default = 0 }
variable "is_only_db_count" { default = 0 }

resource "null_resource" "gpg_download" {
    triggers = {
        ## TODO: Better determine triggers
        ## TODO: Better determine machines that require it
        num_machines_require_gpg = sum([var.admin_servers, var.is_only_db_count])
    }

    ### Download encrypted gpg key on remote server
    provisioner "remote-exec" {
        inline = [ 
            "/usr/local/bin/mc cp ${var.s3alias}/${var.s3bucket}/${var.bot_gpg_name}.asc.gpg $HOME/${var.bot_gpg_name}.asc.gpg"
        ]
    }

    provisioner "local-exec" {
        command = <<-EOF
            ### Copy from remote server to local machine
            IP=${element(distinct(concat(var.admin_public_ips, var.db_public_ips)), 0)}
            ssh-keyscan -H $IP >> ~/.ssh/known_hosts
            scp root@$IP:~/${var.bot_gpg_name}.asc.gpg .

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
    provisioner "remote-exec" {
        inline = [ "rm $HOME/${var.bot_gpg_name}.asc.gpg" ]
    }

    connection {
        host = element(distinct(concat(var.admin_public_ips, var.db_public_ips)), 0)
        type = "ssh"
    }
}

resource "null_resource" "gpg_upload" {
    ## Only admin and DB should need it atm
    count = sum([var.admin_servers, var.is_only_db_count])
    depends_on = [
        null_resource.gpg_download
    ]
    provisioner "file" {
        source = "${var.bot_gpg_name}.asc"
        destination = "~/${var.bot_gpg_name}.asc"
    }
    provisioner "file" {
        content = var.bot_gpg_passphrase
        destination = "~/${var.bot_gpg_name}"
    }
    provisioner "remote-exec" {
        inline = [
            <<-EOF
                ### Temporarily using remote pubkeys as recipients
                /usr/local/bin/mc cp ${var.s3alias}/${var.s3bucket}/${var.tmp_pubkeylist} $HOME/${var.tmp_pubkeylist}
                gpg --import --batch $HOME/${var.tmp_pubkeylist}

                gpg --import --batch ~/${var.bot_gpg_name}.asc
                gpg --list-keys | sed -r -n "s/ +([0-9A-H]{10,})/\1:6:/p" | gpg --import-ownertrust
                rm ~/${var.bot_gpg_name}.asc
                rm ~/${var.tmp_pubkeylist}
            EOF
        ]
    }
    connection {
        host = element(distinct(concat(var.admin_public_ips, var.db_public_ips)), count.index)
        type = "ssh"
    }
}

resource "null_resource" "gpg_clean_files" {
    depends_on = [
        null_resource.gpg_download,
        null_resource.gpg_upload
    ]
    triggers = {
        ## TODO: Better determine triggers
        ## TODO: Better determine machines that require it
        num_machines_require_gpg = sum([var.admin_servers, var.is_only_db_count])
    }
    provisioner "local-exec" {
        command = <<-EOF
            echo "Removing local keyfiles"
            rm ${var.bot_gpg_name}.asc
            rm ${var.bot_gpg_name}.asc.gpg
        EOF
    }
}
