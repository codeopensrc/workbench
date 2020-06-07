

# TODO: Need separate destroying mechanisms for admin and leader
# resource "null_resource" "destroy" {
#     count      = var.servers
#
#     #### TODO: Need to trigger these on scaling down but not on a "terraform destroy"
#     #### Or maybe a seperate paramater to set to run: scaling_down=true, false by default
#     provisioner "file" {
#         when = destroy
#         content = <<-EOF
#             if [ "${var.role == "manager"}" = "true" ]; then
#                 docker node update --availability="drain" ${element(var.names, count.index)}
#                 sleep 20;
#                 docker node demote ${element(var.names, count.index)}
#                 sleep 5
#             fi
#         EOF
#         destination = "/tmp/leave.sh"
#     }
#
#     ####### On Destroy ######
#     provisioner "remote-exec" {
#         when = destroy
#         ## TODO: Review all folders we create/modify on the server and remove them
#         ##   for no actual reason in particular, just being thorough
#         inline = [
#             "chmod +x /tmp/leave.sh",
#             "/tmp/leave.sh",
#             "docker swarm leave",
#             "docker swarm leave --force;",
#             "systemctl stop consul.service",
#             "rm -rf /etc/ssl",
#             "exit 0;"
#         ]
#         on_failure = continue
#     }
#
#     connection {
#         host    = element(var.public_ips, count.index)
#         type    = "ssh"
#         timeout = "45s"
#     }
# }
