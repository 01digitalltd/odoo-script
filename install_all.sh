#!/bin/bash

# 檢查域名參數
if [ -z "$1" ]; then
    echo "使用方法: $0 <domain>"
    echo "例如: $0 example.com"
    exit 1
fi

# 設置變量
MAIN_DOMAIN=$1
ODOO_DOMAIN="erp.${MAIN_DOMAIN}"
ADMIN_EMAIL="it@reformmktg.com"
LOG_FILE="/root/odoo_install.log"

# DNS 檢查變量
DNS_OK=false

# DNS 檢查函數
check_dns() {
    local domain=$1
    echo "檢查域名 $domain..."
    if host $domain > /dev/null 2>&1; then
        return 0
    else
        echo "警告: $domain DNS 未設置"
        return 1
    fi
}

# 檢查 DNS 設置
echo "檢查 DNS 設置..."
if check_dns "erp.${MAIN_DOMAIN}"; then
    DNS_OK=true
fi

echo "=== 開始安裝過程 ==="
echo "主域名: ${MAIN_DOMAIN}"
echo "Odoo 域名: ${ODOO_DOMAIN}"

# 使腳本可執行
sudo chmod +x install_odoo_ubuntu.sh

# 修改 Odoo 安裝腳本中的域名和郵箱
sudo sed -i "s/WEBSITE_NAME=\".*\"/WEBSITE_NAME=\"${ODOO_DOMAIN}\"/" install_odoo_ubuntu.sh
sudo sed -i "s/ADMIN_EMAIL=\".*\"/ADMIN_EMAIL=\"${ADMIN_EMAIL}\"/" install_odoo_ubuntu.sh

# 安裝 Odoo
echo "=== 開始安裝 Odoo ==="
sudo bash install_odoo_ubuntu.sh

# SSL setup function
setup_ssl() {
    echo "=== Installing and Configuring SSL for Odoo ==="
    
    # Install certbot if not present
    if ! command -v certbot &> /dev/null; then
        sudo apt-get remove certbot
        sudo snap install core
        sudo snap refresh core
        sudo snap install --classic certbot
        sudo ln -s /snap/bin/certbot /usr/bin/certbot
    fi

    # Configure SSL certificates
    if [ "$DNS_OK" = true ]; then
        echo "Configuring SSL certificates for Odoo..."
        
        # 停止 Nginx 服務（如果正在運行）
        if systemctl is-active --quiet nginx; then
            echo "Stopping Nginx service..."
            sudo systemctl stop nginx
        fi

        # 只為 Odoo 獲取證書
        sudo certbot certonly --nginx \
            -d erp.${MAIN_DOMAIN} \
            --non-interactive \
            --agree-tos \
            --email ${ADMIN_EMAIL}

        # 設置證書權限
        sudo mkdir -p /etc/letsencrypt/archive
        sudo mkdir -p /etc/letsencrypt/live
        
        # 設置目錄權限 - 確保 Nginx 可以讀取
        sudo chmod -R 755 /etc/letsencrypt
        sudo chown -R root:root /etc/letsencrypt
        
        # 特別設置 private key 的權限
        sudo find /etc/letsencrypt/archive -name "privkey*.pem" -exec chmod 640 {} \;
        sudo find /etc/letsencrypt/archive -name "privkey*.pem" -exec chown root:www-data {} \;
        sudo find /etc/letsencrypt/live -name "privkey*.pem" -exec chmod 640 {} \;
        sudo find /etc/letsencrypt/live -name "privkey*.pem" -exec chown root:www-data {} \;

        # 只配置 Odoo 的 SSL
        sudo certbot --nginx \
            -d erp.${MAIN_DOMAIN} \
            --non-interactive \
            --agree-tos \
            --redirect
        
        # 測試 Nginx 配置
        echo "Testing Nginx configuration..."
        if sudo nginx -t; then
            echo "Nginx configuration test passed"
            echo "Starting Nginx service..."
            sudo systemctl start nginx
            echo "SSL certificate configuration complete!"
        else
            echo "Nginx configuration test failed"
            echo "Please check the error messages above"
            exit 1
        fi
    else
        echo "DNS not propagated, skipping SSL setup"
        echo "Run the following when DNS is ready:"
        echo "sudo certbot --nginx -d erp.${MAIN_DOMAIN}"
    fi
}

# Configure SSL
setup_ssl

# 記錄 Odoo 信息
sudo bash -c "cat >> $LOG_FILE" << EOF
=== Odoo 登錄信息 ===
網址：https://${ODOO_DOMAIN}
$(sudo grep "Password superadmin" /var/log/odoo_install.log)
數據庫用戶：odoo
----------------------------------------
EOF

echo "============================================"
echo "安裝完成！"
echo "Odoo 訪問地址: https://erp.${MAIN_DOMAIN}"
echo "所有登錄信息已保存到：${LOG_FILE}"
echo "============================================"

# 設置日誌文件的最終權限
sudo chown root:root $LOG_FILE
sudo chmod 600 $LOG_FILE 