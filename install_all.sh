#!/bin/bash

# 檢查是否以 root 權限運行
if [ "$EUID" -ne 0 ]; then 
    echo "請使用 sudo 運行此腳本"
    exit 1
fi

# 設置日期時間變量
INSTALL_DATE=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="installation_credentials_${INSTALL_DATE}.log"

# 創建並設置日誌文件權限
sudo touch $LOG_FILE
sudo chmod 600 $LOG_FILE  # 只有 root 可以讀寫

# 創建日誌
sudo bash -c "cat > $LOG_FILE" << EOF
=== 安裝信息日誌 ===
安裝日期：${INSTALL_DATE}
域名：${MAIN_DOMAIN}
----------------------------------------
EOF

# 檢查是否提供域名參數
if [ -z "$1" ]; then
    echo "請提供主域名作為參數"
    echo "使用方法: ./install_all.sh example.com"
    exit 1
fi

# 檢查必要的腳本文件是否存在
if [ ! -f "install_odoo_ubuntu.sh" ] || [ ! -f "install_wordpress.sh" ]; then
    echo "錯誤：找不到必要的安裝腳本文件"
    echo "請確保 install_odoo_ubuntu.sh 和 install_wordpress.sh 在當前目錄"
    exit 1
fi

# 添加域名檢查函數
check_domain() {
    local domain=$1
    echo "檢查域名 $domain 的 DNS 設置..."
    if ! host $domain > /dev/null 2>&1; then
        echo "警告: 域名 $domain 似乎未正確設置 DNS 記錄"
        echo "目前將使用 IP 訪問，等 DNS 生效後再設置 SSL"
        return 1
    fi
    return 0
}

# 在域名檢查函數後添加
wait_for_dns() {
    local domain=$1
    local max_attempts=5
    local attempt=1
    
    echo "等待 DNS 解析生效..."
    while [ $attempt -le $max_attempts ]; do
        if check_domain $domain; then
            echo "DNS 解析已生效"
            return 0
        fi
        echo "等待 30 秒後重試... (${attempt}/${max_attempts})"
        sleep 30
        attempt=$((attempt + 1))
    done
    return 1
}

# 設置域名
MAIN_DOMAIN=$1
ODOO_DOMAIN="erp.${MAIN_DOMAIN}"
WP_DOMAIN="www.${MAIN_DOMAIN}"  # 修改為 www 子域名

# 檢查 Nginx 配置
check_nginx_configs() {
    echo "檢查 Nginx 配置..."
    
    # 檢查並備份現有的 Nginx 配置
    if [ -f "/etc/nginx/sites-enabled/default" ]; then
        sudo mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup
    fi
    
    # 清理可能存在的舊配置
    sudo rm -f "/etc/nginx/sites-enabled/${MAIN_DOMAIN}"
    sudo rm -f "/etc/nginx/sites-enabled/odoo"
    sudo rm -f "/etc/nginx/sites-available/${MAIN_DOMAIN}"
    sudo rm -f "/etc/nginx/sites-available/odoo"
}

# 檢查域名 DNS 設置
DNS_OK=true
if ! check_domain $MAIN_DOMAIN || ! check_domain $ODOO_DOMAIN; then
    echo "是否等待 DNS 解析生效？(y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if wait_for_dns $MAIN_DOMAIN && wait_for_dns $ODOO_DOMAIN; then
            DNS_OK=true
        else
            echo "DNS 解析仍未生效，將跳過 SSL 配置"
            DNS_OK=false
        fi
    else
        DNS_OK=false
    fi
fi

ADMIN_EMAIL="it@reformmktg.com"

echo "=== 開始安裝過程 ==="
echo "主域名: ${MAIN_DOMAIN}"
echo "Odoo 域名: ${ODOO_DOMAIN}"
echo "WordPress 域名: ${WP_DOMAIN}"

# 在安裝前添加 Nginx 配置檢查
check_nginx_configs

