
############
############
#### NOTE: We use aws_route53 over cloudflare now. Still useful for cloudflare though
########
########

# curl -X GET "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
# -H "X-Auth-Email: EMAIL" \
# -H "X-Auth-Key: AUTH_KEY" \
# -H "Content-Type: application/json"

# TODO: Tie to terraform
# TODO: Have this first check if we have the available domains already registered
# TODO: Have it be re-runnable


# TODO: Supply credentials via secure method
################################################
######## Credentials should NOT be committed
######## Only VERY specific credentials should be committed as a well-reviewed last resort
######## TODO: Place this warning wherever credentials potentially committed
################################################

ZONE_ID = ""
cloudflare_email=""
cloudflare_auth_key=""

ROOT_DOMAIN_NAME=""

A_RECORDS=()

CNAME_RECORDS=()


################################################
######## Nothing below this needs to be edited
################################################

# TODO: Get all DNS records and filter out from CNAME_RECORDS and A_RECORDS if we
#   already have it registered


# Replace ZONE_ID, cloudflare_email, and cloudflare_auth_key to get all dns for a zone/domain
# curl -X GET "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
# -H "X-Auth-Email: cloudflare_email" \
# -H "X-Auth-Key: cloudflare_auth_key" \
# -H "Content-Type: application/json"



for A_RECORD in ${A_RECORDS[@]}; do
    curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
         -H "X-Auth-Email: ${cloudflare_email}" \
         -H "X-Auth-Key: ${cloudflare_auth_key}" \
         -H "Content-Type: application/json" \
         --data '{"type":"A","name":"'${A_RECORD}'","content":"127.0.0.1","ttl":1,"priority":10,"proxied":false}'
done


for CNAME_RECORD in ${CNAME_RECORDS[@]}; do
    curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
         -H "X-Auth-Email: ${cloudflare_email}" \
         -H "X-Auth-Key: ${cloudflare_auth_key}" \
         -H "Content-Type: application/json" \
         --data '{"type":"CNAME","name":"'${CNAME_RECORD}'","content":"'${ROOT_DOMAIN_NAME}'","ttl":1,"priority":10,"proxied":false}'
done
