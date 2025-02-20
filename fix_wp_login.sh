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

# Fix permissions
echo "Fixing permissions..."
sudo chown -R www-data:www-data $WP_ROOT
sudo find $WP_ROOT -type d -exec chmod 755 {} \;
sudo find $WP_ROOT -type f -exec chmod 644 {} \;

# Add SSL and cookie settings to wp-config.php
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

# Restart services
echo "Restarting services..."
sudo systemctl restart php8.3-fpm
sudo systemctl restart nginx

echo "Fix complete. Please try logging in again."
echo "If issues persist, check the debug log:"
echo "tail -f ${WP_ROOT}/wp-content/debug.log" 