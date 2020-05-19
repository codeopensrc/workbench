## NOTES
* Under active development
* Lot of unused code/old comments
* Requires currently non-public repo to run until firewall and misc configuration re-factored
* Even this README is a little old as it now uses old dns configuration

## NOTE: README out of date

## Personal use

Most of configurable functionality of terraform has been extracted down to the variables below and are in the `main.tf` file in order for very easy configuration and DRY code.

### Providers
- DO
```
token = #Your DO api token here
```


- AWS
```
alias = #Alias to use to associate to certain region
region = #AWS region
access_key = #Your aws key
secret_key = #Your aws secret_key
```

### Variables
Below are configurable variables

This needs to be unique per terraform machine per Digital Ocean/AWS acc/org   
`variable "server_name_prefix" { default = "" }`

These variables are the number of servers you wish to have up  
NOTE: \*\_db servers are \*\_mongo and \*\_pg combined.
```
#AWS
variable "aws_leader" { default = 0 }
variable "aws_db" { default = 0 }

variable "aws_web" { default = 0 }
variable "aws_dev" { default = 0 }
variable "aws_build" { default = 0 }
variable "aws_mongo" { default = 0 }
variable "aws_pg" { default = 0 }


#DO
variable "do_leader" { default = 1 }
variable "do_db" { default = 1 }

variable "do_web" { default = 2 }
variable "do_dev" { default = 0 }
variable "do_build" { default = 0 }
variable "do_mongo" { default = 0 }
variable "do_pg" { default = 0 }
```


### Module specific
There is an AWS and DO module. **If you aren't planning on using one, you must comment it out.**

##### SPECIAL VARS
###### AWS
```
variable "aws_key_name" { default = "" } // Ex: "id_rsa"
variable "aws_region" { default = "" } // Ex: "awseast"
```

###### DO
```
//You can find the ssh fingerprint in the security section of DO where you enter
//  your SSH key.
variable "do_ssh_fingerprint" { default = "" } // Your ssh fingerprint
variable "do_region" { default = "" } // Ex: "nyc1"
```
### Cloudflare / DNS

Cloudflare gives the ability to modify it's DNS settings via their API.  
This allows us to modify the DNS on cloudflare on new servers coming up/going down.

##### Cloudflare credentials
```
variable "cloudflare_email" { default = "YourEmail@Address.com" }
variable "cloudflare_auth_key" { default = "Cloudflare_auth_key" }
```

##### Cloudflare DNS

* Each root level domain has a `zone_id`  
* Each subdomain (including the root level) has a `dns_id`  

We define the DNS settings for our main `leader` instances using the `*_site_dns` list variable.  
We define the DNS settings for our `db` instances using the `*_db_dns` list variable.  

`zone_id` is found on the main page for each root level domain on cloudflare.  

`dns_id` is unique for each subdomain on cloudflare.

>To get the `dns_id` for each domain/subdomain:  
>- GET https://api.cloudflare.com/client/v4/zones/:zone_identifier/dns_records  
>
>EX:  
```
curl -X GET "https://api.cloudflare.com/client/v4/zones/${var.zone_id}/dns_records" \
-H "X-Auth-Email: ${var.cloudflare_email}" \
-H "X-Auth-Key: ${var.cloudflare_auth_key}" \
-H "Content-Type: application/json"
```
>    

Each variable is a `list` and is defined as such:

```
variable "*_site_dns" {
    type = "list"
    default = [
        {},
        {}
    ]
}
```

Each `{}` object inside the list is in the form of:
```
{
    "url" = "site domain"
    "dns_id" = "dns_id from cloudflare"
    "zone_id" = "zone_id from cloudflare"
}
```



### Misc
The instance types/sizes are fairly self explanatory.  

##### If you are combining AWS and DO  

You can have consul communicate across the data centers.
You should have a preference for which is the "main" data center and the other is more of a backup.

Uncomment only one of the following depending on which is your "main" data center:  
`do_leaderIP = "${module.do.do_ip}"` uncomment if you are using AWS  
`aws_leaderIP = "${module.aws.aws_ip}"` uncomment if you are using DO  
