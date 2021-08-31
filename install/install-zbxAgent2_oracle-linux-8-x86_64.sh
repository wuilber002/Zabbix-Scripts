#!/bin/sh
#===============================================================================
#         FILE: install-zbxAgent2_oracle-linux-8-x86_64.sh
#        USAGE: curl -ks https://raw.githubusercontent.com/wuilber002/Zabbix-Scripts/master/install/install-zbxAgent2_oracle-linux-8-x86_64.sh|bash -s -- <zabbix_server_address>
#
#  DESCRIPTION: Script de instalacao para o Zabbix Agent2 5.4 
#
#       AUTHOR: Igor Nicoli
#      VERSION: 1.0
#      CREATED: 30/08/2021 17:55:01 PM
#     REVISION: ---
#===============================================================================

GREEN='\033[0;32m' # Green color
RED='\033[0;31m'   # Red color
RESET='\033[0m'    # Reset color

if [ `id -u` -ne 0 ]; then
    printf '[${RED}ERRO${RESET}] Voce precisa esta logado como root... Execute o comando "sudo su -"'
    exit 1
fi

# Endereco Ip do Zabbix Server e Data de backup para os arquivos de configuracao.
zabbix_server=$1
hostname=$(hostname -s|cut -d \. -f 1|tr [a-z] [A-Z])
local_address=$(hostname -I)
backup_data=$(date +%Y_%m_%d-%H_%M_%S)
log="/tmp/zabbix_agent_install_${backup_data}.log"
if [ -z "${zabbix_server}" ]; then
    printf "[${RED}ERRO${RESET}] Voce precisa especificar o endereco do servidor zabbix.\n" 2>&1 | tee --append ${log}
    exit 1
fi

printf "[${GREEN}INFO${RESET}] Configuracao do repositorio do Zabbix\n" 2>&1 | tee --append ${log}
rpm -Uvh https://repo.zabbix.com/zabbix/5.4/rhel/8/x86_64/zabbix-release-5.4-1.el8.noarch.rpm 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Instalando o Zabbix agent2\n" 2>&1 | tee --append ${log}
yum --assumeyes install zabbix-sender zabbix-agent2 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Configuracao de regras de Firewall (Oracle Linux)\n" 2>&1 | tee --append ${log}
firewall-cmd --zone=public --permanent --add-port=10050/tcp 1>>${log} 2>&1
firewall-cmd --reload 1>>${log} 2>&1
iptables -nL 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Configurando o Zabbix agent2\n" 2>&1 | tee --append ${log}
cp /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf_${backup_data}
sed -i -e "s/Server=127.0.0.1$/Server=${zabbix_server}/" \
-e "s/# Plugins.SystemRun.LogRemoteCommands=0/Plugins.SystemRun.LogRemoteCommands=1/" \
-e "s/# DenyKey=system.run[*]/AllowKey=system.run[*]/" \
-e "s/# UnsafeUserParameters=0/UnsafeUserParameters=1/" \
-e "s/^Hostname=Zabbix server$/Hostname=$hostname/" \
/etc/zabbix/zabbix_agent2.conf
cat /etc/zabbix/zabbix_agent2.conf|egrep '^(Server|LogRemoteCommands|DenyKey|UnsafeUserParameters|Hostname)=' 1>>${log} 2>&1

printf "[${GREEN}INFO${RESET}] Iniciando o servico do zabbix agent2\n" 2>&1 | tee --append ${log}
systemctl enable zabbix-agent2.service 1>>${log} 2>&1
systemctl start zabbix-agent2.service 1>>${log} 2>&1
systemctl status zabbix-agent2.service 2>&1 | tee --append ${log}
lsof -Pi tcp:10050 +c0 2>&1 | tee --append ${log}

printf "\n>>> ${RED}Instalation information${RESET} <<<\n"
printf "> Hostname = $hostname\n"
printf "> Local Address = $local_address\n"

### Uninstall commands:
# rpm -aq | grep zabbix|xargs yum --assumeyes remove
# rm -rf /etc/zabbix
# firewall-cmd --zone=public --remove-port=10050/tcp --permanent && firewall-cmd --reload
