* Pretty old - Probably still a work in progress - Just getting it commited

## Upgrading and version control

The flow
* terraform bin/cli tool
* terraform envs
* terraform providers
* terraform provisioners

* docker-engine
* docker-compose

* chef server/chef dk
* chef cookbooks

* consul
* applications


## Checklist
- We have the right terraform version/tool that matches what is currently
managing the production infrastructure
    - At this time, workstation using Linux
- We're working in the correct `env` folder
- The providers have the correct credentials for that environment
- Review all the configurable variables in the `vars.tf` file
    - Ignore software versions the first overview

## Upgrading the stack
We have 6 different versioned pieces (that we can control in terraform) we need to
keep track of and make sure they match up appropriately

* docker-engine
* docker-compose

* chef server/chef dk
* chef cookbooks

* consul
* applications



##### Docker
We want to make sure we're using the correct docker engine version corresponding
to our applications and the active swarm itself.

We want to make sure we have the correct compose version in order to build the images
(once we use a dedicated build server) as older compose versions can't build images
that have features from later versions

##### Chef
We want to make sure we have a chef server/dk version that does all the things we
need in the chef cookbooks

We want to make sure the chef cookbooks provision our machines to the state that
all of our applications can run in

In order to have chef cookbooks correspond appropriately with our apps, we need
to start versioning the chef repo appropriately so we know when we move/change files
and remove/add some functionality that the apps previously required

##### Consul
We need to version consul to make sure we have the servers speaking the same
protocol and our apps that utilize consul are using the correct version when accessing it
(in the most recent case, going from raft protocol 2 to 3 by going from consul 0.8.5 -> 1.0.6)

##### Apps
Latestly we need to version our applications in 2 ways:
1 being the git repository
1 being the docker hub image

The resulting docker hub image version should correspond th the git repo version
ie.  For an app with a `git tag` version 0.5.0 -> 0.6.0, we should have a corresponding
docker image for both git version 0.5.0 and now we build 0.6.0 with the new "release"


## Order of operations

* All of the below steps are when we are migrating across machines that are not
close enough in compatibility and we need to have a brand new admin AND leader
at the same time (our current case since we werent doing this 6 months ago)

* If we incrementally test `dev` changes on `stage`, where `stage` should EXACTLY
mirror `prod`, we should IMMEDIATELY deploy stable changes from `stage` to `prod`
    - Keeps `prod` up to date with the latest deployments.
    - Keeps `stage` in tight unison with `prod`
    - Allows us to identify what we need to do in `dev` to ensure we can deploy
      to `prod`, as `stage` SHOULD mirror `prod`

### Consul
* Run `bash update_consul.sh` for a node at a time to ensure we dont lose quoram
    - If we have few consul nodes, it will probably be a 5-10 second outage querying
    things in consul as a new leader election needs to take place

* Run on admin last as we delete it's data dir (arguable if thats necessary anymore
    now that we dont have it ever rejoin)

### Docker/Chef
* We're gonna try adding an admin node, which changes the admin DNS and temporarily
leaves previously provisioned nodes un-updated for a short period
* Add a new leader but do NOT change the dns


Atm we dont use consul for routing on the old infra but we do the new one.

Meaning `app.domain.tk` is -> old leader.
We tell the consul on the old admin/leader to point (blue) `beta.app.domain.tk` -> new machine ip
The old admin/leader consul still has (green) `app.domain.tk` -> old services

On new machine(s) consul, we set the active to 'blue' (preset to point to `app_dev`
    until we start using 'blue' and 'green' with our services, we're gonna do use `*_main` and `*_dev`).
This causes (on the new machine(s)) to have (green) to point to `beta.app.domain.tk`
    which points to the ip/service at `app_main`. `app.domain.tk` (now blue) is now
    pointing to `app_dev` BUT our DNS is still pointing to the OLD leader
    (to not interrupt services), where 'green' is STILL pointing to `app_main`

Meaning we have
Old machine     (green) => Active services        Blue => New machine
                `app.domain.tk`                   `beta.app.domain.tk`

New machine     (green) => Active beta services   Blue => `app_dev`
                `beta.app.domain.tk`              `app.domain.tk`

We never route to the 'blue' services on the New machine as its being consumed on the Old machine
(where our DNS is currently pointing all traffic)

Test as much as we can that `beta.app.domain.tk` works the same as `app.domain.tk`

On new machine(s) consul, we stop testing/directing traffic to our `beta.*`, we swap
the active services to to 'green' causing the DNS resolution to change to

Old machine     (green) => Active services        Blue => New machine
                `app.domain.tk`                   `beta.app.domain.tk`

New machine     (green) => Active beta services  Blue => `app_dev`
                `app.domain.tk`                  `beta.app.domain.tk`

(Unless we have services on `app_dev` running, `beta.*` no longer works)

We then change the DNS at `app.domain.tk` to point to the New machine and traffic
starts routing from `app.domain.tk` to our new services


* See above for these 2 steps
* Make sure previous proxy has a route to the new machine ip using the `beta.*`
prefix per subdomain
* Config proxy on new machine to route `beta.*` requests to the soon-to-be production apps




* Update DB firewall to allow new leader server(s) to route to it

-- We're here in the thought process and unsure if we'll be able to find the DB
--   ip from the leader node inside our apps (as they use consul)
-- Our hope is we can "join" the DB node and find it and hope connecting the consul
--   clusters like this doesn't break anything, but I'm assuming it does
-- We could potentially update the compose files to use the "DEV_DB_URL" to directly
--   point to the database url until the DB server joins the consul cluster

* UPD It works but we also have to allow the admin server in, then configure the leader(s) and admin
    to also allow the DB in. Join the DB node and the DB services are discoverable in consul
    to the leader(s)
- This is where I want it automated so that nothing "should" go wrong as long as we
- Add NEW leader and NEW admin to OLD DB's firewall rules
- Add OLD DB to NEW leader and NEW admin firewall rules
* Firewall rules from chef WILL NOT update (see next step) these entries due to them being ADDED
for ip addresses we do not know about
* After everything is tested, being routed and working, when we re-provision the DB
  to the new chef server, chef WILL update the firewall rules for ALL nodes due to
  us having firewall rules that DO match the IP addresses
  - Meaning we don't have to clean up old firewall rule entries

* Literally all the above headaches with firewall rules go away if we get a dedicated
  subnet/vpn-like network between ALL nodes we control (regardless of vendor, datacenter, etc)


NOTE: Update apps to use ServiceAddress instead of Address when using consul for DB.
This way, maybe we can just add a temporary service to the new cluster that points to the DBs
to test for stability etc.


* Test to make sure everything does in fact work on the `beta.*` subdomain
* Change dns to the new node
    - In our new case (just tested) we just swap blue and green and should be g2g
* Provision the DB to the new chef server


* We can later swap the admin/db and shutdown those machines

* Docker
* Chef
* Apps
