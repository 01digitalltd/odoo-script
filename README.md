# Odoo 和 WordPress 一鍵安裝腳本

此腳本可以在 Ubuntu 服務器上一次性完成以下安裝：
- Odoo 18.0 ERP 系統 (erp.your-domain.com)
- WordPress 網站 (your-domain.com)
- Nginx 網站服務器
- SSL 證書自動配置

## 系統要求

- Ubuntu 24.04 LTS
- 至少 2GB RAM
- 至少 20GB 硬盤空間
- 域名已正確指向服務器 IP
- Root 或 Sudo 權限

## 快速安裝

```bash
# 1. 進入腳本目錄
cd ~/odoo-script

# 2. 設置執行權限
sudo chmod +x *.sh

# 3. 執行安裝（替換 your-domain.com 為你的實際域名）
sudo bash install_all.sh your-domain.com
```

安裝完成後：
- Odoo 訪問地址：https://erp.your-domain.com
- WordPress 訪問地址：https://your-domain.com

## 配置說明

### Odoo 配置
- 版本：18.0 社區版
- 端口：8069
- 數據庫：PostgreSQL
- 管理員密碼：自動生成（安裝時顯示）

### WordPress 配置
- 最新版本
- 數據庫：MySQL/MariaDB
- 數據庫信息：自動生成（安裝時顯示）

### Nginx 配置
- SSL：自動通過 Let's Encrypt 配置
- HTTP 自動跳轉 HTTPS
- 靜態文件緩存優化

## 重要提示

安裝完成後，請務必保存以下信息：
1. Odoo 數據庫管理密碼
2. WordPress 數據庫憑據
3. 所有管理員登錄信息

這些信息只會顯示一次，請安全保存。

## 故障排除

如果遇到執行權限問題，可以：

1. 檢查文件權限：
```bash
ls -l ~/odoo-script/*.sh
```

2. 重新設置權限：
```bash
cd ~/odoo-script
sudo chmod +x *.sh
```

3. 使用 bash 直接執行：
```bash
sudo bash install_all.sh your-domain.com
```

## 安全建議

1. 安裝完成後修改所有默認密碼
2. 定期備份數據庫
3. 及時更新系統和應用
4. 配置防火牆規則

## 技術支持

如有問題，請提交 Issue 或發送郵件至技術支持。

## 授權說明

本項目採用 MIT 授權。
