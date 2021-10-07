* Pretty old - Probably still a work in progress - Just getting it commited

Random note - To purge a server from the cluster if all else fails (still possibly
breaking things but what can you do)

Remove the chef reference to it
    `knife node delete NODE_NAME`
    `knife client delete NODE_NAME`

If its a leader or web server (most likely), remove it from the swarm
    `docker swarm leave --force`

Run the appropriate "swap_X_.sh" file to move to the back of the terraform list

Remove the docker reference
    `docker-machine rm NODE_NAME`


Lower the server count in terraform
Or if terraform is in a bad state, delete it from the appropriate cloud provder




# This note refers to the resource "null_resource" "consul_install"
# If there are only 2 servers and one goes offline (or sufficient quoram is not met)
#  consul must be stopped `service consul stop` and the data-dir (our case /tmp/consul) needs to be deleted.
#  Then we can can start consul again using `service consul start` to repair the leader
#  election. To avoid this, use either 3 or 5 consul servers per data center. This
#  works well considering docker requires the same (we should make the admin a docker leader
#  and drain it so it cannot receive tasks)
### UPD: I'd like to keep admins from joining any swarm and being agnostic to their
###   docker engine versions. Without joining one swarm, we can facilitate more than one.






# I believe the only problem we'll have an need to think about is switching
#  the domain of the chef server once the chef server has been installed.
# I don't know how or what to change as far as certs if we choose to have say
#  chef.hwapps.tk become chef.dev.metrostudy.com  . We can change the knife.rb
#  in the terraform file easily, change the hostname on the server, but will that
#  communicate correctly once the url itself has changed.
# I believe this should be tested before implementing in a _real_ production env

# Probably edit
# /etc/chef/chef-server.rb
# and run
# chef-server-ctl reconfigure
# Yup - https://docs.chef.io/config_rb_server.html
# api_fqdn
# The FQDN for the Chef server. This setting is not in the server configuration
# file by default. When added, its value should be equal to the FQDN for the service
# URI used by the Chef server. For example: api_fqdn "chef.example.com".

# I think we run do _before_ we migrate from chef.hwapps.tk to chef.hwinternal.tk.
# Then run a 'chef-client' on all the chef nodes
# Change hostname on server
# Change chef_server_url in knife.rb and TF files

# The main idea being, unless we are doing a full teardown of the production env
# (unlikely except for major events like vendor migration), the admin server
# will not be destroyed, but should be able to be restarted without any *serious* hiccups
# in the infrastructure (a missed chef-client run is fine). All other servers should
# be completely disposable, and given enough time and thorough understanding and investment,
# we should have a front-end and back-end chef server in order to properly migrate
# admin servers, making them disposable as well (they are, but it would require _at least_
# a 30 minute window maintenance window, and thats not including the GB's of data the DB
# servers would have to download/upload/import).

# At this point these are just notes/thoughts I've been writing down - If we can mirror
# DB servers in some way, we can remove the maintenance window entirely as long as we change
# the DNS once all servers/services are back online. The underlying problem is data integrity,
# we can't have someone modify data on the old DB and NOT have those chanegs persisted over
# to the new DB. Thats a conversation with John K, John M, and Dave on how we could accomplish that

# Now that I think about it, I remember reading an article about a shop migrating
# their DB or infrastructure down the street and they had to mirror the DB in the above
# fashion, I believe theirs was a lot more involved, but something major like that I guess
# should be (I don't want it to be)

# Also a main goal (should be in readme) is to make sure the terraforming can happen
# on some remote instance everyone has access too, or figuring out how to share the
# tfstate file (version control might work?) so essentially anyone should be able to go
# in and bring up more servers if so desired (after proper chain of permission)
