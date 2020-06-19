#!/bin/bash

# Not sure what this install method supports up to, but works for 5.0.9
REDIS_VERSION="5.0.9"
BIND_IP="0\.0\.0\.0"

while getopts "v:e" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        v) REDIS_VERSION=$OPTARG;;
        e) ENABLE=true;;
    esac
done


sudo apt-get update;
sudo apt-get install -y tcl8.5;
curl -L http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz > /tmp/redis-$REDIS_VERSION.tar.gz;
cd /tmp; mkdir -p /var/lib/redis; tar xzf redis-$REDIS_VERSION.tar.gz -C /var/lib/redis;
cd /var/lib/redis/redis-$REDIS_VERSION; make clean && make;
cd /var/lib/redis/redis-$REDIS_VERSION; make install;
sed -i "s/bind 127\.0\.0\.1/bind $BIND_IP/" /var/lib/redis/redis-$REDIS_VERSION/redis.conf;
sed -i "s/protected-mode yes/protected-mode no/" /var/lib/redis/redis-$REDIS_VERSION/redis.conf;
cd /var/lib/redis/redis-$REDIS_VERSION/utils;

# NOTE: The empty lines are important between ./install_server.sh <<-EOI  and   EOI
# It denotes an empty/default response to redis install questions
./install_server.sh <<-EOI

/var/lib/redis/redis.conf

/var/lib/redis


EOI

if [ "$ENABLE" = true ]; then
    sudo update-rc.d redis_6379 defaults;
    sudo service redis_6379 start;
else
    sudo service redis_6379 stop
    sudo systemctl disable redis_6379
fi
