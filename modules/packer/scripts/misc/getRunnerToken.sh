#!/bin/bash

DOMAIN=$(hostname -d)

USER="root"
PW=""

while getopts "d:p:u:" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DOMAIN=$OPTARG;;
        p) PW=$OPTARG;;
        u) USER=$OPTARG;;
    esac
done

if [[ -f  /tmp/cookies.txt ]]; then rm /tmp/cookies.txt; fi

## Get csrf token
RES1=$(curl -s -L --cookie-jar /tmp/cookies.txt "https://gitlab.$DOMAIN/users/sign_in")
TOKEN1=$(echo $RES1 | grep "authenticity" |  sed -rn "s|.*authenticity_token\" value=\"([^\"]+)\".*|\1|p")

## Get login token/cookie
curl -s -L --cookie /tmp/cookies.txt \
    --cookie-jar /tmp/cookies.txt \
    --data-urlencode "authenticity_token=$TOKEN1" \
    --data-urlencode "user[login]=$USER" \
    --data-urlencode "user[password]=$PW" \
    --data-urlencode "user[remember_me]=1" \
    "https://gitlab.$DOMAIN/users/sign_in" > /dev/null

## Get Registration token from admin page
URL="https://gitlab.$DOMAIN/admin/runners"
RES=$(curl -s -L --cookie /tmp/cookies.txt --cookie-jar /tmp/cookies.txt $URL)
TOKEN=$(echo $RES | grep "registration" | sed -rn "s|.*data-registration-token=\"([^\"]+)\".*|\1|p")

rm /tmp/cookies.txt


echo $TOKEN
