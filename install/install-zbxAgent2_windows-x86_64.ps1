#===============================================================================
#         FILE: install-zbxAgent2_windows-x86_64.ps1
#        USAGE: curl -ks https://raw.githubusercontent.com/wuilber002/Zabbix-Scripts/master/install/install-zbxAgent2_windows-x86_64.ps1
#
#  DESCRIPTION: Script de instalacao para o Zabbix Agent2 5.4 
#
#       AUTHOR: Igor Nicoli
#      VERSION: 1.0
#      CREATED: 30/08/2021 17:55:01 PM
#     REVISION: ---
#===============================================================================
#
# Para instalar esse script, execute os dois comandos abaixo:
# $install_script="https://raw.githubusercontent.com/wuilber002/Zabbix-Scripts/master/install/install-zbxAgent2_windows-x86_64.ps1"
# Invoke-WebRequest -Uri $install_script -OutFile "$env:TEMP\zabbix_agent_install.ps1"
# cd $env:TEMP
# .\zabbix_agent_install.ps1 -server <zabbix_server_address>

# Parametros Ip do Zabbix Server e Data de backup para os arquivos de configuracao.
param ($server, $port='')
if ($server -eq $null) {
    Write-Host "Voce precisa informar o endereco do servidor zabbix."
    exit 1
}
$msi='https://cdn.zabbix.com/zabbix/binaries/stable/5.4/5.4.3/zabbix_agent2-5.4.3-windows-amd64-openssl.msi'
$install_folder = 'C:\Program Files\Zabbix Agent'
$server_name = (Get-WMIObject Win32_ComputerSystem | Select-Object -ExpandProperty name).ToUpper()
$DataStamp = get-date -Format yyyy.MM.dd-HH.mm.ss
$logFile = '{0}\{1}-{2}.log' -f $env:TEMP,"install-zabbix-agent",$DataStamp

# Download do binario de instalacao:
Add-Content -Path "FilePath" -Value "Fazendo download do instalador"
Write-Host 'Fazendo download do instalador'
Invoke-WebRequest -Uri $msi -OutFile "$env:TEMP\zabbix_agent.msi" 

# Comando de instalacao do Zabbix Agent 2
if (Test-Path "$env:TEMP\zabbix_agent.msi") {
    Write-Host 'Instalando o Zabbix Agent 2'
    $MSIArguments = @(
        "/passive"
        "/norestart"
        "/l*v ""$logFile"""
        "/i ""$env:TEMP\zabbix_agent.msi"""
        "ADDLOCAL=""AgentProgram,MSIPackageFeature"""
        "LOGTYPE=""file"""
        "LOGFILE=""$install_folder\log\zabbix_agentd.log"""
        "ENABLEREMOTECOMMANDS=""1"""
        "SERVER=""$server,127.0.0.1"""
        "SERVERACTIVE=""$server$port"""
        "HOSTNAME=""$server_name"""
        "TIMEOUT=""15"""
        "INSTALLFOLDER=""$install_folder"""
        "ENABLEPATH=""1"""
        "SKIP=""fw"""
    )
    Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait

    # deleta o binario de instalacao do Zabbix Agent 2
    Remove-Item -path "$env:TEMP\zabbix_agent.msi" -recurse
}

# Firewall rules (Oracle Linux)
Write-Host '>>> Criando regra de firewall'
New-NetFirewallRule -DisplayName "Zabbix Agent" -Direction inbound -Profile Any -Action Allow -LocalPort 10050 -Protocol TCP | Out-File -Append -FilePath "$logFile"

# Iniciar o servico do Zabbix Agent 2
Write-Host '>>> Iniciando o servico'
Start-Service -Name "Zabbix Agent 2" | Out-File -Append -FilePath "$logFile"

Write-Host ">>> Instalation information <<<"
Write-Host "> Hostname = $server_name"
Write-Host "> Local Address ="(Test-Connection -ComputerName (hostname) -Count 1  | Select -ExpandProperty IPV4Address).IPAddressToString
Write-Host "> Instalation Folder = $install_folder"

### Uninstall commands:
# (Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Zabbix Agent 2 (64-bit)"}).Uninstall()
# Remove-NetFirewallRule -DisplayName "Zabbix Agent"
