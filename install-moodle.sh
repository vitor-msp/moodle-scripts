#!/bin/bash

# check env vars
for var in MOODLE_DATA_EFS_HOSTNAME MOODLE_CODE_EFS_HOSTNAME MOODLE_DOMAIN; do
    if [ -z "${!var}" ]; then
        echo "Environment variable $var is not set."
        exit 1
    fi
done

# set timezone
timedatectl set-timezone America/Sao_Paulo

# install packages
apt update && apt upgrade -y
apt -y install nginx curl aspell git ghostscript unzip cron nfs-common php8.3-{pgsql,fpm,pspell,curl,gd,intl,xml,xmlrpc,ldap,zip,soap,mbstring,tokenizer,redis}

# configure php
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

# generate tls certificate
mkdir /var/www/moodlecert
cd /var/www/moodlecert
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 -out ca.crt -subj "/C=BR/ST=Minas Gerais/L=Belo Horizonte/O=Colegio Logosofico/OU=Matriz/CN=ca.colegiologosofico.com.br"
openssl genrsa -out moodle.key 2048
openssl req -new -key moodle.key -out moodle.csr -subj "/C=BR/ST=Minas Gerais/L=Belo Horizonte/O=Colegio Logosofico/OU=Matriz/CN=www.colegiologosofico.com.br"
openssl x509 -req -in moodle.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out moodle.crt -days 365 -sha256
chmod 644 moodle.crt moodle.key

# configure nginx
cp ./nginx.conf /etc/nginx/nginx.conf.template
cp ./moodle.conf /etc/nginx/sites-available/moodle.conf
ln -sf /etc/nginx/sites-available/moodle.conf /etc/nginx/sites-enabled/moodle 
rm /etc/nginx/sites-enabled/default
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
envsubst '${INSTANCE_ID}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
systemctl enable nginx
systemctl restart nginx

# configure efs
mkdir /var/www/moodledata
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $MOODLE_DATA_EFS_HOSTNAME:/ /var/www/moodledata
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $MOODLE_CODE_EFS_HOSTNAME:/ /var/www/html
printf "\n $MOODLE_DATA_EFS_HOSTNAME:/ /var/www/moodledata nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0 \n" >> /etc/fstab
printf "\n $MOODLE_CODE_EFS_HOSTNAME:/ /var/www/html nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0 \n" >> /etc/fstab

# configure moodle
if [ ! -f /var/www/html/config.php ]; then
    rm /var/www/html/*
    git clone -b MOODLE_405_STABLE git://git.moodle.org/moodle.git /var/www/html/
    chown -R root:root /var/www/html
    chmod -R 0755 /var/www/html
    chown -R www-data:www-data /var/www/moodledata
    chown www-data /var/www/html
fi

# install cloudwatch agent
curl https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/amazon-cloudwatch-agent.deb
apt install -y /tmp/amazon-cloudwatch-agent.deb
systemctl enable amazon-cloudwatch-agent
cp ./cloudwatch-agent.json /var/www/cloudwatch-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/var/www/cloudwatch-agent.json

# configure initialization script
cp ./moodle-initialization.sh /var/www/initialization.sh
chmod 770 /var/www/initialization.sh
echo "@reboot MOODLE_DOMAIN=\"$MOODLE_DOMAIN\" /var/www/initialization.sh >> /dev/null 2>&1" | crontab -

exit 0