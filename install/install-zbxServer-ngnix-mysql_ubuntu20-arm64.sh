#!/bin/sh
#===============================================================================
#         FILE: install-on-ubuntu-20-arm64-zabbix-server-ngnix-external-mysql
#        USAGE: curl -ks https://github-url-project/install-zbxServer-ngnix-mysql_ubuntu20-arm64.sh| \
#               bash -s -- <mysql_address> <mysql_root_passwd>
#
#  DESCRIPTION: Script de instalacao para o Zabbix Server/Agent2 5.4 com nginx e
#               mysql instalado em servidor diferentes.
#
#       AUTHOR: Igor Nicoli
#      VERSION: 1.0
#      CREATED: 30/08/2021 17:55:01 PM
#     REVISION: ---
#===============================================================================

GREEN='\033[0;32m' # Green color
RED='\033[0;31m'   # Red color
RESET='\033[0m'    # Reset color

# Validacao do acesso de root ao servidor:
if [ `id -u` -ne 0 ]; then
    printf "[${RED}ERRO${RESET}] root is need... please run 'sudo su -'" 2>&1 | tee --append ${log}
    exit 1
fi
printf "[ ${GREEN}OK${RESET} ] Premissao de 'root'\n" 2>&1 | tee --append ${log}

# Parametros de configuracao:
if [ -z $1 ]; then
    printf "[${RED}ERRO${RESET}] Voce precisa especificar o endereco do endpoint do MySQL.\n" 2>&1 | tee --append ${log}
    exit 1
fi
if [ -z $2 ]; then
    printf "[${RED}ERRO${RESET}] Voce precisa especificar a senha do usuario "root" do MySQL.\n" 2>&1 | tee --append ${log}
    exit 1
fi
mysql_root_passwd=$2
mysql_server_address=$1
backup_data=$(date +%Y_%m_%d-%H_%M_%S)
mysql_zabbix_passwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${32:-32};echo \#1604;)
mysql_zbx_monitor_passwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${32:-32};echo \#1604;)
log="/tmp/zabbix_install_${backup_data}.log"

if [ `echo ${mysql_zabbix_passwd}|wc -c` -le 10 -o `echo ${mysql_zbx_monitor_passwd}|wc -c` -le 10 ]; then
    printf "[${RED}ERRO${RESET}] Falha ao criar as senhas randomicas.\n" 2>&1 | tee --append ${log}
    echo "  mysql_zabbix_passwd=${mysql_zabbix_passwd}" 2>&1 | tee --append ${log}
    echo "  mysql_zbx_monitor_passwd=${mysql_zbx_monitor_passwd}" 2>&1 | tee --append ${log}
    exit 1
fi

printf "[ ${GREEN}OK${RESET} ] Parametros de configuracao\n" 2>&1 | tee --append ${log}

printf "[${GREEN}INFO${RESET}] Download e configuracao do reposito do Zabbix\n" 2>&1 | tee --append ${log}
wget https://repo.zabbix.com/zabbix/5.4/ubuntu-arm64/pool/main/z/zabbix-release/zabbix-release_5.4-1+ubuntu20.04_all.deb -O /tmp/zabbix-release.deb 1>>${log} 2>&1
dpkg -i /tmp/zabbix-release.deb 1>>${log} 2>&1
rm -f /tmp/zabbix-release.deb 1>>${log} 2>&1
apt-get update 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Instalando o Zabbix server, agent2 e frontend\n" 2>&1 | tee --append ${log}
apt-get --assume-yes install \
zabbix-server-mysql \
zabbix-frontend-php \
zabbix-nginx-conf \
zabbix-sql-scripts \
zabbix-agent2 \
zabbix-get 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Configurando a inicializacao dos servicos no linux\n" 2>&1 | tee --append ${log}
systemctl enable \
zabbix-server.service \
zabbix-agent2.service \
nginx.service \
php7.4-fpm.service 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Configuracao do MySQL\n" 2>&1 | tee --append ${log}
mkdir -p /var/lib/zabbix && chown zabbix:zabbix /var/lib/zabbix 1>>${log} 2>&1
printf "[client]\nuser=zbx_monitor\npassword='${mysql_zbx_monitor_passwd}'\nhost=${mysql_server_address}\n" >/var/lib/zabbix/.my.cnf
printf "[client]\nuser=root\npassword='${mysql_root_passwd}'\nhost=${mysql_server_address}\n" >/root/.my.cnf

