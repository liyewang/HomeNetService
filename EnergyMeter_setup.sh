#!/bin/bash

path="/root/EnergyMeter"
read -p "Press ENTER to confirm you put EnergyMeter into ${path} and configured it." input
if [ "${input}" = "" ]; then
    echo "[Unit]
Description=EnergyMeter Service
After=network.target nss-lookup.target

[Service]
Type=simple
Restart=always
RestartSec=5s
ExecStart=python ${path}/EnergyMeter.py

[Install]
WantedBy=multi-user.target" > \
        '/etc/systemd/system/EnergyMeter.service'
    mkdir -p '/etc/systemd/system/EnergyMeter.service.d'
    "rm" -f '/etc/systemd/system/EnergyMeter.service.d/EnergyMeter.conf'
    echo "[Service]
ExecStart=
ExecStart=python ${path}/EnergyMeter.py" > \
        '/etc/systemd/system/EnergyMeter.service.d/EnergyMeter.conf'
    systemctl daemon-reload
    systemctl enable EnergyMeter
    systemctl start EnergyMeter
    echo "EnergyMeter.service installed."
fi