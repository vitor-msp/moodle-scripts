#!/bin/bash

STATUS_FILE=/var/www/html/ec2-launch-status.php

init_log(){
    echo "<?php" > $STATUS_FILE
}

log(){
    MESSAGE=$1
    echo "echo '$MESSAGE <br>';" >> $STATUS_FILE
}

log_bold(){
    MESSAGE=$1
    log "<strong>$MESSAGE</strong>"
}

check_env_vars(){
    if [ -z "$MOODLE_URL" ]; then
        log_bold "Error in Moodle initialization script: environment variable MOODLE_URL is not set"
        exit 1
    fi
}

configure_nginx(){
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    export INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    envsubst '${INSTANCE_ID}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
}

set_moodle_domain(){
    MOODLE_URL=${MOODLE_URL,,}
    sed -i "s|\$CFG->wwwroot.*|\$CFG->wwwroot   = '$MOODLE_URL';|" /var/www/html/config.php
}

restart_nginx(){
    systemctl restart nginx
}

main(){
    init_log
    log_bold "Moodle initialization script started"
    log "checking env vars"
    check_env_vars
    log "configuring nginx"
    configure_nginx
    log "setting moodle domain"
    set_moodle_domain
    log "restarting nginx"
    restart_nginx
    log_bold "Moodle initialization script completed"
    exit 0
}

main