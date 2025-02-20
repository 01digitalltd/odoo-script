#!/bin/bash

# 接收域名作為參數
if [ -z "$1" ]; then
    echo "請提供域名作為參數"
    echo "使用方法: ./install_wordpress.sh example.com"
    exit 1
fi

DOMAIN=$1
MAIN_DOMAIN=$DOMAIN
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
define('WP_HOME', 'https://${MAIN_DOMAIN}');
define('WP_SITEURL', 'https://${MAIN_DOMAIN}');

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

# 確保目錄存在
sudo mkdir -p ${WP_ROOT}
sudo mkdir -p ${WP_ROOT}/wp-content/uploads
sudo mkdir -p ${WP_ROOT}/wp-content/upgrade
sudo mkdir -p ${WP_ROOT}/wp-content/plugins
sudo mkdir -p ${WP_ROOT}/wp-content/themes

# 設置目錄擁有者
sudo chown -R www-data:www-data ${WP_ROOT}

# 設置基本權限
sudo find ${WP_ROOT} -type d -exec chmod 775 {} \;  # 修改為 775
sudo find ${WP_ROOT} -type f -exec chmod 664 {} \;  # 修改為 664

# 特殊目錄權限
sudo chmod 775 ${WP_ROOT}/wp-content
sudo chmod 775 ${WP_ROOT}/wp-content/themes
sudo chmod 775 ${WP_ROOT}/wp-content/plugins
sudo chmod 775 ${WP_ROOT}/wp-content/uploads
sudo chmod 775 ${WP_ROOT}/wp-content/upgrade

# wp-config.php 需要特殊權限
sudo chmod 660 ${WP_ROOT}/wp-config.php  # 修改為 660

# 添加當前用戶到 www-data 組
sudo usermod -a -G www-data ubuntu

# 確保 Nginx 用戶也在 www-data 組
sudo usermod -a -G www-data nginx

# 設置目錄的 SGID 位
sudo find ${WP_ROOT} -type d -exec chmod g+s {} \;

# 確保上傳目錄的權限
sudo chown -R www-data:www-data ${WP_ROOT}/wp-content/uploads
sudo chmod -R 775 ${WP_ROOT}/wp-content/uploads

# 設置正確的 PHP-FPM 配置
sudo bash -c "cat > /etc/php/8.3/fpm/pool.d/www.conf" << EOF
[www]
user = www-data
group = www-data
listen = /run/php/php8.3-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

# 重啟 PHP-FPM
sudo systemctl restart php8.3-fpm

# 重啟 Nginx
sudo systemctl restart nginx

# 驗證權限
echo "=== Verifying permissions ==="
ls -la ${WP_ROOT}
ls -la ${WP_ROOT}/wp-content
ls -la ${WP_ROOT}/wp-content/uploads

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
# Redirect www to non-www (HTTP only)
server {
    listen 80;
    listen [::]:80;
    server_name www.${MAIN_DOMAIN};

    # Redirect all www traffic to non-www HTTPS
    return 301 https://${MAIN_DOMAIN}\$request_uri;
}

# Main HTTP server
server {
    listen 80;
    listen [::]:80;
    server_name ${MAIN_DOMAIN};

    # Allow ACME challenge for SSL certification
    location /.well-known/acme-challenge {
        root /var/www/html;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${MAIN_DOMAIN};

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

    # Root directory and index files
    root ${WP_ROOT};
    index index.php index.html index.htm;

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

    # WordPress permalinks and main location
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP handling
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # FastCGI settings
        fastcgi_buffers 8 16k;
        fastcgi_buffer_size 32k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;

        # WordPress specific FastCGI settings
        fastcgi_param HTTPS on;
        fastcgi_param HTTP_X_FORWARDED_PROTO https;
        
        # Cookie and session handling
        fastcgi_intercept_errors on;
        fastcgi_hide_header X-Powered-By;
        fastcgi_param PHP_VALUE "session.cookie_httponly=1;session.cookie_secure=1;session.use_only_cookies=1";
    }

    # Deny access to sensitive files
    location ~ /\.(ht|git|env|config) {
        deny all;
    }

    # Deny access to wp-config.php
    location ~ ^/wp-config.php {
        deny all;
    }

    # Deny access to PHP files in the uploads directory
    location ~* /(?:uploads|files)/.*\.php\$ {
        deny all;
    }

    # Cache static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)\$ {
        expires max;
        log_not_found off;
        access_log off;
        add_header Cache-Control "public, no-transform";
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
    client_max_body_size 64M;
    
    # Prevent PHP execution in uploads directory
    location /wp-content/uploads/ {
        location ~ \.php$ {
            deny all;
        }
    }

    # Prevent direct access to .php files in wp-includes
    location ~* /wp-includes/.*\.php$ {
        deny all;
    }

    # Allow XML-RPC
    location /xmlrpc.php {
        limit_except POST {
            deny all;
        }
    }

    # WordPress admin area
    location /wp-admin {
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
            fastcgi_param HTTPS on;
            fastcgi_param HTTP_X_FORWARDED_PROTO https;
            fastcgi_buffer_size 128k;
            fastcgi_buffers 4 256k;
            fastcgi_busy_buffers_size 256k;
        }
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