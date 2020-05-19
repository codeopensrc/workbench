#!/bin/bash

# Lazy rebooting, copy paste/run on server

PROXY_UP=$(docker service ps proxy_main);
MONITOR_UP=$(docker service ps monitor_main);

[ "$PROXY_UP" ] && docker service update proxy_main -d --force
[ "$MONITOR_UP" ] && docker service update monitor_main -d --force
