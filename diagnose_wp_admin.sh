#!/bin/bash

DOMAIN=$1
WP_ROOT="/var/www/${DOMAIN}"

echo "=== WordPress Admin Diagnostic ==="

# Check PHP-FPM status
echo "Checking PHP-FPM..."
sudo systemctl status php8.3-fpm

# Check Nginx config
echo "Checking Nginx config..."
sudo nginx -t

# Check permissions
echo "Checking permissions..."
ls -la "${WP_ROOT}/wp-admin/"
ls -la "${WP_ROOT}/wp-includes/"

# Check wp-config.php
echo "Checking wp-config.php..."
grep -i "cookie" "${WP_ROOT}/wp-config.php"
grep -i "ssl" "${WP_ROOT}/wp-config.php"

# Check error logs
echo "Recent PHP errors:"
sudo tail -n 20 /var/log/php8.3-fpm.log

echo "Recent Nginx errors:"
sudo tail -n 20 /var/log/nginx/error.log

# Test wp-admin access
echo "Testing wp-admin access..."
curl -I "https://www.${DOMAIN}/wp-admin/" 