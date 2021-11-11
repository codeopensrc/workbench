#!/bin/bash

######
### NOTE: This WILL overrwrite any file at the path given for the KEY_FILE argument
### Provide full consul key path for CONSUL_KEY_NAME and absolute file path for KEY_FILE
######

CONSUL_KEY_NAME="ssl/privkey"
CONSUL_CHAIN_NAME="ssl/fullchain"
DOMAIN=$(consul kv get domainname)

LETSENCRYPT_DIR=/etc/letsencrypt/live/$DOMAIN
KEY_FILE="$LETSENCRYPT_DIR/privkey.pem"
CHAIN_FILE="$LETSENCRYPT_DIR/fullchain.pem"

while getopts "f:k:s:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        f) KEY_FILE=$OPTARG;;
        k) CONSUL_KEY_NAME=$OPTARG;;
        s) SERVICE_NAME=$OPTARG;;
    esac
done

GET_KEY_CMD="/usr/local/bin/consul kv get $CONSUL_KEY_NAME"
GET_CHAIN_CMD="/usr/local/bin/consul kv get $CONSUL_CHAIN_NAME"

CONSUL_KEY=$($GET_KEY_CMD)
# Save result at getting the key, 0 successful 1 if not found
FOUND_CONSUL_KEY=$?

if [ $FOUND_CONSUL_KEY = "0" ]; then

    FILE_KEY=$(<$KEY_FILE)

    if [ "$CONSUL_KEY" != "$FILE_KEY" ]; then
        echo "Consul key at '$CONSUL_KEY_NAME' did not match key file at $KEY_FILE"
        $GET_KEY_CMD > $KEY_FILE
        $GET_CHAIN_CMD > $CHAIN_FILE
        echo "Updated certs on disk"
    fi

    sudo systemctl reload nginx || echo 0

else
    echo "Could not find consul key: $CONSUL_KEY_NAME"
fi
