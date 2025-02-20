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
DB_PASS="1234567890"
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
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost';"
sudo mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
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

# 在添加安全密鑰之後，添加以下配置
sudo bash -c "cat >> ${WP_ROOT}/wp-config.php" << EOF

/* SSL and Cookie Settings */
define('FORCE_SSL_ADMIN', true);
define('FORCE_SSL_LOGIN', true);
define('COOKIE_DOMAIN', false);
define('ADMIN_COOKIE_PATH', '/');
define('COOKIEPATH', '/');
define('SITECOOKIEPATH', '/');

/* Custom WP_HOME and WP_SITEURL */
define('WP_HOME', 'https://${WWW_DOMAIN}');
define('WP_SITEURL', 'https://${WWW_DOMAIN}');

/* Prevent file editing from WordPress admin */
define('DISALLOW_FILE_EDIT', true);

/* Memory limits */
define('WP_MEMORY_LIMIT', '256M');
define('WP_MAX_MEMORY_LIMIT', '512M');

EOF

# 檢查配置文件替換是否成功
echo "=== 驗證 WordPress 配置 ==="
if grep -q "database_name_here\|username_here\|password_here" ${WP_ROOT}/wp-config.php; then
    echo "錯誤：WordPress 配置文件未正確更新"
    exit 1
else
    echo "WordPress 配置文件更新成功"
fi

# 修改權限設置部分
echo "=== Setting up WordPress permissions ==="

# 設置目錄權限為 755
sudo find ${WP_ROOT} -type d -exec chmod 755 {} \;

# 設置文件權限為 644
sudo find ${WP_ROOT} -type f -exec chmod 644 {} \;

# 特殊目錄權限
sudo chmod 755 ${WP_ROOT}/wp-content
sudo chmod 755 ${WP_ROOT}/wp-content/themes
sudo chmod 755 ${WP_ROOT}/wp-content/plugins

# 可寫入目錄
sudo chmod 775 ${WP_ROOT}/wp-content/uploads
sudo chmod 775 ${WP_ROOT}/wp-content/upgrade

# wp-config.php 需要特殊權限
sudo chmod 600 ${WP_ROOT}/wp-config.php

# 設置正確的擁有者
sudo chown -R www-data:www-data ${WP_ROOT}

# 確保 uploads 目錄存在並設置正確權限
sudo mkdir -p ${WP_ROOT}/wp-content/uploads
sudo chown -R www-data:www-data ${WP_ROOT}/wp-content/uploads
sudo chmod 775 ${WP_ROOT}/wp-content/uploads

# 添加 .htaccess 文件保護
sudo bash -c "cat > ${WP_ROOT}/.htaccess" << EOF
# Protect wp-config.php
<files wp-config.php>
order allow,deny
deny from all
</files>

# Protect .htaccess
<files .htaccess>
order allow,deny
deny from all
</files>

# Disable directory browsing
Options -Indexes

# Protect sensitive files
<FilesMatch "^.*(error_log|wp-config\.php|php.ini|\.[hH][tT][aApP].*)$">
Order deny,allow
Deny from all
</FilesMatch>
EOF

sudo chown www-data:www-data ${WP_ROOT}/.htaccess
sudo chmod 644 ${WP_ROOT}/.htaccess

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
# HTTP server - redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${MAIN_DOMAIN} ${WWW_DOMAIN};

    # Allow ACME challenge for SSL certification
    location /.well-known/acme-challenge {
        root /var/www/html;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${MAIN_DOMAIN} ${WWW_DOMAIN};

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/${MAIN_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${MAIN_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Proxy settings
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;

    # Basic settings
    client_max_body_size 64M;
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    proxy_buffers 8 16k;
    proxy_buffer_size 32k;

    # Logs
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src * data: 'unsafe-eval' 'unsafe-inline'" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Main location
    location / {
        proxy_pass http://127.0.0.1:8080;  # WordPress 運行在本地 8080 端口
        proxy_redirect off;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)\$ {
        proxy_pass http://127.0.0.1:8080;
        proxy_cache_use_stale error timeout http_500 http_502 http_503 http_504;
        proxy_cache_valid 200 60m;
        proxy_cache_valid 404 1m;
        expires max;
        log_not_found off;
        access_log off;
        add_header Cache-Control "public, no-transform";
    }

    # PHP files handling
    location ~ \.php\$ {
        proxy_pass http://127.0.0.1:8080;
        proxy_intercept_errors on;
    }

    # Deny access to sensitive files
    location ~ /\.(ht|git|env|config) {
        deny all;
    }

    # Deny access to wp-config.php
    location ~ ^/wp-config.php {
        deny all;
    }

    # Deny access to PHP files in uploads directory
    location ~* /(?:uploads|files)/.*\.php\$ {
        deny all;
    }

    # Handle common files
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # WordPress specific settings
    location /wp-admin {
        proxy_pass http://127.0.0.1:8080;
        proxy_redirect off;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
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

# Create local WordPress Nginx configuration
echo "=== Creating local WordPress Nginx configuration ==="
sudo cat > /etc/nginx/sites-available/wordpress_local <<EOF
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    root ${WP_ROOT};
    index index.php index.html index.htm;

    # PHP handling
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        fastcgi_buffers 8 16k;
        fastcgi_buffer_size 32k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF

# Enable the local configuration
sudo ln -sf /etc/nginx/sites-available/wordpress_local /etc/nginx/sites-enabled/

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