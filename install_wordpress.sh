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

# 安裝必要的套件（只安裝 WordPress 特定需要的）
echo "=== 安裝 WordPress 必要套件 ==="
# 檢查是否已安裝 PHP-FPM
if ! dpkg -l | grep -q "php-fpm"; then
    sudo apt install -y php-fpm php-mysql php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip
fi

# 檢查是否已安裝 MariaDB
if ! dpkg -l | grep -q "mariadb-server"; then
    sudo apt install -y mariadb-server
fi

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

# 創建 Nginx 配置文件
echo "=== 配置 Nginx ==="
sudo cat > /etc/nginx/sites-available/${NGINX_CONF} <<EOF
# 默認伺服器塊 - 處理 IP 訪問
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

# 主域名和 www 配置
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

# 創建軟連接
sudo ln -s /etc/nginx/sites-available/${NGINX_CONF} /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

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