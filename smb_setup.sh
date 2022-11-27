#!/bin/bash

username="root"
path="/"

main() {
    privilege_check
    install_samba
    config
    echo "Success"
    exit 0
}

privilege_check() {
    # If you want to run as another user, please modify $UID to be owned by this user
    if [[ "$UID" -ne '0' ]]; then
        echo
        echo "ERROR: This script must be run as root!"
        exit 1
    fi
}

install_samba() {
    apt update
    apt install samba -y
}

config() {
    read -p "Input Admin Username[${username}]: " input
    if [ "${input}" != "" ]; then username=${input}; fi
    smbpasswd -a ${username}
    read -p "Input Sharing Path[${path}]: " input
    if [ "${input}" != "" ]; then path=${input}; fi
    if [ -f "/etc/samba/smb.conf" ]; then
        mv --backup=t /etc/samba/smb.conf{,.save}
    fi
    cat > /etc/samba/smb.conf<<-EOF
[global]
   workgroup = WORKGROUP
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   vfs objects = catia fruit streams_xattr
   fruit:nfs_aces = no

[HomeDrive]
   comment = HomeDrive Directories
   path = ${path}
   read only = no
   create mask = 0644
   directory mask = 0755
   admin users = ${username}
EOF
}

main
