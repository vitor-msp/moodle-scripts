# Moodle Scripts

### Scripts para instalação e gerenciamento do Moodle

O script [install-moodle.sh](install-moodle.sh) deve rodar na inicialização para instalar o PHP, Ningx, Moodle, CloudWatch Agent e demais dependências.

Após a finalização do script, o Moodle deve ser configurado pela interface web. Enfim, o script [after-moodle-installation.sh](after-moodle-installation.sh) deve ser executado para otimizar a entrega de conteúdo estático e instalar o plugin Moodle Heartbeat.