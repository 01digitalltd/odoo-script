#!/bin/bash

# 檢查是否以 root 權限運行
if [ "$EUID" -ne 0 ]; then 
    echo "請使用 sudo 運行此腳本"
    exit 1
fi

# 檢查域名參數
if [ -z "$1" ]; then
    echo "請提供域名作為參數"
    echo "使用方法: sudo ./diagnose.sh example.com"
    exit 1
fi

DOMAIN=$1
ERP_DOMAIN="erp.${DOMAIN}"
WWW_DOMAIN="www.${DOMAIN}"

echo "=== 系統狀態檢查 ==="

# 檢查服務狀態
echo "1. 檢查服務狀態："
echo "Nginx 狀態："
systemctl status nginx | grep "Active:"
echo "Odoo 狀態："
systemctl status odoo | grep "Active:"

# 檢查端口
echo -e "\n2. 檢查端口使用情況："
netstat -tulpn | grep -E ':80|:443|:8069|:8072'

# 檢查 Nginx 配置
echo -e "\n3. 檢查 Nginx 配置："
nginx -t

# 檢查 SSL 證書
echo -e "\n4. 檢查 SSL 證書："
certbot certificates

# 檢查 DNS 解析
echo -e "\n5. 檢查 DNS 解析："
echo "主域名解析："
dig +short $DOMAIN
echo "www 解析："
dig +short $WWW_DOMAIN
echo "erp 解析："
dig +short $ERP_DOMAIN

# 檢查日誌文件
echo -e "\n6. 檢查最近的錯誤日誌："
echo "Nginx 錯誤日誌："
tail -n 5 /var/log/nginx/error.log
echo -e "\nOdoo 錯誤日誌："
tail -n 5 /var/log/odoo/odoo-server.log

# 檢查防火牆狀態
echo -e "\n7. 檢查防火牆狀態："
ufw status

# 顯示 Nginx 站點配置
echo -e "\n8. 檢查 Nginx 站點配置："
echo "WordPress 配置："
cat /etc/nginx/sites-enabled/$DOMAIN
echo -e "\nOdoo 配置："
cat /etc/nginx/sites-enabled/odoo

echo -e "\n=== 診斷完成 ==="
echo "如果需要更詳細的日誌，請運行："
echo "sudo tail -f /var/log/nginx/error.log"
echo "sudo tail -f /var/log/nginx/access.log"
echo "sudo tail -f /var/log/odoo/odoo-server.log" 