#!/bin/bash

############
############
#### NOTE: HASNT BEEN REVIEWED IN SOME TIME. USED AT LEAST 2 MAJOR TERRAFORM UPDATES AGO
#### Also its labeled bad-old
########
########

###### Swapping admin
#### Ensure 2 leader servers active (for consul election)
#### Add new server from 1 to 2
#### apply

##### MAKE SURE SSL CERTS ARE ON THE NEW ADMIN SERVER BEFORE PROCEEDING
##### MAKE SURE SSL CERTS ARE ON THE NEW ADMIN SERVER BEFORE PROCEEDING

####### Taint leader bootstraps/Bootstrap leaders
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_leader_provisioners.null_resource.bootstrap | tr -d ':' | sed -e 's/module.do.do_leader_provisioners.//'`; do
    terraform taint -module=do.do_leader_provisioners $RESOURCE
done
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_leader_provisioners.null_resource.consul_file_leader | tr -d ':' | sed -e 's/module.do.do_leader_provisioners.//'`; do
    terraform taint -module=do.do_leader_provisioners $RESOURCE
done
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_leader_provisioners.null_resource.consul_service | tr -d ':' | sed -e 's/module.do.do_leader_provisioners.//'`; do
    terraform taint -module=do.do_leader_provisioners $RESOURCE
done

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
for RESOURCE in `/usr/local/bin/terraform show -module-depth=2 | grep module.do.do_db_provisioners.null_resource.consul_service | tr -d ':' | sed -e 's/module.do.do_db_provisioners.//'`; do
    terraform taint -module=do.do_db_provisioners $RESOURCE
done

### Have dbs join admin-1 with old consul cluster info into new consul cluster
### This is purely so we ensure the DB retries on the correct admin server in case of interuption
###   and health/service checks. These stay available to the leaders as neither really "left" the
###   the cluster (the challenge is swapping the admins in the consul cluster)
### What DOES happen though (I believe) is we can't issue any more services that discover DBs using
###   consul while the DB servers restart consul. Being able to apply a rolling update would be ideal,
###   but even better would be services still being able to find DBs on the WAN in another az/dc temporarily
###   that are being replicated etc. while this specific cluster is "under maintenence" (even if its 0-5 minutes)
terraform apply


#### We dont want to change admin DNS when we do this as we're already pointing to the correct IP address
####   when we increase it from 1 to 2 -- Solved by using the droplet name instead of id or ip
#### Move 0 to 2+
terraform state mv module.do.digitalocean_droplet.admin[0] module.do.digitalocean_droplet.admin[2]
#### Move 1 to 0
terraform state mv module.do.digitalocean_droplet.admin[1] module.do.digitalocean_droplet.admin[0]
#### Move old 0 from 2 to 1
terraform state mv module.do.digitalocean_droplet.admin[2] module.do.digitalocean_droplet.admin[1]

#### Force name swap on digital ocean
terraform apply

#### Now name swap in all the appropriate places to take rightful leader as number 0
terraform taint -module=do.do_admin_provisioners null_resource.docker_init.0
terraform apply
terraform taint -module=do null_resource.change_admin_hostname.0
terraform taint -module=do.do_admin_provisioners null_resource.consul_file_admin.0
terraform taint -module=do.do_admin_provisioners null_resource.consul_service.0
terraform apply
terraform taint -module=do null_resource.admin_bootstrap.0
terraform apply

###### Lower admin from 2 to 1
echo "Next lower admin servers from 2 to 1 and apply to finish."
