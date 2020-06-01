### WIP
### Things needed
Software on Linux workstation:  
terraform  
docker-machine  

Misc:  
AWS account  
domain (mysite.com)  
optional: Digital Ocean account if using Digital Ocean  

### Review  
* Duplicate template environment folder `envs/template_env` creating `envs/ENVIRONMENT`  
* Review and customize variables in `envs/ENVIRONMENT/vars.tf` and `envs/ENVIRONMENT/credentials.tf`  


#### TODO: Review below variables again
Below variable file was split and more variables have been added
```
#Key credentials
provider "digitalocean"
provider "aws"

`server_name_prefix`
`docker_registry_url`
`apps`
`chef_server_url`  -- chef.DOMAIN
`chef_email`
`cloudflare_email`
`cloudflare_auth_key`
`root_domain_name`

Apply DNS changes now - review when we don't
`change_db_dns`
`change_site_dns`
`change_admin_dns`

If using AWS
`aws_key_name`
`aws_region`
`aws_ami`
`aws_security_group_admin`
`aws_security_group_lead`
`aws_security_group_db`

These should only be enabled on the prod server
`db_backups_enabled`
`run_service_enabled`
`send_logs_enabled`
`send_jsons_enabled`
```






### Domain
* Get a new domain name from a domain registrar (or aws)
* Add the domain as a hosted zone in [__**aws_route53**__](https://console.aws.amazon.com/route53/home#hosted-zones:)  
    * 2 records automatically created, NS and SOA
    * Get the name servers here from the NS record  
    * Go to domain registrar's website and replace name servers to ones provided via the NS record


### Using aws route53 over cloudflare, below still informational
#### Cloudflare
<!-- route 53 -->
* Get a cloudflare account
* Add site for the new domain name from the previous step
    * TODO: Maybe more indepth instructions
* Get `zone_id` and `dns_id` from the main page of cloudflare for your domain
* Have your cloudflare email and authkey and change `cloudflare_email` `cloudflare_auth_key` in `envs/ENVIRONMENT/vars.tf`
* Supply your domain name to `root_domain_name` in `envs/ENVIRONMENT/credentials.tf`
* Add/register following entires to domain list on cloudflares site
    * Modify and run `scripts/registersubdomains.sh`
    * A      www     127.0.0.1     Proxied     -- Proxy on, off probably fine
* Get all `dns_id` records
    * Change `ZONE_ID`, `XAUTHEMAIL`, and `XAUTHKEY` and run:
        curl -X GET "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
        -H "X-Auth-Email: XAUTHEMAIL" \
        -H "X-Auth-Key: XAUTHKEY" \
        -H "Content-Type: application/json"
* Change all of the `zone_id` and `dns_id` for all of the following
    * `aws_db_dns`
    * `do_db_dns`
    * `aws_site_dns`
    * `do_site_dns`
    * `aws_admin_dns`
    * `do_admin_dns`



### AWS
* Get your `access_key` and `secret_key` from AWS (EC2 Dashboard Page - Top Menu > My Security Credentials)
    * `https://YOUR_AWS_NUM_OR_ORG.signin.aws.amazon.com/console`
    * Add this to the `envs/ENV/credntials.tf` file under the `aws` provider
* Add your `ssh_key` from AWS (EC2 Dashboard Page - Key Pairs)


>What would be good is making sure people have the appropriate docker-machine version
  as well. After that I believe it would be just OS and terraform version that could
  be different per workstation (none of this works on windows with all the local-execs)
>
Which brings up the point.. would like to be able to use docker containers for the scripts/
  provisioning done on the workstation so it CAN work on windows/osx with almost 0 config



### TODO/Note/Needs another review
When rebooting AWS changes the public ip

A) Assign static ip  
or  
B) Figure out things that rely on ip besides `consul`
    * `/etc/hosts`    so hostname resource possibly