printf "[${GREEN}INFO${RESET}] Criando banco de dados e usuarios\n" 2>&1 | tee --append ${log}
echo "CREATE DATABASE zabbix CHARACTER SET utf8 COLLATE utf8_bin;" >/tmp/zabbix_mysql.sql
echo "CREATE USER 'zabbix'@'%' IDENTIFIED WITH mysql_native_password BY '${mysql_zabbix_passwd}';" >>/tmp/zabbix_mysql.sql
echo "CREATE USER 'zbx_monitor'@'%' IDENTIFIED WITH mysql_native_password BY '${mysql_zbx_monitor_passwd}';" >>/tmp/zabbix_mysql.sql
echo "GRANT USAGE,REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW ON *.* TO 'zbx_monitor'@'%';" >>/tmp/zabbix_mysql.sql
echo "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';" >>/tmp/zabbix_mysql.sql
mysql --host=${mysql_server_address} --user=root --execute 'source /tmp/zabbix_mysql.sql;' 1>>${log} 2>&1
rm -f /tmp/zabbix_mysql.sql

printf "[${GREEN}INFO${RESET}] Carregando dados iniciais do banco de dados do zabbix\n" 2>&1 | tee --append ${log}
su --shell /bin/bash zabbix --command "zcat /usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz | mysql --host=${mysql_server_address} --user=zabbix zabbix --password='${mysql_zabbix_passwd}'"  1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Configurando o Zabbix Server\n" 2>&1 | tee --append ${log}
cp -p /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.conf_${backup_data}
sed -i -e "s/# DBPassword=$/DBPassword=${mysql_zabbix_passwd}/" \
-e "s/^# DBHost=localhost$/DBHost=${mysql_server_address}/" \
/etc/zabbix/zabbix_server.conf 1>>${log} 2>&1
cat /etc/zabbix/zabbix_server.conf|egrep '^(DBPassword|DBHost)=' 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Reiniciando o Zabbix server\n" 2>&1 | tee --append ${log}
systemctl restart zabbix-server.service
systemctl status zabbix-server.service 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] NGINX: Criando certificado ssl\n" 2>&1 | tee --append ${log}
[ -e /usr/local/nginx/ssl ] || mkdir -p /usr/local/nginx/ssl
cd /usr/local/nginx/ssl
openssl req \
-subj "/C=BR/ST=Sao Paulo/L=Sao Paulo/O=IT/CN=" \
-x509 \
-nodes \
-days 3650 \
-newkey rsa:2048 \
-keyout /usr/local/nginx/ssl/cert.key \
-out /usr/local/nginx/ssl/cert.crt 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] NGINX: Configuracao do site\n" 2>&1 | tee --append ${log}
cp -p /etc/nginx/conf.d/zabbix.conf /etc/nginx/conf.d/zabbix.conf_${backup_data}
TEMP_FILE=`mktemp`
cat > $TEMP_FILE << "EOF"
H4sIAAAAAAAAA5VW31PiMBB+lr8izvCg40wDio4D44OjnDiD4EF9cPyRCemWZixJL0k58NC//dJC
EQRb3Ye0Yff7drvZ3aBBjUGhf6WdkGsDAp1WkAc+jUNDdKprlHbmL0TQESBi9wpMrAQ6qlRRYEyk
6xiXA6lNWcGfGLQhseKN0luppD+x7+zUakdI67BRQgtZ5U4EJnQUheAwOWqUrGsdEgbKcJ8zauYm
ONYKh5LREIshFxNsjXBi5DBlGhsY8gLTHIzVLjCRkkYyGepFaP1+e3yE3HZ/XJ2vTvY8zLzwKACV
2SPUur5q1Xdp567dru/eXB7bL8hUSkqzDF4HVAF+pYMBn6zYcOHBJHs6URAlGUiCNlwKdIbwgGrO
iDbUxDrJappAEw8WP9mo3j7YVoE+HXMmhWMXi0OfJJRDIqQhvoyFZ/fS9z8OaBsj3kJi1JT4PIQs
G2VbBOmC0VmtUisgpFqD0VtoKWOgNbEhzvdrsWUCk4gr+DiHasXL9/eO8KMTmC3+PBDTNf9hWEi1
RyP+iGc2wf7D86PzNOOChbEHs7TgYP+nbjJZ9NlSCtP4jh6e8dNjUjp7eFbe5tin2rAhJ5HNeLKP
BZ/UsYoFtqBFSTpaspfNcDKojkJuLIEJCBe+RM97zkHqc38POwf75a+R2wr86wAVHdn9Zffi7qbZ
cUmv23XR1gYqouhf9K5vXfLrut3snN80NynKy09jikcmnUbFtLfnbou4vfNOv33uNi+/S7vBu6iW
dX5d7P/3XbN3T/pu77pzlejLdvjaJtRGcTEshvealqDvkpum2+peWng2vUdgAukVE1x0O25yMO79
bTP1bxvADnlDzDT6RvoyuD2UK7e1Ag9BDE2QUxrc2ikGNqOglPyYv1LklN5QSAWEhTxxQQdSmTlm
2zzJQDYiAcx+EB+BjM1Sf1LJ6Q4Q3gbASvU0B6SA/hw0iH3fXp2av8Kavnp4mtO9c5T+rEY1dHh8
kovT0wy86jMfZWAUpdcC+au4vYsz4Drqzf5Z+A/GDhGqiggAAA==
EOF
cat $TEMP_FILE | base64 -d | gzip -d >/etc/nginx/conf.d/zabbix.conf
rm -f $TEMP_FILE
cat /etc/nginx/conf.d/zabbix.conf 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] NGINX: Configuracao geral\n" 2>&1 | tee --append ${log}
cp -p /etc/nginx/nginx.conf /etc/nginx/nginx.conf_${backup_data}
TEMP_FILE=`mktemp`
cat > $TEMP_FILE << "EOF"
H4sIAAAAAAAAA51WbYvbOBD+7l8xJAsL5dbObpOjJPTDQVM42NJj0y9HKUIrjxMRW/JJcl6u7H+/
kawkztt2uRAntueZR6NnnnHSh8/aQKUNglSFNhV3Uiugt9CqkPPGhBu/gUUcJ30AeAdfi0IKyUuY
qnkp7QI+adFUqFyAjmHhXD3OMjWXapNqM89QZbkWNjvNf2qslVz9Mt80MT9pLBpYr9d3OXd8kqy1
WaJhtdECrUULvHF6kqAx2rBSzyFbcZPRSUuWhUBK15OkljkQsYrL0OUkofoeNc8h3ypeSUGy5E2J
NoUZImSNNZldcIO+mEj4NP3j05dpGhPSRCpRNvkRuAVGquxd6nWlpXBFG7bwMyFJIO6DQgqFF8HC
/eBhOEleksSrEWFUOGt7BFBxqQBubwxW2iHjeW7gDnaXQafvN05WSDoIXv6AHsX+adC6HtwGtvPX
7Y2lHjQWbp51vmXPW4eWWaqTkn0ZzGCBBs0rDBHo12d8Tqm9Xe7Gl77mJsfcn/VuSQSfwoXvXejW
abvaUBpCfr8xgyrKC1lid2FNQf/tRM2Urhty5ZVYjiXfnsWWiDUv5QqZ10w3pDD8Pop525p0WHC7
YBXfMCv/RXgYDD/EcnY9774ydDuLVMSXBoqWLceCN6Vj/tYOzuu6lCLYP9PCobuzziCv4grRlsFD
3BxPJnglLBRGV+AW2F3Z41JyszRkKm22aSTzbr46o2q+IR8aZK1j04Wryn7cYswvLjwx0iMpzoo4
+D5QkDtWZNCfkdBbW1qHKsrxYbBXqUVOrgC/j8c/xq+h2xuMppO0Zp2A0dodunU6rX7Te+0PDbgo
PInhdY8lxBXhmaZumR4YLigTM87ECbvUrRsg64r00kG0z7iaZgyGgyFk9JG2Ze8hR0QfPWQTIG+g
HA0GdDzQ8Z4Ooh/F3FfoRxfpw+mLf7TO0Dmp5q1kHL49zgAVfy4xj6KlST/pdI14Dut0uz4cvgdr
y+Dhh7PeX84JTnlj4qlp9oG3mKbf4bElE2icLPxsI/RC8+uljAlx18K43uRqFlvi9iyzNnJFsR0D
QU4Z6MfQUl+Y4ILMGcrMx7PZ4/i+uoLcP/fuB6cQIesFGgt/PX39/Ofj9OPs79m36ZcTUB1+HKKa
+xT/fO1I8r8Hac/wpkHqrHg0Sfu7L13I9VHaQ0693hmlX3K+MktX+UeX+dsv/6/gP0LVzd64CQAA
EOF
cat $TEMP_FILE | base64 -d | gzip -d >/etc/nginx/nginx.conf
rm -f $TEMP_FILE
cat /etc/nginx/nginx.conf 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] PHP-FPM: Configuracao\n" 2>&1 | tee --append ${log}
cp -p /etc/zabbix/php-fpm.conf /etc/zabbix/php-fpm.conf_${backup_data}
sed -i -e 's/; php_value\[date\.timezone\] = Europe\/Riga/php_value\[date\.timezone\] = America\/Sao_Paulo/' \
/etc/zabbix/php-fpm.conf
cat /etc/zabbix/php-fpm.conf| egrep date.timezone 1>>${log} 2>&1
systemctl restart nginx.service php7.4-fpm.service 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] FIREWALL: Criando regras locais\n" 2>&1 | tee --append ${log}
cp -p /etc/iptables/rules.v4 /etc/iptables/rules.v4_${backup_data}
iptables -I INPUT 1 -p tcp --match multiport -d 0.0.0.0/0 --dport 80,443 -m state --state NEW,ESTABLISHED -j ACCEPT -m comment --comment "Nginx: HTTP and HTTPS" 1>>${log} 2>&1
iptables -I INPUT 2 -p tcp -d 0.0.0.0/0 --dport 10051 -m state --state ESTABLISHED -j ACCEPT -m comment --comment "Zabbix Server: port 10051/TCP" 1>>${log} 2>&1
iptables-save 1>>${log} 2>&1
iptables-save >/etc/iptables/rules.v4

