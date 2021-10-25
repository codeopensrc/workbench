variable "lead_servers" { default = "" }
variable "lead_public_ips" { default = "" }
variable "lead_names" { default = "" }
variable "region" { default = "" }

resource "null_resource" "docker_leader" {
    count = var.lead_servers

    # Create a docker swarm
    provisioner "local-exec" {
        # Uses sh
        # TODO: Since we're using scripts for replacing servers... might as well turn this into one
        #   when we finally extract provisioners in an intelligent way instead of this single file mess
        # TODO: We either need a consul kv lookup for other docker swarms of the same version or figure out a good way
        #   to look up and down the line of docker-machines to find an appropriate swarm to join
        command = <<-EOF
            # Not the most ideal solution, but it will cover 70-95% of use cases until
            #   we setup a consul KV store for docker swarm versions and their tokens
            CUR_MACHINE_IP=${element(distinct(concat(var.lead_public_ips)), count.index)}
            PREV_MACHINE_IP=${element(distinct(concat(var.lead_public_ips)), count.index == 0 ? 0 : count.index - 1)}

            ssh-keyscan -H $CUR_MACHINE_IP >> ~/.ssh/known_hosts
            CUR_SWARM_VER=$(ssh root@$CUR_MACHINE_IP "docker -v;")
            PREV_SWARM_VER=$(ssh root@$PREV_MACHINE_IP "docker -v;")
            JOINED_SWARM=false

            if [ "$CUR_SWARM_VER" = "$PREV_SWARM_VER" ] && [ "$CUR_MACHINE_IP" != "$PREV_MACHINE_IP" ]; then
                SLEEP_FOR=$((5 + $((${count.index} * 6)) ))
                echo "JOIN_LEADER IN $SLEEP_FOR"
                sleep $SLEEP_FOR
                JOIN_CMD=$(ssh root@$PREV_MACHINE_IP "docker swarm join-token manager | grep -- --token;")
                ssh root@$CUR_MACHINE_IP "set -e; $JOIN_CMD"
                JOINED_SWARM=true
            fi

            # Pretty much we're the newest kid on the block with a different docker version
            if [ "$JOINED_SWARM" = "false" ] || [ ${length(var.lead_names)} -eq 1 ]; then
                echo "START NEW SWARM"
                # TODO: Check if we're already part of a (or our own) swarm
                ssh root@$CUR_MACHINE_IP 'docker swarm init --advertise-addr ${element(var.lead_public_ips, count.index)}:2377' || exit 0
            fi

            DOWN_MACHINES=$(ssh root@$CUR_MACHINE_IP "docker node ls | grep 'Down' | cut -d ' ' -f1;")
            # We might have to loop here if there are 2+ down machines, not sure what happens
            ssh root@$CUR_MACHINE_IP "docker node rm --force $DOWN_MACHINES || exit 0;"
            ssh root@$CUR_MACHINE_IP "docker node update --label-add dc=${var.region} --label-add name=${element(var.lead_names, count.index)} ${element(var.lead_names, count.index)}"

            exit 0
        EOF
    }
}

# TODO: Move web specific things into docker_swarm resource
# resource "null_resource" "docker_web" {
#     count = 0 #length(distinct(var.web_public_ips)
#     depends_on = [null_resource.docker_init]
#
#     # Join a docker swarm
#     provisioner "local-exec" {
#         # TODO: We dont use web instances yet, but we should ensure that web instances joining the leaders/cluster ALSO
#         #   share the same docker version so we dont introduce swarm/load balancing/proxy bugs, like in docker_leader resource
#         # SWARM_DOCKER_VER=$(docker-machine ssh ${element(var.names, 1)} "docker -v;")
#         # CUR_DOCKER_VER=$(docker-machine ssh ${element(var.names, count.index)} "docker -v;")
#
#         command = <<-EOF
#             JOIN_CMD=$(docker-machine ssh ${var.docker_leader_name} "docker swarm join-token worker | grep -- --token;");
#             docker-machine ssh ${element(var.names, count.index)} "set -e; $JOIN_CMD;"
#
#             OLD_ID=$(docker-machine ssh ${var.docker_leader_name} "docker node ls --filter name=${element(var.names, count.index)} | grep Down | cut -d ' ' -f1;")
#             docker-machine ssh ${var.docker_leader_name} "docker node rm --force $OLD_ID;"
#             docker-machine ssh ${var.docker_leader_name} "docker node update --label-add dc=${var.region} --label-add name=${element(var.names, count.index)} ${element(var.names, count.index)}"
#         EOF
#     }
# }
