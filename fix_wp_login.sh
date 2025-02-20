#!/bin/bash

# Check if running with root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Get domain from parameter
if [ -z "$1" ]; then
    echo "Please provide domain name"
    echo "Usage: ./fix_wp_login.sh example.com"
    exit 1
fi

DOMAIN=$1
WP_ROOT="/var/www/${DOMAIN}"

echo "=== WordPress Login Fix Tool ==="

# 1. Check PHP-FPM configuration
echo "Checking PHP-FPM configuration..."
PHP_FPM_CONF="/etc/php/8.3/fpm/pool.d/www.conf"
PHP_FPM_SERVICE="php8.3-fpm"

# Backup original config
sudo cp $PHP_FPM_CONF "${PHP_FPM_CONF}.backup"

# Update PHP-FPM configuration
echo "Updating PHP-FPM configuration..."
sudo sed -i 's/^user = .*/user = www-data/' $PHP_FPM_CONF
sudo sed -i 's/^group = .*/group = www-data/' $PHP_FPM_CONF
sudo sed -i 's/^listen = .*/listen = \/run\/php\/php8.3-fpm.sock/' $PHP_FPM_CONF
sudo sed -i 's/^;listen.owner = .*/listen.owner = www-data/' $PHP_FPM_CONF
sudo sed -i 's/^;listen.group = .*/listen.group = www-data/' $PHP_FPM_CONF
sudo sed -i 's/^;listen.mode = .*/listen.mode = 0660/' $PHP_FPM_CONF

# Update PHP-FPM settings
sudo sed -i 's/^pm = .*/pm = dynamic/' $PHP_FPM_CONF
sudo sed -i 's/^pm.max_children = .*/pm.max_children = 50/' $PHP_FPM_CONF
sudo sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' $PHP_FPM_CONF
sudo sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' $PHP_FPM_CONF
sudo sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 35/' $PHP_FPM_CONF

# 2. Fix permissions
echo "Fixing permissions..."
sudo chown -R www-data:www-data $WP_ROOT
sudo find $WP_ROOT -type d -exec chmod 755 {} \;
sudo find $WP_ROOT -type f -exec chmod 644 {} \;

# Make sure wp-content is writable
sudo chmod -R 775 ${WP_ROOT}/wp-content

# 3. Update wp-config.php
echo "Updating wp-config.php..."
if ! grep -q "FORCE_SSL_ADMIN" "${WP_ROOT}/wp-config.php"; then
    cat >> "${WP_ROOT}/wp-config.php" << EOF

/* Custom settings for SSL and cookies */
define('FORCE_SSL_ADMIN', true);
define('COOKIE_DOMAIN', '${DOMAIN}');
define('COOKIEPATH', '/');
define('SITECOOKIEPATH', '/');
define('ADMIN_COOKIE_PATH', '/');

/* Fix for reverse proxy */
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
}

/* WordPress debug mode */
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
EOF
fi

# 4. Check and fix Nginx configuration
echo "Checking Nginx configuration..."
NGINX_CONF="/etc/nginx/sites-available/wordpress"

# Verify PHP-FPM socket path
if ! grep -q "fastcgi_pass.*php8.3-fpm.sock" "$NGINX_CONF"; then
    echo "Updating PHP-FPM socket path in Nginx configuration..."
    sudo sed -i 's/fastcgi_pass.*/fastcgi_pass unix:\/run\/php\/php8.3-fpm.sock;/' "$NGINX_CONF"
fi

# 5. Restart services
echo "Restarting services..."
sudo systemctl restart $PHP_FPM_SERVICE
sudo systemctl status $PHP_FPM_SERVICE
sudo nginx -t && sudo systemctl restart nginx

# 6. Verify services
echo "Verifying services..."
echo "PHP-FPM status:"
sudo systemctl status $PHP_FPM_SERVICE | grep "Active:"
echo "Nginx status:"
sudo systemctl status nginx | grep "Active:"

# 7. Check PHP-FPM socket
if [ -S "/run/php/php8.3-fpm.sock" ]; then
    echo "PHP-FPM socket exists and is valid"
else
    echo "ERROR: PHP-FPM socket not found!"
fi

echo "=== Fix complete ==="
echo "Please try logging in again at https://${DOMAIN}/wp-admin/"
echo "If issues persist, check these logs:"
echo "PHP-FPM log: tail -f /var/log/php8.3-fpm.log"
echo "Nginx error log: tail -f /var/log/nginx/error.log"
echo "WordPress debug log: tail -f ${WP_ROOT}/wp-content/debug.log" 