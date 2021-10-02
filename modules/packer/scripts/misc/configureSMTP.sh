#!/bin/bash

#TODO: Revuew below article and review DKIM and SPF to not have email regarded as spam
###! https://support.google.com/mail/answer/180707?visit_id=637681501706136161-1311806758&p=email_auth&hl=en&rd=1#zippy=%2Ca-message-i-sent-from-my-domain-wasnt-authenticated
###! https://support.google.com/mail/answer/81126

SCRIPT_LOCATION=$(realpath $0)

while getopts "d:k:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DOMAIN=$OPTARG;;
        k) SENDGRID_KEY=$OPTARG;;
    esac
done

## TODO: Programatically determine if ip is on a blacklist
## TODO: Setup DKIM/SPF/MX records
## TODO: Setup gitlab incoming email:  https://docs.gitlab.com/ee/administration/incoming_email.html

##! NOTE: List of possible helpful tools to automate testing if IP is blacklisted
##! Some have illustrated its possible to do a quick lookup and all we want to do is lookup the IP this is run from

#https://check.spamhaus.org/
#https://community.spiceworks.com/topic/2218412-where-can-i-download-a-blacklist-for-email
#http://www.spamhaus.org/drop/drop.txt
#http://www.spamhaus.org/drop/edrop.txt
#https://www.iblocklist.com/lists
#https://www.spamhaus.org/zen/
#https://developers.google.com/safe-browsing/
#https://myip.ms/browse/blacklist/Blacklist_IP_Blacklist_IP_Addresses_Live_Database_Real-time
#https://www.projecthoneypot.org/httpbl_api.php

#https://github.com/IntellexApps/blcheck

#IS_BLACKLISTED=$(doiplookup)
IS_BLACKLISTED=false

if [[ -z $SENDGRID_KEY && $IS_BLACKLISTED = "true" ]]; then
    echo "==========================================================================="
    echo "==========================================================================="
    echo "Unfortunately this IP appears in one or more blocklists and will most likely be unsuccessful when sending email."
    echo
    echo "There are steps you can take to remove it but depend on several factors that are outside the scope of this script."
    echo "An alternative is to use a 3rd party email provider to use as an SMTP host/relay."
    echo
    echo "For simple outgoing email for say a hobby project sendgrid provides a fairly straightforward process and this"
    echo "project comes with sendgrid support built-in."
    echo
    echo "See $SCRIPT_LOCATION for more details regarding email configuration."
    echo "============================================================================"
    echo "============================================================================"
    exit 0;
fi


if [ -n "$SENDGRID_KEY" ]; then
    sed -i "s|# gitlab_rails\['smtp_enable'\]|gitlab_rails\['smtp_enable'\]|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_address'\] = \"smtp.server\"|gitlab_rails\['smtp_address'\] = \"smtp.sendgrid.net\"|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_port'\] = 465|gitlab_rails\['smtp_port'\] = 587|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_user_name'\] = \"smtp user\"|gitlab_rails\['smtp_user_name'\] = \"apikey\"|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_password'\] = \"smtp password\"|gitlab_rails\['smtp_password'\] = \"${SENDGRID_KEY}\"|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_domain'\] = \"example.com\"|gitlab_rails\['smtp_domain'\] = \"smtp.sendgrid.net\"|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_authentication'\] = \"login\"|gitlab_rails\['smtp_authentication'\] = \"plain\"|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_enable_starttls_auth'\]|gitlab_rails\['smtp_enable_starttls_auth'\]|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['smtp_tls'\]|gitlab_rails\['smtp_tls'\]|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['gitlab_email_from'\] = 'example@example.com'|gitlab_rails\['gitlab_email_from'\] = 'gitlab@${DOMAIN}'|" /etc/gitlab/gitlab.rb
    sed -i "s|# gitlab_rails\['gitlab_email_reply_to'\] = 'noreply@example.com'|gitlab_rails\['gitlab_email_reply_to'\] = 'noreply@${DOMAIN}'|" /etc/gitlab/gitlab.rb

    sudo gitlab-ctl reconfigure;
else
    echo "Configuring postfix"
    echo postfix postfix/mailname string $DOMAIN | sudo debconf-set-selections
    echo postfix postfix/main_mailer_type string 'Internet Site' | sudo debconf-set-selections
    sudo apt-get install --assume-yes postfix;

    ###! Maybe in `/etc/postfix/main.cf` modify and `sudo service postfix restart`
    ###!    mydestination = $myhostname, localhost.$mydomain, $mydomain
    ###!    inet_interfaces = all    to:  inet_interfaces = loopback-only
fi


###! Test sending email from gitlab
###! sudo gitlab-rails console -e production
###! Notify.test_email('youremail@example.com', 'Hello World', 'This is a test message').deliver_now

