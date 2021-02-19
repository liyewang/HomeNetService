@echo off

echo Press any key to update v2ray app. . .
pause>nul
set server_addr=192.168.1.100
ssh root@%server_addr% bash /root/v2ray_update.sh
pause
