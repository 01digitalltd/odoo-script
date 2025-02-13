#!/bin/bash

# 在腳本開始處添加日期時間變量
INSTALL_DATE=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="installation_credentials_${INSTALL_DATE}.log"

# 在主域名後添加日誌文件創建
echo "=== 安裝信息日誌 ===" > $LOG_FILE
echo "安裝日期：${INSTALL_DATE}" >> $LOG_FILE
echo "域名：${MAIN_DOMAIN}" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

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

# 在執行 Odoo 安裝後添加
echo "=== Odoo 登錄信息 ===" >> $LOG_FILE
echo "網址：https://${ODOO_DOMAIN}" >> $LOG_FILE
grep "Password superadmin" /var/log/odoo_install.log >> $LOG_FILE
echo "數據庫用戶：odoo" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

# 然後安裝 WordPress
echo "=== 開始安裝 WordPress ==="
./install_wordpress.sh ${WP_DOMAIN}

# 在執行 WordPress 安裝後添加
echo "=== WordPress 登錄信息 ===" >> $LOG_FILE
echo "網址：https://${WP_DOMAIN}" >> $LOG_FILE
echo "數據庫名：${DB_NAME}" >> $LOG_FILE
echo "數據庫用戶：${DB_USER}" >> $LOG_FILE
echo "數據庫密碼：${DB_PASS}" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

echo "============================================"
echo "安裝完成！"
echo "Odoo 訪問地址: https://${ODOO_DOMAIN}"
echo "WordPress 訪問地址: https://${WP_DOMAIN}"
echo "請查看各自的安裝日誌以獲取詳細信息"
echo "============================================"

# 在腳本結束時
echo "所有登錄信息已保存到：${LOG_FILE}" 