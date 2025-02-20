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
sudo sed -i 's/^listen = .*/listen = \/run\/php\/php-fpm.sock/' "$PHP_FPM_CONF"
sudo sed -i 's/^;listen.owner = .*/listen.owner = www-data/' "$PHP_FPM_CONF"
sudo sed -i 's/^;listen.group = .*/listen.group = www-data/' "$PHP_FPM_CONF"
sudo sed -i 's/^;listen.mode = .*/listen.mode = 0660/' "$PHP_FPM_CONF"

# 2. Create Nginx configuration
echo "Creating Nginx configuration..."
cat > "$NGINX_CONF" << 'EOF'
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

    # WordPress specific settings
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Handle PHP
    location ~ \.php$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS on;
    }

    # Cache static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires max;
        log_not_found off;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
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

# Replace domain and path
sed -i "s/\${DOMAIN}/$DOMAIN/g" "$NGINX_CONF"
sed -i "s/\${WP_ROOT}/${WP_ROOT//\//\\/}/g" "$NGINX_CONF"

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

echo "=== Fix complete ==="
echo "Please test PHP at: https://${DOMAIN}/php-test.php"
echo "If successful, delete the test file with:"
echo "sudo rm ${WP_ROOT}/php-test.php"
echo
echo "Check these logs if you have issues:"
echo "tail -f /var/log/nginx/error.log"
echo "tail -f /var/log/php${PHP_VERSION}-fpm.log" 