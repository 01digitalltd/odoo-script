#!/bin/bash

################################################################################
# Odoo 18 Installation Script for Ubuntu 24.04 (could be used for other version too)
# Author: Henry Robert Muwanika
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# crontab -e
# 43 6 * * * certbot renew --post-hook "systemctl reload nginx"
# Make a new file:
# sudo nano install_odoo_ubuntu.sh
# Place this content in it and then make the file executable:
# sudo chmod +x install_odoo_ubuntu.sh
# Execute the script to install Odoo:
# ./install_odoo_ubuntu.sh
################################################################################

OE_USER="odoo"
OE_HOME="/opt/$OE_USER"
OE_HOME_EXT="/opt/$OE_USER/${OE_USER}-server"
# The default port where this Odoo instance will run under (provided you use the command -c in the terminal)
# Set to true if you want to install it, false if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Choose the Odoo version which you want to install. For example: 17.0, 16.0, 15.0 or 14.0. When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 14.0
OE_VERSION="18.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Installs postgreSQL V16 instead of defaults (e.g V16 for Ubuntu 24.04) - this improves performance
INSTALL_POSTGRESQL_SIXTEEN="True"
# Set this to True if you want to install Nginx!
INSTALL_NGINX="True"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
# Set the website name
WEBSITE_NAME="erp.example.com"
# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
LONGPOLLING_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="it@reformmktg.com"

#--------------------------------------------------
# Update and upgrade the system
#--------------------------------------------------
echo -e "=== Updating system packages ... ==="
sudo apt update 
sudo apt upgrade -y
sudo apt autoremove -y

#----------------------------------------------------
# SSH configuration is removed to maintain connection
#----------------------------------------------------
# echo "=== Disabling password authentication ... ==="
# sudo apt -y install openssh-server
# sudo sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
# sudo sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config 
# sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# sudo systemctl restart sshd

#--------------------------------------------------
# Setting up the timezones
#--------------------------------------------------
# set the correct timezone on ubuntu
timedatectl set-timezone Asia/Hong_Kong
timedatectl

#--------------------------------------------------
# Installing PostgreSQL Server
#--------------------------------------------------
echo -e "=== Install and configure PostgreSQL ... ==="
if [ $INSTALL_POSTGRESQL_SIXTEEN = "True" ]; then
    echo -e "=== Installing postgreSQL V16 due to the user it's choice ... ==="
    sudo apt -y install postgresql-16
else
    echo -e "=== Installing the default postgreSQL version based on Linux version ... ==="
    sudo apt -y install postgresql postgresql-server-dev-all
fi

echo "=== Starting PostgreSQL service... ==="
sudo systemctl start postgresql 
sudo systemctl enable postgresql

echo -e "=== Creating the Odoo PostgreSQL User ... ==="
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

#--------------------------------------------------
# Installing required packages
#--------------------------------------------------
echo "=== Installing required packages... ==="
sudo apt install -y git wget python3-minimal python3-dev python3-pip python3-wheel libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev build-essential \
libssl-dev libffi-dev libmysqlclient-dev libjpeg-dev libpq-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev libzip-dev python3-setuptools node-less \
python3-venv python3-cffi gdebi zlib1g-dev curl cython3 python3-openssl

sudo pip3 install --upgrade pip --break-system-packages
sudo pip3 install setuptools wheel --break-system-packages

# Installing xfonts dependencies for wkhtmltopdf
echo "=== Installing xfonts for wkhtmltopdf... ==="
sudo apt -y install xfonts-75dpi xfonts-encodings xfonts-utils xfonts-base fontconfig

# Install Node.js and npm
echo "=== Installing Node.js and npm ... ==="
sudo apt -y install nodejs npm

sudo ln -s /usr/bin/nodejs /usr/bin/node
sudo npm install -g less less-plugin-clean-css

# Install rtlcss for RTL support
echo "=== Installing rtlcss ... ==="
sudo npm install -g rtlcss

#--------------------------------------------------
# Install Wkhtmltopdf if needed
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo "=== Install wkhtmltopdf and place shortcuts on correct place for Odoo 18 ... ==="
  sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb 
  sudo apt install ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb
  sudo cp /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
  sudo cp /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
   else
  echo "Wkhtmltopdf isn't installed due to the choice of the user!"
  fi

# Create Odoo system user
echo "=== Create Odoo system user ==="
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'Odoo' --group $OE_USER

#The user should also be added to the sudo'ers group.
sudo adduser $OE_USER sudo

echo -e "=== Create Log directory ... ==="
sudo mkdir /var/log/$OE_USER
sudo chown -R $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Install Odoo from source
#--------------------------------------------------
echo "=== Cloning Odoo 18 from GitHub ... ==="
sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/
sudo pip3 install -r /$OE_HOME_EXT/requirements.txt --break-system-packages

if [ $IS_ENTERPRISE = "True" ]; then
    # Odoo Enterprise install!
    sudo pip3 install psycopg2-binary pdfminer.six
    
    echo "=== Create symlink for node ==="
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    

    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "============== WARNING ====================="
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \n need to be an offical Odoo partner and you need access to \n http://github.com/odoo/enterprise.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "============================================="
        echo " "
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    done

    echo -e "=== Added Enterprise code under $OE_HOME/enterprise/addons ==="
    echo -e "==== Installing Enterprise specific libraries ==="
    sudo -H pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
fi