# 使腳本可執行
sudo chmod +x install_odoo_ubuntu.sh
sudo chmod +x install_wordpress.sh

# 修改 Odoo 安裝腳本中的域名和郵箱
sudo sed -i "s/WEBSITE_NAME=\".*\"/WEBSITE_NAME=\"${ODOO_DOMAIN}\"/" install_odoo_ubuntu.sh
sudo sed -i "s/ADMIN_EMAIL=\".*\"/ADMIN_EMAIL=\"${ADMIN_EMAIL}\"/" install_odoo_ubuntu.sh

# 傳遞 DNS 狀態給安裝腳本
if [ "$DNS_OK" = true ]; then
    echo "=== 配置 SSL ==="
    # 確保 certbot 已安裝
    sudo apt-get remove certbot
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot

    # 設置 SSL 為啟用
    sudo sed -i "s/ENABLE_SSL=\".*\"/ENABLE_SSL=\"True\"/" install_odoo_ubuntu.sh
    
    # WordPress 安裝時啟用 SSL
    sudo bash install_wordpress.sh ${WP_DOMAIN} "ssl"
    
    # 安裝 Odoo
    sudo bash install_odoo_ubuntu.sh

    # SSL 配置
    echo "配置 SSL 證書..."
    # 為所有域名安裝 SSL
    sudo certbot --nginx \
        -d ${MAIN_DOMAIN} \
        -d www.${MAIN_DOMAIN} \
        -d erp.${MAIN_DOMAIN} \
        --non-interactive \
        --agree-tos \
        --email ${ADMIN_EMAIL}
else
    echo "DNS 未生效，暫時跳過 SSL 配置"
    sudo sed -i "s/ENABLE_SSL=\".*\"/ENABLE_SSL=\"False\"/" install_odoo_ubuntu.sh
    sudo bash install_wordpress.sh ${WP_DOMAIN} "no-ssl"
    sudo bash install_odoo_ubuntu.sh
    
    # 提供後續配置 SSL 的說明
    echo "請在 DNS 生效後運行以下命令配置 SSL："
    echo "sudo certbot --nginx -d ${WP_DOMAIN} -d www.${WP_DOMAIN}"
    echo "sudo certbot --nginx -d ${ODOO_DOMAIN}"
fi

# 記錄 Odoo 信息
sudo bash -c "cat >> $LOG_FILE" << EOF
=== Odoo 登錄信息 ===
網址：https://${ODOO_DOMAIN}
$(sudo grep "Password superadmin" /var/log/odoo_install.log)
數據庫用戶：odoo
----------------------------------------
EOF

# 安裝 WordPress
echo "=== 開始安裝 WordPress ==="
sudo bash install_wordpress.sh ${WP_DOMAIN}

# 獲取 WordPress 憑據
source /tmp/wp_env.sh

# 記錄 WordPress 信息
sudo bash -c "cat >> $LOG_FILE" << EOF
=== WordPress 登錄信息 ===
網址：https://${WP_DOMAIN}
數據庫名：${WP_DB_NAME}
數據庫用戶：${WP_DB_USER}
數據庫密碼：${WP_DB_PASS}
----------------------------------------
EOF

# 清理環境變量文件
sudo rm /tmp/wp_env.sh

echo "============================================"
echo "安裝完成！"
echo "Odoo 訪問地址: https://erp.${MAIN_DOMAIN}"
echo "WordPress 訪問地址: https://www.${MAIN_DOMAIN}"
echo "所有登錄信息已保存到：${LOG_FILE}"
echo "============================================"

# 設置日誌文件的最終權限
sudo chown root:root $LOG_FILE
sudo chmod 600 $LOG_FILE 

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

# 檢查所有需要的域名
echo "檢查 DNS 設置..."
check_dns $MAIN_DOMAIN
check_dns "www.${MAIN_DOMAIN}"
check_dns "erp.${MAIN_DOMAIN}" 