
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
docker-compose --version

echo -e "--Please enter an FQDN for the CIR--"
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

echo -e "--Create CirUser--"
read -p "Username:" ciruser

cd ~/registry/auth && htpasswd -Bc registry.passwd $ciruser

cat > ~/registry/nginx/conf.d/registry.conf <<-EOF
server {
    listen 443 ssl http2;
    server_name $cirfqdn;
    client_max_body_size 2000M;
    ssl_certificate /etc/nginx/ssl/$cirfqdn.crt;
    ssl_certificate_key /etc/nginx/ssl/$cirfqdn.key;

    # Log files for Debug
    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;

    location / {
        # Do not allow connections from docker 1.5 and earlier
        # docker pre-1.6.0 did not properly set the user agent on ping, catch "Go *" user agents
        if (\$http_user_agent ~ "^(docker\/1\.(3|4|5(?!\.[0-9]-dev))|Go ).*$" )  {
            return 404;
        }

        proxy_pass                          http://registry:5000;
        proxy_set_header  Host              \$http_host;
        proxy_set_header  X-Real-IP         \$remote_addr;
        proxy_set_header  X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header  X-Forwarded-Proto \$scheme;
        proxy_read_timeout                  900;
    }

}
EOF

echo -e '\033[1;33mTake the docker-compose.yaml file provided by Airspan and place it in the ~/registry/ directory\033[0m'
