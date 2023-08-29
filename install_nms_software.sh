#!/bin/bash
#This is not an official Airspan Script
#This script is written and maintained by Jaime Ibarra as a way to facilitate the installation process of Airspan ACP Software

#Makes sure script is not run while logged in as root.
if [ "$(id -u)" -eq 0 ]; then
    echo "Please run this script on a different user"
    # Place your action for the root user here
fi

#Option Menu for selecting which NMS to install.
options=($(ls /home/$USER/ | grep -e InstallNMS))
if [ -z "$options" ]; then
        echo -e "\033[1;31mError: No NMS Install File Found in /home/$USER/\033[0m"
        exit 1
elif [ ${#options[@]} -eq 1 ]; then
        echo "Only one choice available: ${options[0]}"
        NMS="${options[0]}"
else
        PS3='Please enter your choice: '
        select NMS in "${options[@]}"
        do
                echo "you chose $NMS"
                break
        done
fi

#For CentOS 7 uncomment the lines below (29)
#sudo rpm -Uvh https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm 

#For CentOS 7 Comment out the line containing "rhel/8/mssql-server-2022.repo"(32) and uncomment the "rhel/7/mssql-server-2019.repo"(33)
sudo curl -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/8/mssql-server-2022.repo
#sudo curl -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/7/mssql-server-2019.repo

sudo yum install -y mssql-server
sudo yum install -y wget 
sudo yum install -y tar

echo -e "Enabling Firewall Rules"
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=443/tcp # HTTPS
sudo firewall-cmd --permanent --add-port=20-22/tcp # File transfer
sudo firewall-cmd --permanent --add-port=80/tcp # HTTP
sudo firewall-cmd --permanent --add-port=161-162/udp # SNMP
sudo firewall-cmd --permanent --add-port=123/udp # NTP
sudo firewall-cmd --permanent --add-port=30000-33999/tcp # Netconf and sFTP vRAN
sudo firewall-cmd --permanent --add-port=830/tcp # Netconf vRAN RU
sudo firewall-cmd --permanent --add-port=9060/tcp # xPU SNMP_TCP
sudo firewall-cmd --permanent --add-port=9060/udp # xPU SNMP_UDP
sudo firewall-cmd --reload
sudo systemctl restart firewalld
echo -e "Done"

sudo mkdir /var/opt/mssql/sql_sys/
sudo mkdir /var/opt/mssql/sql_backup/
sudo mkdir /var/opt/mssql/sql_data/
sudo mkdir /var/opt/mssql/sql_log/
sudo chown -R mssql:mssql /var/opt/mssql
sudo chown -R mssql:mssql /opt/mssql
sudo ls -ltr /var/opt/mssql

sudo /opt/mssql/bin/mssql-conf set filelocation.masterdatafile /var/opt/mssql/sql_sys/master.mdf

sudo /opt/mssql/bin/mssql-conf set filelocation.masterlogfile /var/opt/mssql/sql_sys/mastlog.ldf

sudo systemctl stop mssql-server

echo -e "\033[1;35mEnter a password for SQL Server: (Password must be 8 characters long contain 1 of each [A-Z],[a-z],[0-9],[!,$,#,%])\033[0m"
while true; do
        read sa_password
        if [[ "$sa_password" =~ [A-Z] && "$sa_password" =~ [a-z] && "$sa_password" =~ [0-9] && "$sa_password" =~ [!\$\#%] ]]; then
            echo -e "\033[1;32mPassword is valid.\033[0m"
            break
        else
            echo -e '\033[1;31mPassword is invalid.\033[0m'
            echo -e '\033[1;31mPassword must be 8 characters long contain 1 of each [A-Z],[a-z],[0-9],[!,$,#,%]\033[0m'
        fi
done
echo "$sa_password" > /home/$USER/acp_info.txt
sudo ACCEPT_EULA='Y' MSSQL_PID='Express' MSSQL_SA_PASSWORD="$sa_password" MSSQL_LCID='1033' MSSQL_BACKUP_DIR='/var/opt/mssql/sql_backup' MSSQL_DATA_DIR='/var/opt/mssql/sql_data' MSSQL_LOG_DIR='/var/opt/mssql/sql_log' /opt/mssql/bin/mssql-conf setup

sudo systemctl start mssql-server
sudo systemctl enable mssql-server

sudo yum install -y aspnetcore-runtime-3.1 dotnet-runtime-3.1 aspnetcore-runtime-6.0 dotnet-runtime-6.0
sudo dotnet --list-runtimes

wget -O helm_install.tar.gz https://get.helm.sh/helm-v3.10.1-linux-amd64.tar.gz
tar -xvf helm_install.tar.gz
cd linux-amd64
sudo cp helm /usr/local/bin/

sudo mkdir /home/$USER/nmsinstall
sudo chmod 777 /home/$USER/nmsinstall
cd /home/$USER/nmsinstall
cp /home/$USER/$NMS /home/$USER/nmsinstall/$NMS
sudo chmod 777 $NMS 
sudo ./$NMS install -s 127.0.0.1 -u sa -p $sa_password -a /opt/nms_data -d /var/opt/mssql/sql_data --start-services true --auto-services true --licence-agreed true



