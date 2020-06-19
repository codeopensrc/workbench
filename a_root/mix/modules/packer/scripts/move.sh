#!/bin/bash

mv /tmp/scripts/* /root/code/scripts
mv /root/code/scripts/misc/tmux.conf /root/.tmux.conf

# sudo systemctl enable ssh
# sudo systemctl start ssh
echo 'ClientAliveInterval 30' >> /etc/ssh/sshd_config

service sshd restart
