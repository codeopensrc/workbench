#!/bin/bash

######
### NOTE: This WILL overrwrite any file at the path given for the KEY_FILE argument
### Provide full consul key path for CONSUL_KEY_NAME and absolute file path for KEY_FILE
######

CONSUL_KEY_NAME="ssl/privkey"
KEY_FILE="/etc/ssl/creds/privkey.pem"

while getopts "f:k:s:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        f) KEY_FILE=$OPTARG;;
        k) CONSUL_KEY_NAME=$OPTARG;;
        s) SERVICE_NAME=$OPTARG;;
    esac
done


GET_KV_CMD="/usr/local/bin/consul kv get $CONSUL_KEY_NAME"

CONSUL_KEY=$($GET_KV_CMD)
# Save result at getting the key, 0 successful 1 if not found
FOUND_CONSUL_KEY=$?


if [ $FOUND_CONSUL_KEY = "0" ]; then

    FILE_KEY=$(<$KEY_FILE)

    if [ "$CONSUL_KEY" != "$FILE_KEY" ]; then
        echo "Consul key at '$CONSUL_KEY_NAME' did not match key file at $KEY_FILE"

        $GET_KV_CMD > $KEY_FILE
        echo "Updated $KEY_FILE on disk"

        # Trigger restart on proxy service which will fetch the new ssl certs from consul
        ACTIVE_COLOR=$(/usr/local/bin/consul kv get apps/proxy/active)
        SERVICE_NAME=$(/usr/local/bin/consul kv get apps/proxy/$ACTIVE_COLOR);

        if [ -n $SERVICE_NAME ]; then
            echo "Restarting docker service to use new keys"
            docker service ps $SERVICE_NAME && docker service update $SERVICE_NAME --force;
        fi
    fi
else
    echo "Could not find consul key: $CONSUL_KEY_NAME"
fi
