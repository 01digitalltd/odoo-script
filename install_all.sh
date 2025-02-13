#!/bin/bash

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

MAIN_DOMAIN=$1
ODOO_DOMAIN="erp.${MAIN_DOMAIN}"
WP_DOMAIN="${MAIN_DOMAIN}"
ADMIN_EMAIL="it@reformmktg.com"

echo "=== 開始安裝過程 ==="
echo "主域名: ${MAIN_DOMAIN}"
echo "Odoo 域名: ${ODOO_DOMAIN}"
echo "WordPress 域名: ${WP_DOMAIN}"

# 使腳本可執行
chmod +x install_odoo_ubuntu.sh
chmod +x install_wordpress.sh

# 修改 Odoo 安裝腳本中的域名和郵箱
sed -i "s/WEBSITE_NAME=\".*\"/WEBSITE_NAME=\"${ODOO_DOMAIN}\"/" install_odoo_ubuntu.sh
sed -i "s/ADMIN_EMAIL=\".*\"/ADMIN_EMAIL=\"${ADMIN_EMAIL}\"/" install_odoo_ubuntu.sh

# 首先安裝 Odoo
echo "=== 開始安裝 Odoo ==="
./install_odoo_ubuntu.sh

# 然後安裝 WordPress
echo "=== 開始安裝 WordPress ==="
./install_wordpress.sh ${WP_DOMAIN}

echo "============================================"
echo "安裝完成！"
echo "Odoo 訪問地址: https://${ODOO_DOMAIN}"
echo "WordPress 訪問地址: https://${WP_DOMAIN}"
echo "請查看各自的安裝日誌以獲取詳細信息"
echo "============================================" 