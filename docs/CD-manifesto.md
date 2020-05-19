* Pretty old - Probably still a work in progress - Just getting it commited

# Guidelines

Below are general guidelines to ensure we can continuously keep our applications,
our services(provisional software included), and our machines up to date. Yet completely
disposable, redeployable, fault tolerant, highly available, with quick (if any happen)
outage recovery.

### Production servers
Almost everything being run on a production server that is necessary to our applications
MUST be versioned in version control and NEVER edited real-time (unless ABSOLUTELY necessary,
like logging a bug found in production but hard/unable to produce in dev/staging)

### Stage servers
Stage must, in best effort, mirror production servers almost exactly. They should be cloned/
created/provisioned the exact same way as production servers in order to test how
our new development changes will interact/affect production servers/applications

### Development servers
These are unique per individual and should be built/setup to initially mirror the
production/staging servers, albeit on a much smaller scale


## Deployment (Ops)

#### Steps
* Consul
* Chef
* Docker
* App

#### Chef changes
As new apps come online and older apps get updated, we need to make changes to the
machines either via terraform or chef. To ensure we do not break any existing functionality
on the production servers/apps, we must not deprecate older versions of software or
omit any potential files that could be used for essential operations until we can be
certain that apps/services/software no longer rely on them. To accomplish this
we will use the folllowing steps:

##### Goal
_Do not disrupt any services when deploying new provisioning to production servers_

* Note all App/Service versions currently running and make sure the app definitions
    in terraform match.
* If we have a successful/smooth roll out of the new provisioning and updates to cookbooks,
    in the staging environment we can update the cookbooks on the production servers safely.
* Upload/Deploy those cookbooks to the production environment.
* Update the chef repo on the production chef server to mirror our current provisioning.
* Update the development environments (a good idea, not necessary though) to the
    new production/staging environment.


#### Docker-Engine
Before upgrading the machine/swarm to a new version of docker, we must make sure
all apps (at this time until we implement the better but in development implementation)
work on the new version of the Docker-Engine.
Now docker I'm sure does a wonderful job ensuring backwards compatibility, but they
DO deprecate features which other apps may possibly rely on, but cannot be updated
either to time constraints, or intention to deprecate. We can accomplish this by:

##### Goal
_Do not disrupt/break any services when deploying a new version of the Docker-Engine
to production servers_
_*Footnote*_ We need to (at least) implement an external load balancer in order to run more than
one swarm at a time. More things are probably necessary, but that is the first step
if we intend to support multiple swarms using say versions 17.06, or 17.08, or 18.02 etc.

###### Leader servers
* Note the App/Service version currently running and make sure the app definitions
    in terraform match.
* Change the `docker_engine_version` variable in `vars.tf` to the new version.
* Bring up the appropriate number of leader servers by adding (1-2 until further testing)
  servers and do NOT change the DNS by changing to `change_site_dns = false` in the `vars.tf` file
  BEFORE running `terraform apply`.
  - We start a new swarm as we don't want different docker-engine versions in the same swarm.
* Run `chef-client` on all nodes (in a semi-stable fashion, not swamping the chef server)
    to ensure all nodes can communicate via consul and leader -> DB connections.
* Restart/bring up all the services on the new swarm (due to lack of initial DB
    connections, some services most likely shutdown).
  - We should probably wait/not run the apps/containers immediately or make a toggle, to
    bring up services on the new swarm due to this limitation.

* NOTE: Test and implement the green/blue deployment strategy we're trying to use now
    in the `upgrading.md` file. TLDR Use the `beta.app.domain.com` to test and verify all
    services are in fact running.

* Switch the DNS to the new server and allow traffic into the new swarm.

###### Old Docker-Engine Cleanup
* Run the `replace_single_leader.sh` script using the 4 digit id of the old machine.
  - We can only do one at a time for the moment.
* Lower the machine count by 1 (at a time for now) and we're done.
* Repeat for as many machines we're decommissioning


##### Admin servers
See `Replace admin/chef server` below, the Docker-Engine shouldn't really matter.
Only in extreme cases it where breaks the most basic `docker-machine` commands would we worry.

##### DB servers
(TBD)







#### Apps


##### Goal
_Do not break any (dependent) services and do not disrupt the current/stable version
of the service, when deploying a new version of the application to production servers_






#### Replace admin/chef server
* IMPORTANT: Do not re-size the droplets this way just yet. We have to use a new size
    for new admin but keep the old size in the old droplet, or itll shut down when attempting
    to size up to the new admin's size as well. We need to implement a way to reference 2 different droplet
    sizes and apply the new size ONLY to the new server
    - As long as there are at least 3 servers for the consul cluster, we can shutdown
    the admin server, resize it, and bring it back online. This is actually a safer option
    for the moment using DO as there have been issues with new and old servers being able
    to ping each other causing really obnoxious issues (however customer facing services
    remain unaffected. +1)
