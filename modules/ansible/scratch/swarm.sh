
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
