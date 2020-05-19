#!/bin/bash

############
############
#### NOTE: HASNT BEEN REVIEWED IN SOME TIME. USED AT LEAST 2 MAJOR TERRAFORM UPDATES AGO
#### Also advise not attempting to "swap" the admin at this time, at least using this.
#### Several things were added that forces us to backup and restore a few more items.
#### Backing up and restoring the cluster is a better option for now
########
########

# TODO: We should read in the value/terraform show for the specific env and inform the user if
# 1) Only one leader up and to increase it to at least 2
# 2) The value of admin is still 1 and needs to be set to 2


#### * 1 leader req, 2 leaders reccommended
#### * Change Admin from 1 -> 2 in vars.tf
#### * `terraform apply`   NOTE: chef.DOMAIN dns goes down temporarily after running this
#### * `bash swap_admin.sh -s FOUR_DIGIT_DOCKER_ID -d FOUR_DIGIT_DOCKER_ID`
####          -s is the src (original)    -d is the destination (new one)
#### * Change Admin from 2 -> 1 in vars.tf
#### * Run `chef-client` on all nodes however you wish. ex `knife ssh "role:*" "chef-client"`


## TODO: Bootstrap/modify one node at a time vs ALL nodes at once

DO_NOT_COPY_SSL="false"

while getopts "ns:d:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        s) SRC_ID_TO_FIND=$OPTARG;;
        d) DEST_ID_TO_FIND=$OPTARG;;
        n) DO_NOT_COPY_SSL=true;;
    esac
done


if [ -z "$SRC_ID_TO_FIND" ]; then echo "Please provide src id using the -s flag   '-s FOUR_DIGIT_DOCKER_ID'"; exit 1; fi
if [ -z "$DEST_ID_TO_FIND" ] && [ "$DO_NOT_COPY_SSL" = "false" ]; then
    echo "If you wish to copy the ssl certificates from the src machine,
    please provide destination id using the -d flag   '-d FOUR_DIGIT_DOCKER_ID'";
    echo "Otherwise provide the -n option with no arguments."
    exit 1;
fi


SRC_DOCKER_NAME=$(docker-machine ls -t 3 --filter name=$SRC_ID_TO_FIND -q)
# [ DO_NOT_COPY_SSL = "false" ] &&
DEST_DOCKER_NAME=$(docker-machine ls -t 3 --filter name=$DEST_ID_TO_FIND -q)
# ARR_LEN=`/usr/local/bin/terraform show -module-depth=2 | grep module.do.digitalocean_droplet.lead | wc -l`

if [ -z "$SRC_DOCKER_NAME" ]; then echo "Docker machine with id $SRC_ID_TO_FIND not found."; exit; fi
if [ -z "$DEST_DOCKER_NAME" ] && [ "$DO_NOT_COPY_SSL" = "false" ]; then
    echo "Docker machine with id $DEST_ID_TO_FIND not found.";
    exit;
fi


### TODO: Have this support 3 and 4 (or more)dashs   ie.  NAME-dev-nyc1-admin-1234  AND  prod-nyc1-admin-1234
LIST_OF_NAMES=`/usr/local/bin/terraform show -module-depth=2 | grep "name = .*admin.*" | cut -d "-" -f5`

ARR_LEN=`/usr/local/bin/terraform show -module-depth=2 | grep module.do.digitalocean_droplet.admin | wc -l`
NEW_REPLACE_NUM=$(($ARR_LEN - 1))

SRC_ID_FOUND_AT=-1
INDEX=0
for i in $LIST_OF_NAMES; do
    if [ "$i" = "$SRC_ID_TO_FIND" ]; then
        SRC_ID_FOUND_AT="$INDEX"
    fi
    ((++INDEX))
done

if [ "$SRC_ID_FOUND_AT" -eq -1 ]; then echo "Src ID not found in terraform state"; exit 1; fi




if [ "$DO_NOT_COPY_SSL" = "false" ]; then
    docker-machine scp -r $SRC_DOCKER_NAME:/etc/letsencrypt $DEST_DOCKER_NAME:/etc/letsencrypt
fi



####### Taint leader bootstraps/Bootstrap leaders
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_leader_provisioners.null_resource.bootstrap | tr -d ':' | sed -e 's/module.do.do_leader_provisioners.//'`; do
    terraform taint -module=do.do_leader_provisioners $RESOURCE
done
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_leader_provisioners.null_resource.consul_file_leader | tr -d ':' | sed -e 's/module.do.do_leader_provisioners.//'`; do
    terraform taint -module=do.do_leader_provisioners $RESOURCE
