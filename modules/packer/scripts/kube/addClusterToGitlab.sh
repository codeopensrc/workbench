#!/bin/bash

CLUSTER_NAME_DEFAULTS=( "review" "dev" "beta" "production" )

## For conveniece and so it is not required to keep a PAT available, we create a temp
##  PAT and revoke it at the bottom
TOKEN_UUID=`uuidgen`
sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TOKEN_UUID'); token.save!";

while getopts "d:n:s:ruc" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DOMAIN=$OPTARG;;
        n) CLUSTER_NAME=$OPTARG;;
        s) CLUSTER_SCOPE=$OPTARG;;
        c) CREATE_CLUSTER_ACCOUNTS="true";;
        u) USE_DEFAULTS="true";;
        r) RM_PREV_CLUSTERS="true";;
    esac
done

if [[ -z "$DOMAIN" ]]; then echo "Domain not provided. Use -d"; exit; fi

GL_API_URL="https://gitlab.${DOMAIN}/api/v4"

## NOTE: For importing prev gitlab
##  Loop through deleting
if [[ $RM_PREV_CLUSTERS = "true" ]]; then

    DELETE_IDS=( $(curl -H "PRIVATE-TOKEN: ${TOKEN_UUID}" "${GL_API_URL}/admin/clusters" | jq ".[] | .id") )
    
    for ID in "${DELETE_IDS[@]}"; do
        echo "Removing cluster $ID"
        curl -X DELETE -H "PRIVATE-TOKEN: ${TOKEN_UUID}" "$GL_API_URL/admin/clusters/$ID";
        echo "Removed"
        sleep 5;
    done
fi


if [[ -z "$USE_DEFAULTS" ]]; then
    if [[ -z "$CLUSTER_NAME" ]]; then echo "Cluster name not provided. Use -n"; exit; fi
    CLUSTER_NAMES=($CLUSTER_NAME)
else
    CLUSTER_NAMES=${CLUSTER_NAME_DEFAULTS[@]}
fi


## NOTE: Make sure this IP is allowed to make local requests (we handle it by default now)
## Admin > AppSettings > Network > Outbound requests
#### NOTE: url produced from below command contains color output characters that we remove
CLUSTER_API_ADDR=$(kubectl cluster-info | grep -E 'Kubernetes master|Kubernetes control plane' | sed -r "s|.*(http[s:/.[:alnum:]]*).*|\1|")

SECRET=$(kubectl get secrets | grep default-token | cut -d " " -f1)
CERT=$(kubectl get secret ${SECRET} -o jsonpath="{['data']['ca\.crt']}" | base64 --decode)

## Gitlab accepts \r\n for newlines in cert pem
FORMATTED_CERT=${CERT//$'\n'/'\r\n'}

## NOTE: This requires the gitlab service account in kubernetes before running
SERVICE_TOKEN_1=$(kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep gitlab | awk '{print $1}'))
SERVICE_TOKEN=$(echo "$SERVICE_TOKEN_1" | sed -nr "s/token:\s+(.*)/\1/p")


for CLUSTER_NAME in ${CLUSTER_NAMES[@]}; do
    echo "Running for $CLUSTER_NAME"

    MANAGED="false"

    CLUSTER_BASE_DOMAIN="${CLUSTER_NAME}.${DOMAIN}"  #Just using this until we cant
    if [[ $CLUSTER_NAME = "production" ]]; then CLUSTER_BASE_DOMAIN=${DOMAIN}; fi
    if [[ $CLUSTER_NAME = "review" ]]; then CLUSTER_BASE_DOMAIN="dev.${DOMAIN}"; MANAGED="true"; CLUSTER_SCOPE='*'; fi
    if [[ -z "$CLUSTER_SCOPE" ]]; then CLUSTER_SCOPE=${CLUSTER_NAME}; fi

CLUSTER_DATA='{
    "name": "'${CLUSTER_NAME}'",
    "environment_scope": "'${CLUSTER_SCOPE}'",
    "domain": "'${CLUSTER_BASE_DOMAIN}'",
    "managed": "'${MANAGED}'",
    "platform_kubernetes_attributes": {
        "api_url": "'${CLUSTER_API_ADDR}'",
        "token": "'${SERVICE_TOKEN}'",
        "ca_cert": "'${FORMATTED_CERT}'"
    }
}'

    curl -H "PRIVATE-TOKEN: ${TOKEN_UUID}" -H "Content-Type: application/json" --data "${CLUSTER_DATA}" "$GL_API_URL/admin/clusters/add"
 
    unset CLUSTER_SCOPE;
    sleep 3;
done

sudo gitlab-rails runner "PersonalAccessToken.find_by_token('$TOKEN_UUID').revoke!";

consul kv put kube/gitlab_integrated true

if [[ -n $CREATE_CLUSTER_ACCOUNTS ]]; then
    bash $HOME/code/scripts/kube/createClusterAccounts.sh -a $CLUSTER_API_ADDR -u
fi
