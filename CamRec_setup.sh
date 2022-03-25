#!/bin/bash

path="/root/CamRec"
read -p "Press ENTER to confirm you put CamRec into ${path} and configured it." input
if [ "${input}" = "" ]; then
    echo "[Unit]
Description=CamRec Service
After=network.target nss-lookup.target

[Service]
Type=simple
Restart=always
RestartSec=5s
ExecStart=python ${path}/CamRec.py

[Install]
WantedBy=multi-user.target" > \
        '/etc/systemd/system/CamRec.service'
    mkdir -p '/etc/systemd/system/CamRec.service.d'
    "rm" -f '/etc/systemd/system/CamRec.service.d/CamRec.conf'
    echo "[Service]
ExecStart=
ExecStart=python ${path}/CamRec.py" > \
        '/etc/systemd/system/CamRec.service.d/CamRec.conf'
    systemctl daemon-reload
    systemctl enable CamRec
    systemctl start CamRec
    echo "CamRec.service installed."
fi