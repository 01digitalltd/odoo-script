#!/bin/bash

# Check if running with root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Get domain from parameter or ask for it
if [ -z "$1" ]; then
    echo "Please provide domain name"
    echo "Usage: ./fix_nginx_ssl.sh example.com"
    exit 1
fi

MAIN_DOMAIN=$1
WWW_DOMAIN="www.${MAIN_DOMAIN}"
ERP_DOMAIN="erp.${MAIN_DOMAIN}"

echo "=== Fixing Nginx and SSL Configuration ==="

# 1. Clean up existing configurations
echo "Cleaning up existing configurations..."
sudo rm -f /etc/nginx/conf.d/proxy-cache.conf
sudo sed -i '/proxy_cache_path/d' /etc/nginx/nginx.conf

# 2. Configure Nginx cache
echo "Configuring Nginx cache..."
sudo mkdir -p /var/cache/nginx
sudo chown www-data:www-data /var/cache/nginx
sudo sed -i '/http {/a \    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=STATIC:10m inactive=60m max_size=1g;' /etc/nginx/nginx.conf

# 3. Test and restart Nginx
echo "Testing and restarting Nginx..."
if sudo nginx -t; then
    sudo systemctl restart nginx
else
    echo "Nginx configuration test failed"
    exit 1
fi

# 4. Check if certbot is installed
echo "Checking certbot installation..."
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    sudo apt-get remove certbot
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
fi

# 5. Configure SSL
echo "Configuring SSL certificates..."
if sudo certbot --nginx \
    -d ${MAIN_DOMAIN} \
    -d ${WWW_DOMAIN} \
    -d ${ERP_DOMAIN} \
    --non-interactive \
    --agree-tos \
    --redirect; then
    echo "SSL configuration completed successfully"
else
    echo "SSL configuration failed"
    echo "Please check DNS settings and try again"
    exit 1
fi

# 6. Final check
echo "Performing final check..."
if sudo nginx -t; then
    sudo systemctl restart nginx
    echo "=== Fix completed successfully ==="
    echo "You can now access your sites at:"
    echo "https://${WWW_DOMAIN}"
    echo "https://${ERP_DOMAIN}"
else
    echo "Final configuration check failed"
    exit 1
fi 