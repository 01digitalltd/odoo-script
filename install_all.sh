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

MAIN_DOMAIN=$1
ODOO_DOMAIN="erp.${MAIN_DOMAIN}"
WP_DOMAIN="${MAIN_DOMAIN}"
ADMIN_EMAIL="it@reformmktg.com"

echo "=== 開始安裝過程 ==="
echo "主域名: ${MAIN_DOMAIN}"
echo "Odoo 域名: ${ODOO_DOMAIN}"
echo "WordPress 域名: ${WP_DOMAIN}"

# 使腳本可執行
sudo chmod +x install_odoo_ubuntu.sh
sudo chmod +x install_wordpress.sh

# 修改 Odoo 安裝腳本中的域名和郵箱
sudo sed -i "s/WEBSITE_NAME=\".*\"/WEBSITE_NAME=\"${ODOO_DOMAIN}\"/" install_odoo_ubuntu.sh
sudo sed -i "s/ADMIN_EMAIL=\".*\"/ADMIN_EMAIL=\"${ADMIN_EMAIL}\"/" install_odoo_ubuntu.sh

# 安裝 Odoo
echo "=== 開始安裝 Odoo ==="
sudo bash install_odoo_ubuntu.sh

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

# 記錄 WordPress 信息
sudo bash -c "cat >> $LOG_FILE" << EOF
=== WordPress 登錄信息 ===
網址：https://${WP_DOMAIN}
數據庫名：${DB_NAME}
數據庫用戶：${DB_USER}
數據庫密碼：${DB_PASS}
----------------------------------------
EOF

echo "============================================"
echo "安裝完成！"
echo "Odoo 訪問地址: https://${ODOO_DOMAIN}"
echo "WordPress 訪問地址: https://${WP_DOMAIN}"
echo "請查看各自的安裝日誌以獲取詳細信息"
echo "============================================"

# 設置日誌文件的最終權限
sudo chown root:root $LOG_FILE
sudo chmod 600 $LOG_FILE 