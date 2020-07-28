########## CLOUDFLARE #######
#############################

##########################################################
##########################################################
### NOTHING BELOW NEEDS TO BE MODIFIED IF USING ROUTE53 #######
### Many below variables need to be refactored/deprecated
##########################################################
##########################################################

# Below cloudflare/dns variables _should_ be optional to modify DNS settings on cloudflare

# true/false - Apply changes to DNS servers
##### TODO: Remove / Deprecate
variable "change_db_dns" { default = true }   ## TODO: Untie this from cloudflare
variable "change_site_dns" { default = true }   ## TODO: Untie this from cloudflare
variable "change_admin_dns" { default = true }   ## TODO: Untie this from cloudflare

# Each object in the *_dns should be formatted as {"url": "domainname", "dns_id": "id", "zone_id": "id"}

# zone_id is found on the main page for each main domain on cloudflare
# To get dns id for each domain/subdomain:   GET https://api.cloudflare.com/client/v4/zones/:zone_identifier/dns_records
# EX:
# curl -X GET "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
# -H "X-Auth-Email: CLOUDFLARE_EMAIL" \
# -H "X-Auth-Key: CLOUDFLARE_AUTH_KEY" \
# -H "Content-Type: application/json" | jq '.result[] | {url: .name, dns_id:.id, zone_id: .zone_id}'

##### TODO: Remove / Deprecate
variable "aws_db_dns" {
    type = map(object({ url=string, dns_id=string, zone_id=string }))
    default = {
        pg = {
            "url"       = "pg.aws1.DOMAIN.COM"
            "dns_id"    = ""
            "zone_id"   = ""
        }
        mongo = {
            "url"       = "mongo.aws1.DOMAIN.COM"
            "dns_id"    = ""
            "zone_id"   = ""
        }
        redis = {
            "url"       = "redis.aws1.DOMAIN.COM"
            "dns_id"    = ""
            "zone_id"   = ""
        }
    }
}

##### TODO: Remove / Deprecate
variable "do_db_dns" {
    type = map(object({ url=string, dns_id=string, zone_id=string }))
    default = {
        pg = {
            "url"     = "pg.do1.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        }
        mongo = {
            "url"     = "mongo.do1.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        }
        redis = {
            "url"     = "redis.do1.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        }
    }
}

##### TODO: Remove / Deprecate
variable "site_dns" {
    type = list(object({ url=string, dns_id=string, zone_id=string }))
    default = [
        {
            "url"     = "DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        },
    ]
}

##### TODO: Remove / Deprecate
variable "admin_dns" {
    type = list(object({ url=string, dns_id=string, zone_id=string }))
    # We at least need the chef_server_url pointing to it
    default = [
        {
            "url"     = "chef.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        },
        {
            "url"     = "consul.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        },
        {
            "url"     = "cert.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        },
        {
            "url"     = "gitlab.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        },
        {
            "url"     = "registry.DOMAIN.COM"
            "dns_id"  = ""
            "zone_id" = ""
        }
    ]
}
