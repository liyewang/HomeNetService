#!/bin/bash

v2ray -test -config /usr/local/etc/v2ray/config.json
echo v2ray restart...
systemctl restart v2ray
sleep 3s
echo proxy test:
bash /root/proxy_test.sh
echo
systemctl status v2ray

