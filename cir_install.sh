
sudo yum -y install net-tools httpd-tools yum-utils nano tar wget

sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 


# ********For RL and RHEL 8 remove the installed docker************
# yum remove -y docker*
# *****************************************************************
#*******In case of Firewall Enable*****************************
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=20-22/tcp
sudo firewall-cmd --reload
sudo systemctl restart firewalld
sudo firewall-cmd --list-all
#**************************************************************

sudo yum -y install docker-ce docker-ce-cli containerd.io
sudo groupadd docker
sudo usermod -aG docker $USER

#sudo systemctl status docker
#sudo systemctl status containerd
#sudo systemctl start docker
sudo systemctl enable docker


wget https://github.com/docker/compose/releases/download/v2.11.2/docker-compose-linux-x86_64
cp docker-compose-linux-x86_64 docker-compose

sudo cp docker-compose /usr/bin/
sudo chmod +x /usr/bin/docker-compose
sudo chown $USER:$USER /usr/bin/docker-compose docker-compose
#docker-compose --version

echo -e "--Please enter an FQDN for the CIR--\n---<hostname.domain-name.com>---"
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
#systemctl status docker


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

echo -e "*********************\n--Create CirUser--\n********************"
read -p "Username:" ciruser


cd ~/registry
sudo chown $USER:$USER *.yaml
sudo mv /home/$USER/registry.conf ~/registry/nginx/conf.d/
cd ~/registry/auth && htpasswd -Bc registry.passwd $ciruser

cd ~/registry/
sudo docker-compose up -d

sudo docker login $cirfqdn


#echo -e '\033[1;33mTake the docker-compose.yaml file provided by Airspan and place it in the ~/registry/ directory\033[0m'
