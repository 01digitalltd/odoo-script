#!/bin/bash

# 接收域名作為參數
if [ -z "$1" ]; then
    echo "請提供域名作為參數"
    echo "使用方法: ./install_wordpress.sh example.com"
    exit 1
fi

DOMAIN=$1
WP_ROOT="/var/www/${DOMAIN}"
DB_NAME=$(echo ${DOMAIN} | sed 's/[.-]//g')
DB_USER="${DB_NAME}_user"
DB_PASS=$(openssl rand -base64 12)

# 安裝必要的套件
echo "=== 安裝必要的套件 ==="
sudo apt update
sudo apt install -y php-fpm php-mysql php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip mariadb-server

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
sudo sed -i "s/database_name_here/${DB_NAME}/" ${WP_ROOT}/wp-config.php
sudo sed -i "s/username_here/${DB_USER}/" ${WP_ROOT}/wp-config.php
sudo sed -i "s/password_here/${DB_PASS}/" ${WP_ROOT}/wp-config.php

# 設置權限
sudo chown -R www-data:www-data ${WP_ROOT}
sudo chmod -R 755 ${WP_ROOT}

# 創建 Nginx 配置文件
echo "=== 配置 Nginx ==="
sudo cat > /etc/nginx/sites-available/${DOMAIN} <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${WP_ROOT};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
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

    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires max;
        log_not_found off;
    }
}
EOF

# 啟用網站配置
sudo ln -s /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 安裝 SSL 證書
echo "=== 安裝 SSL 證書 ==="
sudo certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}

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