printf "[${GREEN}INFO${RESET}] ZABBIX: Configuracao do frontend\n" 2>&1 | tee --append ${log}
[ -e /etc/zabbix/web/zabbix.conf.php ] && cp -p /etc/zabbix/web/zabbix.conf.php /etc/zabbix/web/zabbix.conf.php_${backup_data}
cat > /etc/zabbix/web/zabbix.conf.php << EOF
<?php
// Zabbix GUI configuration file.

\$DB['TYPE'] = 'MYSQL';
\$DB['SERVER'] = '${mysql_server_address}';
\$DB['PORT'] = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER'] = 'zabbix';
\$DB['PASSWORD'] = '${mysql_zabbix_passwd}';

// Schema name. Used for PostgreSQL.
\$DB['SCHEMA'] = '';

// Used for TLS connection.
\$DB['ENCRYPTION'] = false;
\$DB['KEY_FILE'] = '';
\$DB['CERT_FILE'] = '';
\$DB['CA_FILE'] = '';
\$DB['VERIFY_HOST'] = false;
\$DB['CIPHER_LIST'] = '';

// Use IEEE754 compatible value range for 64-bit Numeric (float) history values.
// This option is enabled by default for new Zabbix installations.
// For upgraded installations, please read database upgrade notes before enabling this option.
\$DB['DOUBLE_IEEE754'] = true;

