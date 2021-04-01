#!/bin/bash
set -e

CONSUL_VERSION="1.0.6"
DOCKER_COMPOSE_VERSION="1.19.0"
GITLAB_VERSION="13.0.6-ce.0"

while getopts "c:d:g:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        c) CONSUL_VERSION=$OPTARG;;
        d) DOCKER_COMPOSE_VERSION=$OPTARG;;
        g) GITLAB_VERSION=$OPTARG;;
    esac
done


cat > /root/.gitconfig <<EOF
[credential]
    helper = store
EOF


# Dirs/TZ/packages
mkdir -p /root/repos
mkdir -p /root/builds
mkdir -p /root/code
mkdir -p /root/code/logs
mkdir -p /root/code/backups
mkdir -p /root/code/scripts
mkdir -p /root/code/csv
mkdir -p /root/code/jsons
mkdir -p /root/.ssh
mkdir -p /root/.tmux/plugins
mkdir -p /root/.aws
mkdir -p /etc/ssl/creds
mkdir -p /etc/nginx/conf.d
mkdir -p /etc/consul.d
sudo sed -i "s|\\\u@\\\h|\\\u@\\\H|g" /root/.bashrc
[ ! -f /root/.ssh/id_rsa ] && (cd /root/.ssh && ssh-keygen -f id_rsa -t rsa -N '')
[ ! -d /root/.tmux/plugins/tpm ] && git clone https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm
cp /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
timedatectl set-timezone 'America/Los_Angeles'

### Mirrors
#sed -i "s/# deb-src \(.*\) xenial main restricted/deb-src \1 xenial main restricted/" /etc/apt/sources.list
#sed -i "s/# deb-src \(.*\) xenial-updates main restricted/deb-src \1 xenial-updates main restricted/" /etc/apt/sources.list
#echo -e "deb http://mirrors.kernel.org/ubuntu `lsb_release -cs` main" | sudo tee -a /etc/apt/sources.list
#echo -e "deb-src http://mirrors.kernel.org/ubuntu `lsb_release -cs` main" | sudo tee -a /etc/apt/sources.list
#sleep 5;

sudo apt-get update
sudo apt-get upgrade -y
# Base/essentials
sudo apt-get install build-essential -y
sudo apt-get install apt-utils -y
# Misc
sudo apt-get install openjdk-8-jdk vim git awscli jq -y
# unzip for consul, rest for gitlab
sudo apt-get install unzip ca-certificates curl openssh-server -y


# docker-compose
curl -L https://github.com/docker/compose/releases/download/"$DOCKER_COMPOSE_VERSION"/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose


# aws
curl -O https://bootstrap.pypa.io/pip/3.4/get-pip.py
python3 get-pip.py
pip3 install awscli --upgrade


# mc (minio client)
curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc
###! An optional read policy (written as js object)
###! let readpolicy = {
###!     "Version": "2012-10-17",
###!     "Statement": [
###!         {
###!             "Action": [ "s3:ListBucket" ],
###!             "Principal": { "AWS": [ "*" ] },
###!             "Effect": "Allow",
###!             "Resource": [ `arn:aws:s3:::${AWS_BUCKET_NAME}` ],
###!             "Sid": ""
###!         },
###!         {
###!             "Action": [ "s3:GetObject", ],
###!             "Principal": { "AWS": [ "*" ] },
###!             "Effect": "Allow",
###!             "Resource": [ `arn:aws:s3:::${AWS_BUCKET_NAME}/*` ],
###!             "Sid": ""
###!         }
###!     ]
###! }


# consul
curl https://releases.hashicorp.com/consul/"$CONSUL_VERSION"/consul_"$CONSUL_VERSION"_linux_amd64.zip -o /tmp/consul.zip
unzip /tmp/consul.zip -d /tmp
rm -rf /tmp/consul.zip
mv /tmp/consul /usr/local/bin


# gitlab
echo postfix postfix/mailname string example.com | sudo debconf-set-selections
echo postfix postfix/main_mailer_type string 'Internet Site' | sudo debconf-set-selections
sudo apt-get install --assume-yes postfix;

###! WIP
###! sudo apt-get install --assume-yes mailutils;
###! change to:
###! mydestination = $myhostname, localhost.$mydomain, $mydomain
###! maybe   change:  inet_interfaces = all    to:  inet_interfaces = loopback-only
###! in /etc/postfix/main.cf

curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash;
sudo apt-get install gitlab-ce="$GITLAB_VERSION";

# Disable gitlab (enable for 1 instance only)
sudo gitlab-ctl stop
sudo systemctl disable gitlab-runsvdir.service || echo 0
