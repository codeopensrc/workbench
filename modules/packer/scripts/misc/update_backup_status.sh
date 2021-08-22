#!/bin/bash

TODAY=$(date +"%F")
TIME_NOW=$(date +"%a %b %d %H:%M %Z");
CONSUL_HOST="http://localhost:8500"

while getopts "c:e:h:s:t:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        c) CHECK_ID=$OPTARG;;
        e) EXIT_CODE=$OPTARG;;
        h) CONSUL_HOST=$OPTARG;;
        s) SERVICE_ID=$OPTARG;;
        t) TTL=$OPTARG;;
    esac
done

CONSUL_URL="${CONSUL_HOST}/v1/agent"

CONSUL_HELP_URL="https://www.consul.io/docs/discovery/checks"

if [ -z "$CHECK_ID" ]; then echo "Missing CHECK_ID. Provide check id with -c"; exit; fi
if [ -z "$EXIT_CODE" ]; then echo "Missing EXIT_CODE. Provide exit code with -e"; exit; fi
if [ -z "$SERVICE_ID" ]; then echo "Missing SERVICE_ID. Provide service id with -s"; exit; fi
if [ -z "$TTL" ]; then echo -e "Missing TTL. Provide TTL with -t (See \e[1m\e[4m$CONSUL_HELP_URL\e[0m for TTL checks/formatting)"; exit; fi

CHECK='{
    "id": "'${CHECK_ID}'",
    "name": "'${TIME_NOW}'",
    "notes": "On successful backup, check is replaced",
    "service_id": "'${SERVICE_ID}'",
    "ttl": "'${TTL}'"
}
'
SERVICE='{
    "name": "'${SERVICE_ID}'",
    "tags": ["_type=backup"],
    "address": "",
    "enable_tag_override": false
}'



## Register service
curl -X PUT --data "${SERVICE}" ${CONSUL_URL}/service/register

if [[ $EXIT_CODE == 0 ]]; then
    echo "Check updated"
    ## Register check
    curl -X PUT --data "${CHECK}" ${CONSUL_URL}/check/register
    ## Update TTL check
    curl -X PUT ${CONSUL_URL}/check/pass/${CHECK_ID}
fi
## Deregister service
#curl -X PUT ${CONSUL_URL}/service/deregister/${SERVICE_ID}
## Deregister check
#curl -X PUT ${CONSUL_URL}/check/deregister/${CHECK_ID}
