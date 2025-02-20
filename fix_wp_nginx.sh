#!/bin/bash

# Check if running with root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Get domain from parameter
if [ -z "$1" ]; then
    echo "Please provide domain name"
    echo "Usage: ./fix_wp_nginx.sh example.com"
    exit 1
fi

DOMAIN=$1
WP_ROOT="/var/www/${DOMAIN}"
NGINX_CONF="/etc/nginx/sites-available/wordpress"
PHP_VERSION="8.3"
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

echo "=== Fixing WordPress Configuration ==="

# 1. Fix PHP-FPM configuration
echo "Configuring PHP-FPM..."
sudo cp "$PHP_FPM_CONF" "${PHP_FPM_CONF}.backup"

# Update PHP-FPM configuration
sudo sed -i 's/^user = .*/user = www-data/' "$PHP_FPM_CONF"
sudo sed -i 's/^group = .*/group = www-data/' "$PHP_FPM_CONF"
sudo sed -i 's/^listen = .*/listen = \/run\/php\/php8.3-fpm.sock/' "$PHP_FPM_CONF"
sudo sed -i 's/^;listen.owner = .*/listen.owner = www-data/' "$PHP_FPM_CONF"
sudo sed -i 's/^;listen.group = .*/listen.group = www-data/' "$PHP_FPM_CONF"
sudo sed -i 's/^;listen.mode = .*/listen.mode = 0660/' "$PHP_FPM_CONF"

# 2. Create Nginx configuration
echo "Creating Nginx configuration..."
cat > "$NGINX_CONF" << EOF
# Main HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${WP_ROOT};
    index index.php;

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Logs
    access_log /var/log/nginx/${DOMAIN}-access.log;
    error_log /var/log/nginx/${DOMAIN}-error.log;

    # Global restrictions configuration
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # Deny all attempts to access hidden files
    location ~ /\. {
        deny all;
    }

    # WordPress single site rules
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Pass PHP scripts to PHP-FPM
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        
        # WordPress 重定向修復
        fastcgi_param HTTPS on;
        fastcgi_param HTTP_X_FORWARDED_PROTO https;
        fastcgi_param HTTP_X_FORWARDED_HOST \$http_host;
        
        # 增加緩衝和超時
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 600;
    }

    # WordPress admin 重定向修復
    location /wp-admin {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Cache static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires max;
        log_not_found off;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    location /.well-known/acme-challenge {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

# 3. Fix permissions
echo "Setting correct permissions..."
sudo chown -R www-data:www-data "$WP_ROOT"
sudo find "$WP_ROOT" -type d -exec chmod 755 {} \;
sudo find "$WP_ROOT" -type f -exec chmod 644 {} \;
sudo chmod 755 "$WP_ROOT"

# 4. Restart services
echo "Restarting services..."
sudo systemctl restart php${PHP_VERSION}-fpm
sudo systemctl restart nginx

# 5. Verify services
echo "Verifying services..."
echo "PHP-FPM status:"
sudo systemctl status php${PHP_VERSION}-fpm | grep "Active:"
echo "Nginx status:"
sudo systemctl status nginx | grep "Active:"

# 6. Create test PHP file
echo "Creating PHP test file..."
cat > "${WP_ROOT}/php-test.php" << EOF
<?php
phpinfo();
EOF
sudo chown www-data:www-data "${WP_ROOT}/php-test.php"

# Add WordPress configuration
echo "Adding WordPress configuration..."
WP_CONFIG="${WP_ROOT}/wp-config.php"

if [ -f "$WP_CONFIG" ]; then
    # Add SSL and site URL settings if not exists
    if ! grep -q "WP_HOME" "$WP_CONFIG"; then
        cat >> "$WP_CONFIG" << EOF

/* Fix for SSL and redirects */
define('FORCE_SSL_ADMIN', true);
define('WP_HOME', 'https://www.${DOMAIN}');
define('WP_SITEURL', 'https://www.${DOMAIN}');

/* Fix for reverse proxy and HTTPS */
if (strpos(\$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
    \$_SERVER['HTTPS'] = 'on';
    define('FORCE_SSL_ADMIN', true);
}

if (isset(\$_SERVER['HTTP_X_FORWARDED_HOST'])) {
    \$_SERVER['HTTP_HOST'] = \$_SERVER['HTTP_X_FORWARDED_HOST'];
}

/* Fix for login redirect */
define('ADMIN_COOKIE_PATH', '/');
define('COOKIEPATH', '/');
define('SITECOOKIEPATH', '/');
define('COOKIE_DOMAIN', '${DOMAIN}');

/* Fix for admin URLs */
define('WP_ADMIN_DIR', 'wp-admin');
define('ADMIN_COOKIE_PATH', SITECOOKIEPATH . WP_ADMIN_DIR);
EOF
    fi
fi

# Update WordPress URLs in database
echo "Updating WordPress URLs in database..."
if command -v wp > /dev/null; then
    cd "$WP_ROOT"
    wp option update home "https://www.${DOMAIN}" --allow-root
    wp option update siteurl "https://www.${DOMAIN}" --allow-root
fi

echo "=== Fix complete ==="
echo "Please test PHP at: https://${DOMAIN}/php-test.php"
echo "If successful, delete the test file with:"
echo "sudo rm ${WP_ROOT}/php-test.php"
echo
echo "Check these logs if you have issues:"
echo "tail -f /var/log/nginx/error.log"
echo "tail -f /var/log/php${PHP_VERSION}-fpm.log" 