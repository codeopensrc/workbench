#!/bin/bash

############
############
#### NOTE: HASNT BEEN REVIEWED IN SOME TIME. USED AT LEAST 2 MAJOR TERRAFORM UPDATES AGO
########
########

#### TODO: We should read in the value/terraform show for the specific env and inform the user if
#### 1) Only one leader up and to increase it to 2

#### TODO: Allow swapping of multiple leaders at once
#### At the momemnt (unless its easy) this will support only swapping/removing 1

###### Swapping leader
#### It's best to have 3 leaders up for consul election and swarm management
#### Swap 1 <-> 2   without a 3rd at your own risk (it does work)

while getopts "i:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        i) ID_TO_FIND=$OPTARG;;
    esac
done


if [ -z "$ID_TO_FIND" ]; then echo "Please provide an id using the -i flag   '-i FOUR_DIGIT_DOCKER_ID'"; exit 1; fi


### TODO: Have this support 3 and 4 (or more)dashs   ie.  name-dev-nyc1-lead-1234  AND  prod-nyc1-lead-1234
LIST_OF_NAMES=`/usr/local/bin/terraform show -module-depth=2 | grep "name = .*lead.*" | cut -d "-" -f4`
ID_FOUND_AT=-1

ARR_LEN=`/usr/local/bin/terraform show -module-depth=2 | grep module.do.digitalocean_droplet.lead | wc -l`
NEW_REPLACE_NUM=$(($ARR_LEN - 1))

INDEX=0
for i in $LIST_OF_NAMES; do
    if [ "$i" = "$ID_TO_FIND" ]; then
        ID_FOUND_AT="$INDEX"
        break
    fi
    ((++INDEX))
done

if [ "$ID_FOUND_AT" -eq -1 ]; then echo "ID not found"; exit 1; fi


terraform state mv module.do.digitalocean_droplet.lead[$ID_FOUND_AT] module.do.digitalocean_droplet.lead[$ARR_LEN]
terraform state mv module.do.digitalocean_droplet.lead[$NEW_REPLACE_NUM] module.do.digitalocean_droplet.lead[$ID_FOUND_AT]
terraform state mv module.do.digitalocean_droplet.lead[$ARR_LEN] module.do.digitalocean_droplet.lead[$NEW_REPLACE_NUM]

# terraform apply

#### At some point we need to taint/reset   consul_file  as well for non-leader/admins
#### when consul_lan_leader_ip can be a leader (no admin servers in that datacenter/az/whatever)
echo "Next lower the number of leader servers and 'terraform apply' to finish."
