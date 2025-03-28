#!/bin/bash

ROOT_FOLDER=$(pwd)
LOG_FILE=/tmp/ec2-launch-status.php

log(){
    MESSAGE=$1
    echo $MESSAGE >> $LOG_FILE
}

log_bold(){
    MESSAGE=$1
    log "### $MESSAGE ###"
}

check_env_vars(){
    for var in MOODLE_DATA_EFS_HOSTNAME MOODLE_CODE_EFS_HOSTNAME MOODLE_URL; do
        if [ -z "${!var}" ]; then
            log_bold "Error in Moodle installation: environment variable $var is not set"
            exit 1
        fi
    done
}

set_timezone(){
    timedatectl set-timezone America/Sao_Paulo
}

install_packages(){
    apt update && apt upgrade -y
    apt -y install nginx curl aspell git ghostscript unzip cron nfs-common php8.3-{pgsql,fpm,pspell,curl,gd,intl,xml,xmlrpc,ldap,zip,soap,mbstring,tokenizer,redis}
}

configure_php(){
    sed -i s'/;max_input_vars =.*/max_input_vars = 5000/' /etc/php/8.3/fpm/php.ini
    sed -i s'/;max_input_vars =.*/max_input_vars = 5000/' /etc/php/8.3/cli/php.ini
    sed -i s'/.*post_max_size =.*/post_max_size = 256M/' /etc/php/8.3/fpm/php.ini
    sed -i s'/.*post_max_size =.*/post_max_size = 256M/' /etc/php/8.3/cli/php.ini
    sed -i s'/.*upload_max_filesize =.*/upload_max_filesize = 256M/' /etc/php/8.3/fpm/php.ini
    sed -i s'/.*upload_max_filesize =.*/upload_max_filesize = 256M/' /etc/php/8.3/cli/php.ini
    sed -i s'/;security.limit_extensions =.*/security.limit_extensions = .php/' /etc/php/8.3/fpm/pool.d/www.conf
    sed -i s'/^listen =.*/listen = 127.0.0.1:9000/' /etc/php/8.3/fpm/pool.d/www.conf
    echo "* * * * * /usr/bin/php /var/www/html/admin/cli/cron.php > /dev/null" | crontab -u www-data -
    phpenmod redis
    systemctl enable php8.3-fpm
    systemctl restart php8.3-fpm
}

generate_tls_certificate(){
    mkdir /var/www/moodlecert
    cd /var/www/moodlecert
    openssl genrsa -out ca.key 4096
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt -subj "/C=BR/ST=Minas Gerais/L=Belo Horizonte/O=Colegio Logosofico/OU=Matriz/CN=ca.colegiologosofico.com.br"
    openssl genrsa -out moodle.key 2048
    openssl req -new -key moodle.key -out moodle.csr -subj "/C=BR/ST=Minas Gerais/L=Belo Horizonte/O=Colegio Logosofico/OU=Matriz/CN=www.colegiologosofico.com.br"
    openssl x509 -req -in moodle.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out moodle.crt -days 365 -sha256
    chmod 644 moodle.crt moodle.key
}

configure_nginx(){
    cp $ROOT_FOLDER/nginx.conf /etc/nginx/nginx.conf.template
    cp $ROOT_FOLDER/moodle.conf /etc/nginx/sites-available/moodle.conf
    ln -sf /etc/nginx/sites-available/moodle.conf /etc/nginx/sites-enabled/moodle 
    rm /etc/nginx/sites-enabled/default
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    export INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    envsubst '${INSTANCE_ID}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
    systemctl enable nginx
    systemctl restart nginx
}

configure_efs(){
    mkdir /var/www/moodledata
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $MOODLE_DATA_EFS_HOSTNAME:/ /var/www/moodledata
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $MOODLE_CODE_EFS_HOSTNAME:/ /var/www/html
    printf "\n $MOODLE_DATA_EFS_HOSTNAME:/ /var/www/moodledata nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0 \n" >> /etc/fstab
    printf "\n $MOODLE_CODE_EFS_HOSTNAME:/ /var/www/html nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0 \n" >> /etc/fstab
}

configure_moodle(){
    rm /var/www/html/*
    git clone -b MOODLE_405_STABLE git://git.moodle.org/moodle.git /var/www/html/
    chown -R root:root /var/www/html
    chmod -R 0755 /var/www/html
    chown www-data /var/www/html
    chown -R www-data:www-data /var/www/moodledata
}

configure_cloudwatch_agent(){
    curl https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/amazon-cloudwatch-agent.deb
    apt install -y /tmp/amazon-cloudwatch-agent.deb
    systemctl enable amazon-cloudwatch-agent
    cp $ROOT_FOLDER/cloudwatch-agent.json /var/www/cloudwatch-agent.json
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/var/www/cloudwatch-agent.json
}

configure_initialization_script(){
    cp $ROOT_FOLDER/moodle-initialization.sh /var/www/initialization.sh
    chmod 770 /var/www/initialization.sh
    echo "@reboot MOODLE_URL=\"$MOODLE_URL\" /var/www/initialization.sh >> /dev/null 2>&1" | crontab -
}

main(){
    log_bold "Moodle installation started"
    log "checking env vars"
    check_env_vars
    log "setting time zone"
    set_timezone
    log "installing packages"
    install_packages
    log "configuring php"
    configure_php
    log "generating tls certificate"
    generate_tls_certificate
    log "configuring nginx"
    configure_nginx
    log "configuring efs"
    configure_efs
    if [ ! -d /var/www/html/.git ]; then
        log "configuring moodle"
        configure_moodle
    fi
    log "configuring cloudwatch agent"
    configure_cloudwatch_agent
    log "configuring initialization script"
    configure_initialization_script
    log_bold "Moodle installation completed"
    exit 0
}

main
