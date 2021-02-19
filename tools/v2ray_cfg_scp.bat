@echo off

echo Press any key to update v2ray configuration. . .
pause>nul
set server_addr=192.168.1.100
set cfg_path=C:\config.json

scp "%cfg_path%" root@%server_addr%:/usr/local/etc/v2ray/config.json
ssh root@%server_addr% bash /root/chcfg.sh
pause
