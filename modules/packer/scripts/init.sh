#!/bin/bash
set -e

sed -i "s|1|0|" /etc/apt/apt.conf.d/20auto-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades

CONSUL_VERSION="1.10.0"
DOCKER_COMPOSE_VERSION="1.29.2"
GITLAB_VERSION="14.3.0-ce.0"
BUILDCTL_VERSION="0.10.5"

while getopts "b:c:d:g:a" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) IS_ADMIN=true;;
        b) BUILDCTL_VERSION=$OPTARG;;
        c) CONSUL_VERSION=$OPTARG;;
        d) DOCKER_COMPOSE_VERSION=$OPTARG;;
        g) GITLAB_VERSION=$OPTARG;;
    esac
done


cat > /root/.gitconfig <<EOF
[credential]
    helper = store
[alias]
    pretty = log --format='%C(auto)%h%d %cd - %s' --date=short
    mmwps = push -o merge_request.create -o merge_request.target=master -o merge_request.merge_when_pipeline_succeeds
    dmwps = push -o merge_request.create -o merge_request.target=dev -o merge_request.merge_when_pipeline_succeeds
EOF


#### Dirs/TZ/packages
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
cp /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
timedatectl set-timezone 'America/Los_Angeles'

### Mirrors
#sed -i "s/# deb-src \(.*\) xenial main restricted/deb-src \1 xenial main restricted/" /etc/apt/sources.list
#sed -i "s/# deb-src \(.*\) xenial-updates main restricted/deb-src \1 xenial-updates main restricted/" /etc/apt/sources.list
#echo -e "deb http://mirrors.kernel.org/ubuntu `lsb_release -cs` main" | sudo tee -a /etc/apt/sources.list
#echo -e "deb-src http://mirrors.kernel.org/ubuntu `lsb_release -cs` main" | sudo tee -a /etc/apt/sources.list
#sleep 5;

echo "update & install";
echo "Idk wait 30 seconds for apt-get update to avoid lock"
sleep 30;
sudo apt-get update;
echo "Idk wait 30 seconds again for apt-get upgrade to avoid lock"
sleep 30;
sudo apt-mark hold openssh-server;
echo "Marked ssh server"
sleep 15;
sudo apt-get upgrade -y;
echo "Idk wait 30 seconds again for apt-get install to avoid lock"
sleep 30;
sudo apt-get install \
    build-essential apt-utils net-tools openjdk-8-jdk \
    unzip apt-transport-https ca-certificates curl \
    vim git jq python3-distutils python3 \
    awscli silversearcher-ag -y

sudo apt-mark unhold openssh-server

#### docker-compose
curl -L https://github.com/docker/compose/releases/download/"$DOCKER_COMPOSE_VERSION"/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

### According to https://github.com/pypa/get-pip
### We should be able to `python3 get-pip.py "pip < 21.2.3"` in order to pin
### When using the edge /get-pip.py it temporarily caused issues
###   /get-pip.py installs 21.2.3      /pip/3.5/get-pip.py installs 20.3.4

#### pip
curl -O https://bootstrap.pypa.io/pip/3.5/get-pip.py \
 && python3 get-pip.py \
 && rm get-pip.py

#### aws
pip3 install awscli --upgrade


#### mc (minio client)
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


#### consul
curl https://releases.hashicorp.com/consul/"$CONSUL_VERSION"/consul_"$CONSUL_VERSION"_linux_amd64.zip -o /tmp/consul.zip \
 && unzip -o /tmp/consul.zip -d /usr/local/bin \
 && rm -rf /tmp/consul.zip


#### buildctl
curl -L https://github.com/moby/buildkit/releases/download/v${BUILDCTL_VERSION}/buildkit-v${BUILDCTL_VERSION}.linux-amd64.tar.gz -o /tmp/buildkit-linux.tar.gz \
 && mkdir -p /tmp/buildkit-linux && tar -xzvf /tmp/buildkit-linux.tar.gz -C /tmp/buildkit-linux \
 && mv /tmp/buildkit-linux/bin/buildctl /usr/local/bin \
 && rm -rf /tmp/buildkit-linux*


#### gitlab
if [[ -n $IS_ADMIN ]]; then
    curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash;
    sudo apt-get install gitlab-ce="$GITLAB_VERSION";

    # Disable gitlab (enable for 1 instance only)
    sudo gitlab-ctl stop
    
    ###! If in the future we start provisioning FROM admin
    ###! Also just to have simple documentation to install
    #sudo apt-add-repository ppa:ansible/ansible
    #sudo apt update
    #sudo apt install ansible
fi

sed -i "s|0|1|" /etc/apt/apt.conf.d/20auto-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
