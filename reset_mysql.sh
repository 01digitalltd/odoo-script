#!/bin/bash

# Check if running with root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Get domain from parameter or ask for it
if [ -z "$1" ]; then
    echo "Please provide domain name"
    echo "Usage: ./reset_mysql.sh example.com"
    exit 1
fi

DOMAIN=$1
DB_NAME=$(echo ${DOMAIN} | sed 's/[.-]//g')
DB_USER="${DB_NAME}_user"
DB_PASS=$(openssl rand -base64 12)

echo "=== MariaDB Database Reset Tool ==="
echo "Domain: ${DOMAIN}"
echo "Database Name: ${DB_NAME}"
echo "Database User: ${DB_USER}"
echo "New Password: ${DB_PASS}"

# Confirm before proceeding
read -p "This will reset the database and user. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 1
fi

# Check if MariaDB is running
echo "Checking MariaDB service..."
if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB service..."
    sudo systemctl start mariadb
fi

# Backup existing database if it exists
echo "Checking for existing database..."
if mariadb -e "use ${DB_NAME}" 2>/dev/null; then
    echo "Creating backup of existing database..."
    BACKUP_FILE="${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"
    mariadb-dump ${DB_NAME} > "${BACKUP_FILE}"
    echo "Backup created: ${BACKUP_FILE}"
fi

# Reset database and user
echo "Resetting database and user..."
mariadb <<EOF
-- Drop existing database and user
DROP DATABASE IF EXISTS ${DB_NAME};
DROP USER IF EXISTS '${DB_USER}'@'localhost';

-- Create new database and user
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Update WordPress config if it exists
WP_CONFIG="/var/www/${DOMAIN}/wp-config.php"
if [ -f "$WP_CONFIG" ]; then
    echo "Updating WordPress configuration..."
    sudo sed -i "s/define( *'DB_NAME', *'[^']*' *);/define( 'DB_NAME', '${DB_NAME}' );/" "$WP_CONFIG"
    sudo sed -i "s/define( *'DB_USER', *'[^']*' *);/define( 'DB_USER', '${DB_USER}' );/" "$WP_CONFIG"
    sudo sed -i "s/define( *'DB_PASSWORD', *'[^']*' *);/define( 'DB_PASSWORD', '${DB_PASS}' );/" "$WP_CONFIG"
fi

# Save credentials to a file
CREDS_FILE="mysql_credentials_${DOMAIN}.txt"
cat > "${CREDS_FILE}" << EOF
=== MariaDB Credentials ===
Domain: ${DOMAIN}
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Database Password: ${DB_PASS}
Backup File: ${BACKUP_FILE}
Reset Date: $(date)
========================
EOF

# Secure the credentials file
chmod 600 "${CREDS_FILE}"

echo "=== Reset Complete ==="
echo "New credentials saved to: ${CREDS_FILE}"
if [ -n "${BACKUP_FILE}" ]; then
    echo "Old database backed up to: ${BACKUP_FILE}"
fi
echo "Please update your application configuration if needed." 