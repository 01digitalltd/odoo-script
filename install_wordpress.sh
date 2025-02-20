#!/bin/bash

# 接收域名作為參數
if [ -z "$1" ]; then
    echo "請提供域名作為參數"
    echo "使用方法: ./install_wordpress.sh example.com"
    exit 1
fi

DOMAIN=$1
MAIN_DOMAIN=$DOMAIN
WWW_DOMAIN="www.${DOMAIN}"
WP_ROOT="/var/www/${DOMAIN}"
DB_NAME=$(echo ${DOMAIN} | sed 's/[.-]//g')
DB_USER="${DB_NAME}_user"
DB_PASS=$(openssl rand -base64 12)
NGINX_CONF="wordpress"  # 使用固定的配置文件名

# 創建環境變量文件
sudo bash -c "cat > /tmp/wp_env.sh" << EOF
export WP_DB_NAME="${DB_NAME}"
export WP_DB_USER="${DB_USER}"
export WP_DB_PASS="${DB_PASS}"
EOF

# Install required packages
echo "=== Installing WordPress Requirements ==="
# Add PHP repository
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update

# Install PHP and its extensions
if ! dpkg -l | grep -q "php8.3-fpm"; then
    sudo apt install -y php8.3-fpm \
        php8.3-mysql \
        php8.3-curl \
        php8.3-gd \
        php8.3-intl \
        php8.3-mbstring \
        php8.3-soap \
        php8.3-xml \
        php8.3-zip
fi

# Install MariaDB
if ! dpkg -l | grep -q "mariadb-server"; then
    # Add MariaDB repository
    sudo apt-get install -y apt-transport-https curl
    sudo curl -o /etc/apt/trusted.gpg.d/mariadb_release_signing_key.asc 'https://mariadb.org/mariadb_release_signing_key.asc'
    sudo sh -c "echo 'deb https://mirrors.xtom.com/mariadb/repo/10.11/ubuntu jammy main' > /etc/apt/sources.list.d/mariadb.list"
    sudo apt update
    sudo apt install -y mariadb-server
fi

# Secure MariaDB installation
echo "=== Securing MariaDB Installation ==="
sudo mysql_secure_installation << EOF

y
$DB_PASS
$DB_PASS
y
y
y
y
EOF

# 創建 WordPress 資料庫和用戶
echo "=== 創建資料庫和用戶 ==="
sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# 下載和解壓 WordPress
echo "=== 下載和安裝 WordPress ==="
sudo mkdir -p ${WP_ROOT}
cd /tmp
wget https://wordpress.org/latest.tar.gz
sudo tar xf latest.tar.gz
sudo cp -r wordpress/* ${WP_ROOT}/
sudo rm -rf wordpress latest.tar.gz

# 設置 WordPress 配置文件
echo "=== 配置 WordPress ==="
sudo cp ${WP_ROOT}/wp-config-sample.php ${WP_ROOT}/wp-config.php

# 替換數據庫配置
sudo sed -i "s/database_name_here/${DB_NAME}/" ${WP_ROOT}/wp-config.php
sudo sed -i "s/username_here/${DB_USER}/" ${WP_ROOT}/wp-config.php
sudo sed -i "s/password_here/${DB_PASS}/" ${WP_ROOT}/wp-config.php

# 添加安全密鑰
KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sudo sed -i "/put your unique phrase here/d" ${WP_ROOT}/wp-config.php
echo "${KEYS}" | sudo tee -a ${WP_ROOT}/wp-config.php > /dev/null

# 檢查配置文件替換是否成功
echo "=== 驗證 WordPress 配置 ==="
if grep -q "database_name_here\|username_here\|password_here" ${WP_ROOT}/wp-config.php; then
    echo "錯誤：WordPress 配置文件未正確更新"
    exit 1
else
    echo "WordPress 配置文件更新成功"
fi

# 設置權限
sudo chown -R www-data:www-data ${WP_ROOT}
sudo chmod -R 755 ${WP_ROOT}

# Install and configure Nginx if not installed
echo "=== Installing and configuring Nginx ==="
if ! command -v nginx &> /dev/null; then
    sudo apt update
    sudo apt install -y nginx
fi

# Create Nginx directories if they don't exist
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled

# Create Nginx configuration file
echo "=== Creating Nginx configuration ==="
sudo cat > /etc/nginx/sites-available/${NGINX_CONF} <<EOF
# Default server block - handle IP access
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    location /.well-known/acme-challenge {
        root /var/www/html;
    }
    
    location / {
        return 301 https://www.${MAIN_DOMAIN}\$request_uri;
    }
}

# Main domain and www configuration
server {
    listen 80;
    listen [::]:80;
    server_name ${MAIN_DOMAIN} ${WWW_DOMAIN};
    
    root ${WP_ROOT};
    index index.php index.html index.htm;

    location /.well-known/acme-challenge {
        root /var/www/html;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires max;
        log_not_found off;
        add_header Cache-Control "public, no-transform";
    }
}
EOF

# Create symbolic link and verify configuration
echo "=== Setting up Nginx configuration ==="
sudo ln -sf /etc/nginx/sites-available/${NGINX_CONF} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
echo "=== Testing and reloading Nginx ==="
sudo nginx -t && sudo systemctl reload nginx || {
    echo "Nginx configuration test failed"
    exit 1
}

# 輸出配置信息
echo "============================================"
echo "WordPress 安裝完成！"
echo "域名: ${DOMAIN}"
echo "數據庫名: ${DB_NAME}"
echo "數據庫用戶: ${DB_USER}"
echo "數據庫密碼: ${DB_PASS}"
echo "WordPress 目錄: ${WP_ROOT}"
echo "請保存好以上信息！"
echo "============================================" 