done
# for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_leader_provisioners.null_resource.consul_service | tr -d ':' | sed -e 's/module.do.do_leader_provisioners.//'`; do
#     terraform taint -module=do.do_leader_provisioners $RESOURCE
# done

#### Have leaders join admin-1 with old consul cluster info into new consul cluster
#### This allows leaders to stay in sync with the database to not knock off/interupt existing services
####   and also allow us to continually add services to the new consul cluster
terraform apply


###### Taint DB bootraps/Bootstrap DBS
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_db_provisioners.null_resource.bootstrap | tr -d ':' | sed -e 's/module.do.do_db_provisioners.//'`; do
    terraform taint -module=do.do_db_provisioners $RESOURCE
done
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_db_provisioners.null_resource.consul_file | tr -d ':' | sed -e 's/module.do.do_db_provisioners.//'`; do
    terraform taint -module=do.do_db_provisioners $RESOURCE
done
# for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_db_provisioners.null_resource.consul_service | tr -d ':' | sed -e 's/module.do.do_db_provisioners.//'`; do
#     terraform taint -module=do.do_db_provisioners $RESOURCE
# done

### Have dbs join admin-1 with old consul cluster info into new consul cluster
### This is purely so we ensure the DB retries on the correct admin server in case of interuption
###   and health/service checks. These stay available to the leaders as neither really "left" the
###   the cluster (the challenge is swapping the admins in the consul cluster)
### What DOES happen though (I believe) is we can't issue any more services that discover DBs using
###   consul while the DB servers restart consul. Being able to apply a rolling update would be ideal,
###   but even better would be services still being able to find DBs on the WAN in another az/dc temporarily
###   that are being replicated etc. while this specific cluster is "under maintenence" (even if its 0-5 minutes)
terraform apply


### TODO: When should we really do this?
### Leave to force an election between the new nodes
docker-machine ssh $SRC_DOCKER_NAME "systemctl stop consul.service"


# # #### We dont want to change admin DNS when we do this as we're already pointing to the correct IP address
# # ####   when we increase it from 1 to 2 -- Solved by using the droplet name instead of id or ip
# # #### Move 0 to 2+
# terraform state mv module.do.digitalocean_droplet.admin[0] module.do.digitalocean_droplet.admin[2]
# # #### Move 1 to 0
# terraform state mv module.do.digitalocean_droplet.admin[1] module.do.digitalocean_droplet.admin[0]
# # #### Move old 0 from 2 to 1
# terraform state mv module.do.digitalocean_droplet.admin[2] module.do.digitalocean_droplet.admin[1]
# #
# # #### Force name swap on digital ocean
# terraform apply

terraform state mv module.do.digitalocean_droplet.admin[$SRC_ID_FOUND_AT] module.do.digitalocean_droplet.admin[$ARR_LEN]
#### Move 1 to 0
terraform state mv module.do.digitalocean_droplet.admin[$NEW_REPLACE_NUM] module.do.digitalocean_droplet.admin[$SRC_ID_FOUND_AT]
terraform state mv module.do.digitalocean_droplet.admin[$ARR_LEN] module.do.digitalocean_droplet.admin[$NEW_REPLACE_NUM]



echo "### WARNING ###"
echo "Be sure to run \`terraform plan\` before running \`terraform apply\`"
echo "### WARNING ###"

echo "* Run terraform apply to swap the admin indexes in terraform"
echo "* Then lower the admin server count from 2 -> 1 and run terraform apply again to finish"

# Until we come up with a way to guard against differing sizes between droplets when
# adding an admin server, intentional or otherwise, we shouldn't auto-apply terraform apply
exit;

############ NOTE ############
############ NOTE ############
# OUR ADMIN DNS IS NOW POINTING TO THE OLD SERVER AFTER THIS APPLY
terraform apply
# WE NEED TO EITHER
# A) Lower admin from 2 to 1 and it will change back
# B) Insert script here to change it back
# C) Manually change it

# Go for A) its a temp 30 sec-1min outage for non-customer facing things
# that accomplishes what we want







#### Now name swap in all the appropriate places to take rightful leader as number 0
# terraform taint -module=do.do_admin_provisioners null_resource.docker_init.0
# terraform apply
# terraform taint -module=do null_resource.change_admin_hostname.0
# terraform taint -module=do.do_admin_provisioners null_resource.consul_file_admin.0
# terraform taint -module=do.do_admin_provisioners null_resource.consul_service.0
# terraform apply
# terraform taint -module=do null_resource.admin_bootstrap.0

###### Lower admin from 2 to 1
echo "Next lower admin servers from 2 to 1 and apply to finish."
