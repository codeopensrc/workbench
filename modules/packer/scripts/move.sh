#!/bin/bash

mv /tmp/scripts/* /root/code/scripts

echo 'ClientAliveInterval 30' >> /etc/ssh/sshd_config

service sshd restart
