#!/bin/bash

# check env vars
if [ -z "$MOODLE_DOMAIN" ]; then
    echo "Environment variable MOODLE_DOMAIN is not set."
    exit 1
fi

# set instance id env var for nginx
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
envsubst '${INSTANCE_ID}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# set moodle domain
sed -i "s|\$CFG->wwwroot.*|\$CFG->wwwroot   = '$MOODLE_DOMAIN';|" /var/www/html/config.php

# restart nginx
systemctl restart nginx

exit 0