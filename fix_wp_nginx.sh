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

echo "=== Fixing WordPress Nginx Configuration ==="

# Create Nginx configuration
echo "Creating new Nginx configuration..."
cat > "$NGINX_CONF" << EOF
# Main HTTPS server
server {
    # Ports to listen on
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    # Server name to listen for
    server_name ${DOMAIN} www.${DOMAIN};

    # Path to document root
    root ${WP_ROOT};

    # Paths to certificate files
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # File to be used as index
    index index.php;

    # Overrides logs defined in nginx.conf
    access_log /var/log/nginx/${DOMAIN}-access.log;
    error_log /var/log/nginx/${DOMAIN}-error.log;

    # SSL configuration
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Basic configuration
    client_max_body_size 500M;

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP handling with PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    # Cache static files
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires max;
        log_not_found off;
        add_header Cache-Control "public, no-transform";
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

# Create required directories
echo "Creating log directories..."
sudo mkdir -p /var/log/nginx
sudo chown -R www-data:www-data /var/log/nginx

# Set correct permissions
echo "Setting permissions..."
sudo chown root:root "$NGINX_CONF"
sudo chmod 644 "$NGINX_CONF"

# Create symbolic link
echo "Creating symbolic link..."
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

# Remove default config
sudo rm -f /etc/nginx/sites-enabled/default

# Test configuration
echo "Testing Nginx configuration..."
if sudo nginx -t; then
    echo "Configuration test successful"
    sudo systemctl restart nginx
    echo "Nginx restarted"
else
    echo "Configuration test failed"
    exit 1
fi

echo "=== Fix complete ==="
echo "Your WordPress site should now be accessible at:"
echo "https://${DOMAIN}"
echo "https://www.${DOMAIN}" 