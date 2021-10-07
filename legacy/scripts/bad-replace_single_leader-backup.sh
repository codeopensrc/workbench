#!/bin/bash

############
############
#### NOTE: HASNT BEEN REVIEWED IN SOME TIME. USED AT LEAST 2 MAJOR TERRAFORM UPDATES AGO
#### Also its labeled bad-old
########
########

#### TODO: We should read in the value/terraform show for the specific env and inform the user if
#### 1) Only one leader up and to increase it to at least 2
#### 2) The value of admin is still 1 and needs to be set to 2

#### We also need to make a script to take the ssl certs from the old admin and place
####  them into the new one painlessly (we have the script, just need a good way to implement
####  it to be used autonomously/no user config)

#### TODO: Allow swapping of multiple leaders at once
#### At the momemnt (unless it its easy) this will support only swapping/removing
#### the leader at index 0


###### Swapping leader
#### Ensure at least 3 leader servers active (for consul election)



#### apply

###### TODO: Move 0 to End (empty), Loop moving N to N-1,  Move end to Last (one to remove)
#### Move 0 to 3+
terraform state mv module.do.digitalocean_droplet.lead[0] module.do.digitalocean_droplet.lead[4] #3 is empty
#### Move 1 to 0
terraform state mv module.do.digitalocean_droplet.lead[1] module.do.digitalocean_droplet.lead[0]
#### Move 2 to 1
terraform state mv module.do.digitalocean_droplet.lead[2] module.do.digitalocean_droplet.lead[1]
#### Move old 0 from 3 to 2
terraform state mv module.do.digitalocean_droplet.lead[3] module.do.digitalocean_droplet.lead[2]

terraform state mv module.do.digitalocean_droplet.lead[4] module.do.digitalocean_droplet.lead[3]

terraform apply

### This strategy is if we have/want 2 leaders active. We increased it to 3, put 0
### to the end of the line to an empty spot (3 in this example), move 1 to 0, 2 to 1,
### move the old 0 thats now at 3 to 2 and we destroy 2. So we dont need to worry
### re-provisioning index 2 since we plan to despose of it

#### If we were to be able to swap out a random node (which we should) we need to
#### be able to modify N and every resource after N


##### Need to drain the node/leader before re-provisioning so requests are routed
##### to the functioning swarm member


terraform taint -module=do.do_leader_provisioners null_resource.docker_init.0
##### We dont want chef applying a wrong hostname so apply immedietely
terraform taint -module=do null_resource.change_leader_hostname.0
terraform taint -module=do.do_leader_provisioners null_resource.docker_leader.0
terraform apply

##### We need to make sure it has rejoined the swarm, launched services, and found/connected to
##### consul DBs before messing with the consul state, as services are not be able to connect to DB's
##### until we remove the original consul member (due to name's clashing)

#### New problem is how to enforce a rebalance across our containers for 0 downtime
#### Right now all the containers are running on the 2nd host and none on the 1st
#### If we leave/join etc, theres a small period of no containers up
####  We might need 3 active leaders in order to swap appropriately

sleep 30
terraform taint -module=do.do_leader_provisioners null_resource.consul_file_leader.0
terraform taint -module=do.do_leader_provisioners null_resource.consul_service.0
terraform apply
terraform taint -module=do.do_leader_provisioners null_resource.bootstrap.0
terraform apply
#
# ##### Cautionary waiting period to ensure swarm/consul/chef etc have updated
# ##### I want to test with this, then without, I don't like possible race conditions
# sleep 30
#
#
# ##### Now apply to index 1 now that index 0 is part of the swarm and can be routed to
# terraform taint -module=do.do_leader_provisioners null_resource.docker_init.1
# ##### We dont want chef applying a wrong hostname so apply immedietely
# terraform taint -module=do null_resource.change_leader_hostname.1
# terraform taint -module=do.do_leader_provisioners null_resource.docker_leader.1
# terraform apply
#
# ##### We need to make sure it has rejoined the swarm, launched services, and found/connected to
# ##### consul DBs before messing with the consul state, as services are not be able to connect to DB's
# ##### until we remove the original consul member (due to name's clashing)
# sleep 30
# terraform taint -module=do.do_leader_provisioners null_resource.consul_file_leader.1
# terraform taint -module=do.do_leader_provisioners null_resource.consul_service.1
# terraform apply
# terraform taint -module=do.do_leader_provisioners null_resource.bootstrap.1
# terraform apply
#
#
#
# ##### Cautionary waiting period to ensure swarm/consul/chef etc have updated
# ##### I want to test with this, then without, I don't like possible race conditions
# sleep 30
#
#
# ##### Now apply to index 1 now that index 0 is part of the swarm and can be routed to
# terraform taint -module=do.do_leader_provisioners null_resource.docker_init.1
# ##### We dont want chef applying a wrong hostname so apply immedietely
# terraform taint -module=do null_resource.change_leader_hostname.1
# terraform taint -module=do.do_leader_provisioners null_resource.docker_leader.1
# terraform apply
#
# ##### We need to make sure it has rejoined the swarm, launched services, and found/connected to
# ##### consul DBs before messing with the consul state, as services are not be able to connect to DB's
# ##### until we remove the original consul member (due to name's clashing)
# sleep 30
# terraform taint -module=do.do_leader_provisioners null_resource.consul_file_leader.1
# terraform taint -module=do.do_leader_provisioners null_resource.consul_service.1
# terraform apply
# terraform taint -module=do.do_leader_provisioners null_resource.bootstrap.1
# terraform apply



#### At some point we need to taint/reset   consul_file  as well for non-leader/admins
#### when consul_lan_leader_ip can be a leader (no admin servers in that datacenter/az/whatever)


###### Lower leader from 3 to 2
echo "Next lower leader servers from 4 to 2/1 and apply to finish."








#
# terraform untaint -module=do.do_leader_provisioners null_resource.docker_init.0
# terraform untaint -module=do.do_leader_provisioners null_resource.docker_init.1
#
# terraform apply
# terraform untaint -module=do null_resource.change_leader_hostname.0
# terraform untaint -module=do null_resource.change_leader_hostname.1
# terraform untaint -module=do.do_leader_provisioners null_resource.consul_file_leader.0
# terraform untaint -module=do.do_leader_provisioners null_resource.consul_file_leader.1
# terraform untaint -module=do.do_leader_provisioners null_resource.consul_service.0
# terraform untaint -module=do.do_leader_provisioners null_resource.consul_service.1
# exit;
# terraform apply
# terraform taint -module=do.do_leader_provisioners null_resource.bootstrap.0
# terraform taint -module=do.do_leader_provisioners null_resource.bootstrap.1
# exit;
# terraform apply