\$ZBX_SERVER = 'zabbix-server';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;

// Uncomment this block only if you are using Elasticsearch.
// Elasticsearch url (can be string if same url is used for all types).
//$HISTORY['url'] = [
//	'uint' => 'http://localhost:9200',
//	'text' => 'http://localhost:9200'
//];
// Value types stored in Elasticsearch.
//$HISTORY['types'] = ['uint', 'text'];

// Used for SAML authentication.
// Uncomment to override the default paths to SP private key, SP and IdP X.509 certificates, and to set extra settings.
//\$SSO['SP_KEY'] = 'conf/certs/sp.key';
//\$SSO['SP_CERT'] = 'conf/certs/sp.crt';
//\$SSO['IDP_CERT'] = 'conf/certs/idp.crt';
//\$SSO['SETTINGS'] = [];
EOF
cat /etc/zabbix/web/zabbix.conf.php 1>>${log} 2>&1
chown www-data:www-data /etc/zabbix/web/zabbix.conf.php 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] ZABBIX AGENT2: Reiniciando\n" 2>&1 | tee --append ${log}
systemctl restart zabbix-agent2.service
systemctl status zabbix-agent2.service 1>>${log} 2>&1

printf "\n>>> List of users and passwords created by this script <<<\n"
printf "MySQL: User(zabbix) ............: ${mysql_zabbix_passwd}\n"
printf "MySQL: User(zbx_monitor_passwd) : ${mysql_zbx_monitor_passwd}\n\n"
