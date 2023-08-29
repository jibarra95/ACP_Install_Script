#!/bin/bash
#This is not an official Airspan Script
#This script is written and maintained by Jaime Ibarra as a way to facilitate the installation process of CIR Software

#Description: This function checks for the locaiton of a file and moves it to /home/$USER
#Usecase: Moves registry.conf and docker-compose.yaml files if not in the right place.
move_to_home() {
    if [ -f "$1" ]; then
        if [ "$PWD/$1" != "/home/$USER/$1" ]; then
            mv "$1" "/home/$USER/"
            #echo "Moved $1 to /home/$USER/"
        fi
    else
        echo "$1 does not exist."
        exit 1
    fi
}


#Makes sure script is not run while logged in as root.
if [ "$(id -u)" -eq 0 ]; then
    echo "Please run this script on a different user"
    # Place your action for the root user here
fi

move_to_home "docker-compose.yaml"
move_to_home "registry.conf"

cd /home/$USER/
###################################################################
#INSTALL PACKAGES
###################################################################
sudo yum -y install net-tools httpd-tools yum-utils nano tar wget

#Comment out centos link if using on rhel.
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
#sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

sudo yum -y install docker-ce docker-ce-cli containerd.io
sudo groupadd docker
sudo usermod -aG docker $USER

sudo systemctl enable docker

wget https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-linux-x86_64
cp docker-compose-linux-x86_64 docker-compose

sudo cp docker-compose /usr/bin/
sudo chmod +x /usr/bin/docker-compose
sudo chown $USER:$USER /usr/bin/docker-compose docker-compose
###################################################################
#FIREWALL RULES
###################################################################
echo -e "Enabling Firewall Rules"
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=20-22/tcp
sudo firewall-cmd --reload
sudo systemctl restart firewalld
echo -e "Done"

###################################################################
#CONFIGURE CIR
###################################################################
#echo -e "\033[1;33m***************************************\n|-Please enter an FQDN to use for CIR-|\n|     <hostname.domain-name.com>      |\n***************************************\033[0m"
echo -e "\033[1;33m ------------------------------------- \n| Please enter an FQDN to use for CIR |\n|     <hostname.domain-name.com>      |\n ------------------------------------- \033[0m"
read cirfqdn

mkdir -p ~/{workspace/sslca,registry/{auth,nginx/{conf.d,ssl}}}
sudo mkdir -p /etc/docker/certs.d/$cirfqdn/
sudo mkdir -p /usr/share/ca-certificates/extra/

cd ~/workspace/sslca
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -sha512 -days 3650 -subj "/CN=$cirfqdn" -key ca.key -out ca.crt
openssl genrsa -out $cirfqdn.key 4096
openssl req -sha512 -new -subj "/CN=$cirfqdn" -key $cirfqdn.key -out $cirfqdn.csr

cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=$cirfqdn
EOF

openssl x509 -req -sha512 -days 3650 -extfile v3.ext -CA ca.crt -CAkey ca.key -CAcreateserial -in $cirfqdn.csr -out $cirfqdn.crt
openssl x509 -inform PEM -in $cirfqdn.crt -out $cirfqdn.cert

sudo cp $cirfqdn.key ~/registry/nginx/ssl/
sudo cp $cirfqdn.crt ~/registry/nginx/ssl/

sudo cp $cirfqdn.cert /etc/docker/certs.d/$cirfqdn/
sudo cp $cirfqdn.key /etc/docker/certs.d/$cirfqdn/
sudo cp ca.crt /etc/docker/certs.d/$cirfqdn/

sudo cp ca.crt /usr/share/ca-certificates/extra/
sudo systemctl restart docker


while true; do
    if [ -f "/home/$USER/docker-compose.yaml" ] && [ -f "/home/$USER/registry.conf" ]; then
        echo "Both files found in $directory."
        break
    else
        echo -e "\033[1;33mPlace the registry.conf and docker-compose.yaml files in the /home/$USER directory\033[0m"
        read -p "Press Enter to continue..."
    fi
done

sudo sed -i "s/<hostname.domain-name.com>/$cirfqdn/g" "/home/$USER/registry.conf"

sudo mv /home/$USER/docker-compose.yaml ~/registry/

#echo -e "\033[1;33m**********************\n|   Create CirUser   |\n**********************\033[0m"
echo -e "\033[1;33m -------------------- \n|   Create CirUser   |\n -------------------- \033[0m"
read -p "Username:" ciruser


cd ~/registry
sudo chown $USER:$USER *.yaml
cd ~/registry/auth && htpasswd -Bc registry.passwd $ciruser
sudo mv /home/$USER/registry.conf ~/registry/nginx/conf.d/

cd ~/registry/

if [ "$cirfqdn" = "$(cat /etc/hostname)" ]; then
    echo "Hostname is correct."
else
    sudo hostnamectl set-hostname "$cirfqdn"
fi

sudo docker-compose up -d

###################################################################
#Verify CIR Login Works
###################################################################
echo -e "\033[1;33m ------------------- \n|   Log in to CIR   |\n ------------------- \033[0m"
sudo docker login $cirfqdn


#echo -e '\033[1;33mTake the docker-compose.yaml file provided by Airspan and place it in the ~/registry/ directory\033[0m'