# Create custom addons directory
echo "Creating custom addons directory..."
sudo mkdir $OE_HOME/custom
sudo mkdir $OE_HOME/custom/addons

echo "Creating enterprise addons directory..."
sudo mkdir $OE_HOME/enterprise
sudo mkdir $OE_HOME/enterprise/addons

echo "=== Setting permissions on home folder ==="
sudo chown -R $OE_USER:$OE_USER $OE_HOME/

# Create Odoo configuration file
echo "=== Creating Odoo configuration file ... ==="
sudo touch /etc/${OE_CONFIG}.conf

# Generate admin password
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    echo -e "\n========= Generating random admin password ==========="
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
    echo "Odoo admin password: ${OE_SUPERADMIN}" >> /var/log/odoo_install.log
fi

sudo cat <<EOF > /etc/${OE_CONFIG}.conf
[options]
admin_passwd = ${OE_SUPERADMIN}
db_host = False
db_port = False
db_user = $OE_USER
db_password = False
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
addons_path = ${OE_HOME_EXT}/addons, ${OE_HOME}/custom/addons, ${OE_HOME}/enterprise/addons
http_port = ${OE_PORT}
xmlrpc_port = ${OE_PORT}
workers = 1
list_db = True
EOF

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

#--------------------------------------------------
# Creating systemd service file for Odoo
#--------------------------------------------------
echo "=== Creating systemd service file... ==="
sudo cat <<EOF > /lib/systemd/system/$OE_USER.service
[Unit]
Description=Odoo Open Source ERP and CRM
After=network.target

[Service]
Type=simple
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME_EXT/odoo-bin --config /etc/${OE_CONFIG}.conf  --logfile /var/log/${OE_USER}/${OE_CONFIG}.log
KillMode=mixed

[Install]
WantedBy=multi-user.target

EOF

sudo chmod 755 /lib/systemd/system/$OE_USER.service
sudo chown root: /lib/systemd/system/$OE_USER.service

# Reload systemd and start Odoo service
echo "=== Reloading systemd daemon ... ==="
sudo systemctl daemon-reload

sudo systemctl enable --now $OE_USER.service
sudo systemctl start $OE_USER.service

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
echo "==== Installing nginx ... ===="
if [ $INSTALL_NGINX = "True" ]; then
    sudo apt install -y nginx
    sudo systemctl enable nginx

    # Add cache configuration to nginx.conf first
    sudo bash -c 'cat >> /etc/nginx/nginx.conf' << 'EOF'

# Cache configuration
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=STATIC:10m inactive=60m max_size=1g;
EOF

    # Create cache directory for Nginx
    sudo mkdir -p /var/cache/nginx
    sudo chown www-data:www-data /var/cache/nginx
    
    echo "==== Configuring nginx ... ===="
    cat <<EOF > /etc/nginx/sites-available/$OE_USER
# Odoo servers
upstream odoo {
    server 127.0.0.1:$OE_PORT;
}

upstream odoo-chat {
    server 127.0.0.1:$LONGPOLLING_PORT;
}

# HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${WEBSITE_NAME};

    location /.well-known/acme-challenge {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${WEBSITE_NAME};

    # Proxy settings
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    # Basic configuration
    client_max_body_size 500M;
    access_log /var/log/nginx/$OE_USER-access.log;
    error_log /var/log/nginx/$OE_USER-error.log;

    # Handle longpolling
    location /longpolling {
        proxy_pass http://odoo-chat;
    }

    # Handle / requests
    location / {
        proxy_redirect off;
        proxy_pass http://odoo;
    }

    # Cache static files
    location ~* /web/static/ {
        proxy_cache_use_stale error timeout http_500 http_502 http_503 http_504;
        proxy_buffering on;
        proxy_cache STATIC;
        proxy_cache_valid 200 60m;
        proxy_cache_valid 404 1m;
        proxy_pass http://odoo;
        expires 864000;
    }
}
EOF

    # Set up symbolic links
    sudo mv /etc/nginx/sites-available/$OE_USER /etc/nginx/sites-available/odoo
    sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo

    # Remove default config
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo rm -f /etc/nginx/sites-available/default

    # Set correct permissions
    sudo chown root:root /etc/nginx/sites-available/odoo
    sudo chmod 644 /etc/nginx/sites-available/odoo

    # Test and reload Nginx
    sudo nginx -t && sudo systemctl reload nginx

    sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
    echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/odoo"
else
    echo "===== Nginx isn't installed due to choice of the user! ========"
fi

# Final message
# Check Odoo service status
echo "Checking Odoo service status..."
sudo systemctl status $OE_USER
echo "========================================================================"
echo "Done! The odoo server is up and running. Specifications:"
echo "Port: $OE_PORT"
echo "User service: $OE_USER"
echo "User PostgreSQL: $OE_USER"
echo "Code location: $OE_USER"
echo "Addons folder: $OE_USER/$OE_CONFIG/addons/"
echo "Password superadmin (database): $OE_SUPERADMIN"
echo "start odoo service: sudo systemctl start $OE_USER"
echo "stop odoo service: sudo systemctl stop $OE_USER"
echo "Restart Odoo service: sudo systemctl restart $OE_USER"
echo "Odoo installation is complete. Access it at http://your-IP-address:8069"
echo "========================================================================"

if [ $INSTALL_NGINX = "True" ]; then
  echo "Nginx configuration file: /etc/nginx/sites-available/$OE_USER"
fi


