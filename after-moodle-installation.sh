#!/bin/bash

## configure moodle static content optimization
sed -i "/require_once/i \
\$CFG->xsendfile = 'X-Accel-Redirect';\n\
\$CFG->xsendfilealiases = array(\n\
    '/dataroot/' => \$CFG->dataroot\n\
);\n" /var/www/html/config.php

## configure moodle heartbeat
curl https://moodle.org/plugins/download.php/33918/tool_heartbeat_moodle44_2024111800.zip -o /tmp/heartbeat.zip
unzip -q /tmp/heartbeat.zip -d /var/www/html/admin/tool
chown -R root:root /var/www/html/admin/tool/heartbeat
chmod -R 0755 /var/www/html/admin/tool/heartbeat
echo Access YOUR_MOODLE_URL/admin/settings.php?section=tool_heartbeat to configure hearbeat

exit 0