* Add an Admin node with the SAME version of Chef/cookbooks as the production env
    - Until we setup a 2nd chef domain for swapping like this, we're going to temporarily
    lose the ability to query the chef server due to DNS needed on the new admin node,
    which is totally fine
* Run the `swap_admin.sh` script with the 'src' id and the 'dest' id. This will do a few things:
    - Bootstrap the leader(s) to the new chef/admin server
        - Also sets it's consul's config to retry_join the new server
    - Then bootstrap the DB to the new chef server.
        - Also sets it's consul's config to retry_join the new server
    - Leader -> DB order is important. This ensures the DB server always allows the leader
    through the DB firewall
    - Informs the old admin/chef server to leave the consul cluster
        (This may be bad and we should possibly wait until it's destroyed to do so)
    - Swaps the terraform index of the 2 admin servers so we can lower it later
    - Then changes the DNS of the admin servers to the OLD admin server (temporarily which is fine)
* Lower the admin server count back down (to 1 at this time)
    - This will cause the old admin to leave the consul cluster if it hasn't already
    - Changes the DNS back to the new admin server to continue operations as normal
* We need to re-add the app routes and the SSL keys (already copied over) by:
    - Tainting both "null_resource.add_proxy_hosts" and "null_resource.setup_letsencrypt"
        in `admin.tf`
    - Run `terraform apply`

** NOTE: At some point we have to have either the leader/db join the admin or vice versa


#### Replace leader server
* IMPORTANT: Do not re-size the droplets this way just yet. We have to use a new size
    for new leader but keep the old size in the old droplet, or itll shut down when attempting
    to size up to the new leader's size as well. We need to implement a way to reference 2 different droplet
    sizes and apply the new size ONLY to the new server
* Add a Leader node with the SAME docker-engine in `vars.tf` terraform
* Run `chef-client` on all machines for the firewalls
* Scale up/Re-balance services off the old machine making sure at least 1
    of every service is covered on another machine.
    - See below for scaling strategy.
* Set `change_site_dns = false` in `vars.tf`
* Run the `replace_single_leader.sh` script using the 4 digit id of the old machine
  - We can only do one at a time for the moment
* Change `change_site_dns = false` back to `true` in `vars.tf`
* Lower the number of servers by 1
* Repeat for as many machine that need to be replaced

** NOTE: We need to change the DNS BEFORE we destroy the droplet and WAIT a bit.
DNS does not immediately propagate and will continue to point to the old server for
a brief time after applying the DNS change.


###### 1 Leader running and swapping to another
* 1-2 tasks per service already running on main host
* Change number of leader servers from 1 to 2
* Scale tasks to 4 per service
    - This will place 2 on each host
* Scale tasks to 2 per service
    - Now 1 on each host
    - We do this because the containers from the old host will be placed onto
    the new host, bringing the total back down to 2 on the main host vs 4 (increase in cpu/mem)






## Development

#### Guidelines
* Mirror Production/Stage
    - Chef repo version/Cookbooks recipes
    - Docker-Engine
    - App versions
* Change 1 of the following at a time:
    - Chef cookbook(s)/recipe(s)
    - Docker-Engine version
    - Apps
* After a change, roll it out into the staging environment and make sure it is zero downtime.
* If the change does not affect other services (TBD how we properly "integrate"),
    and rolls out without any hiccups, roll out to production before making another change.

#### Chef changes
* We're going to mirror our development servers to production (or stage)
    - Note all App/Service versions currently running and make sure the app definitions
    in terraform match.
* Bring up the development servers with the same Docker-Engine version and Chef coookbooks
    - Run `knife cookbook list` on the production server to get all current cookbooks
    - If its a patch/minor version diff, should be safe to do the following and reconcile
        - `cd cookbook/$BOOK` `git diff <commit>..master .` to see the diff in cookbooks
    <!-- - If its a possibly larger change, provision with  -->

* Run all apps(exact versions) from production on our development servers and ensure they all work
* Test any new provisioning we're doing to ensure our "stable" apps work on development servers
    - a. Double check any provisioning we changed does not break existing applications
    - b. Ensure new provisioning does not interfere/break existing applications
* Check to see if any applications need some additional things provisioned and repeat _a._ and _b._ above
* Deploy/Roll out those changes to the staging environment
    - Roll out the updates as if we're deploying to live, not dropping any connections/requests
    repeating _a._ and _b._ above for the staging environment as it should be mirroring the production
     environment
* If we have a successful/smooth roll out of the new provisioning and updates to cookbooks,
    we can update the cookbooks on the production servers safely.
* Update dev environment to the current production/stable staging environment

** NOTE: Need to figure out and note when we should be committing changes to github
** We are going to start versioning the chef repo and hopefully finding a way to deploy
**   cookbooks individually of the "monolithic" chef repo.
** Also review how we use chef cookbooks, recipes, and roles


#### Docker-Engine upgrades



#### App development/deployment
