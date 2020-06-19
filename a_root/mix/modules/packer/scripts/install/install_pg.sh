#!/bin/bash

# TODO: Prep to upgrade postgres incrementally to latest version
# Support 18.04+ bionic

PG_VERSION="9.5"
BIND_IP="0.0.0.0/0"

while getopts "v:u:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        v) PG_VERSION=$OPTARG;;
        u) DB_USER=$OPTARG;;
    esac
done

PG_APT=$(grep xenial-pgdg < /etc/apt/sources.list.d/pgdg.list)

if [[ -z $PG_APT ]]; then
    echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list
fi

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

sudo apt-get update

sudo apt-get install -y postgresql-$PG_VERSION
# postgresql-contrib

# Listen on all network interfaces
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/$PG_VERSION/main/postgresql.conf

# Change postgres 'peer' to 'trust' in pg_hba.conf for local postgres user connection
sudo sed -i 's/postgres\([[:space:]]\{5,\}\)peer/postgres\1trust/' /etc/postgresql/$PG_VERSION/main/pg_hba.conf

# Allow remote connections to connect on $BIND_IP with password and if firewall/security group allows ip
ALREADY_ALLOWED=$(sudo cat /etc/postgresql/$PG_VERSION/main/pg_hba.conf | grep $BIND_IP)
if [[ -z $ALREADY_ALLOWED ]]; then
    echo "host    all             all             $BIND_IP            md5" | sudo tee -a /etc/postgresql/$PG_VERSION/main/pg_hba.conf
fi

sudo service postgresql restart

POSTGRES_USER=postgres
if [[ $DB_USER != "" ]]; then POSTGRES_USER=$DB_USER; fi

# TODO: Architecture built for a single pg database at this time. Needs to be more general use for multiple dbs
PG_PASSWORD=$(/usr/local/bin/consul kv get PG_PASSWORD)
/usr/bin/psql -U $POSTGRES_USER -c 'ALTER USER '${POSTGRES_USER}' WITH ENCRYPTED PASSWORD '\'${PG_PASSWORD}\'';'

# TODO: See if this is necessary or if the problem was parent terraform script
exit 0;

# On recently booted up server: postgresql.conf
# data_directory = '/var/lib/postgresql/9.5/main'
# datestyle = 'iso, mdy'
# default_text_search_config = 'pg_catalog.english'
# external_pid_file = '/var/run/postgresql/9.5-main.pid'
# hba_file = '/etc/postgresql/9.5/main/pg_hba.conf'
# ident_file = '/etc/postgresql/9.5/main/pg_ident.conf'
# listen_addresses = '*'
# log_line_prefix = '%t '
# max_connections = 100
# port = 5432
# shared_buffers = '24MB'
# ssl = on
# ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
# ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
# unix_socket_directories = '/var/run/postgresql'

# On recently booted up server: pg_hba.conf
# host    all             all             0.0.0.0/0               md5
# local   all             all                                     trust
# host    all             all             127.0.0.1/32            md5
# host    all             all             ::1/128                 md5
# # "local" is for Unix domain socket connections only
# local   all             all                                     peer
