#!/bin/bash

DOWNLOAD_LINK_IP_MONITOR="https://raw.githubusercontent.com/liyewang/HomeNetService/master/ip_monitor.py"
crontab_path="/var/spool/cron/crontabs"
python3_path="/usr/bin/python3"
ip_monitor_path=`pwd`
PROXY=`export | grep -i http_proxy | cut -d '"' -f 2`

privilege_check() {
    # If you want to run as another user, please modify $UID to be owned by this user
    if [[ "$UID" -ne '0' ]]; then
        echo
        echo "ERROR: This script must be run as root!"
        exit 1
    else
        crontab_path="${crontab_path}/$USER"
    fi
}

install_cron() {
    apt update
    apt install cron -y
    systemctl enable cron
}

set_path() {
    echo "Note: Privilege issue may occur under /root path."
    read -p "Input installation path[${ip_monitor_path}]: " input
    if [ "${input}" != "" ]; then ip_monitor_path=${input}; fi
    if [ ! -d ${ip_monitor_path} ]; then
        mkdir ${ip_monitor_path}
    fi
}

ip_monitor_update() {
    echo "Downloading: $DOWNLOAD_LINK_IP_MONITOR"
    if ! curl -x ${PROXY} -L -H 'Cache-Control: no-cache' -o "${ip_monitor_path}/ip_monitor.py.new" "$DOWNLOAD_LINK_IP_MONITOR"; then
        if [[ ! -f "${ip_monitor_path}/ip_monitor.py" ]]; then
            echo "error: Download failed! Please check your network or try again."
            exit 1
        else
            echo "warning: Download failed! Use existing script instead."
        fi
    else
        if [ -f "${ip_monitor_path}/ip_monitor.py" ]; then
            mv "${ip_monitor_path}/ip_monitor.py"{,.old}
        fi
        install -m 700 "${ip_monitor_path}/ip_monitor.py.new" "${ip_monitor_path}/ip_monitor.py"
        rm "${ip_monitor_path}/ip_monitor.py.new"
    fi
}

ip_monitor_crontab() {
    if [ -f ${crontab_path} ]; then
        crontab_list=`cat ${crontab_path}`
        crontab_prev=`cat ${crontab_path} | grep 'ip_monitor'`
        crontab_update="* * * * * sudo ${python3_path} ${ip_monitor_path}/ip_monitor.py"
        if [ -z "${crontab_prev}" ]; then
            echo "${crontab_update}" >> ${crontab_path}
        else
            echo "${crontab_list/$crontab_prev/$crontab_update}" > ${crontab_path}
        fi
    else
        echo "${crontab_update}" >> ${crontab_path}
    chmod 600 ${crontab_path}
}

privilege_check
install_cron
set_path
ip_monitor_update
ip_monitor_crontab

echo "Success"
exit 0
