#!/bin/bash

############ Default Settings ############

# Certificate
cert_opt="1"
cert_dir="IPsec_Certs"
cert_CN="VPN Root CA"   # Common Name
cert_O="Home"           # Orgnization
cert_C="CN"             # Country
cert_pkcs12_gen="no"

# Authorization
username="username"
password="password"
psk="${password}"
xauth="${password}"

# Filter (iptables/firewall)
filter_opt="1"
snat="1"
interface="eth0"

# VPN (IPsec)
ip_peer="10.1.1.0/24"
dns1="223.5.5.5"
dns2="8.8.8.8"

##########################################

main() {
    if [ "$#" -eq '1' ]; then
        case "$1" in
            '--install')
                privilege_check
                os_ver
                settings
                install_strongswan
                install_cert
                config
                ;;
            '--config')
                privilege_check
                os_ver
                settings
                install_cert
                config
                ;;
            '--remove')
                apt purge strongswan strongswan-pki
                ;;
            '--help')
                help_info
                ;;
            *)
                echo "ERROR: Invalid option '$1'."
                help_info
                exit 1
                ;;
        esac
    else
        echo "ERROR: Argument error."
        help_info
        exit 1
    fi
    echo "Success"
    exit 0
}

help_info() {
    echo "Usage: $0 [--install | --config | --remove | --help]"
}

privilege_check() {
    # If you want to run as another user, please modify $UID to be owned by this user
    if [[ "$UID" -ne '0' ]]; then
        echo
        echo "ERROR: This script must be run as root!"
        exit 1
    fi
}

os_ver() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        system_str="0"
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        system_str="1"
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        system_str="1"
    elif grep -Eqi "Raspbian" /etc/issue || grep -Eq "Raspbian" /etc/*-release; then
        system_str="1"
    else
        echo "ERROR: This Script only support CentOS/Ubuntu/Debian"
        exit 1
    fi
}

settings() {
    echo
    echo "========== Configurations =========="
    echo
    echo "1. Address"
    set_addr
    echo
    echo "2. Certificate"
    set_cert
    echo
    echo "3. Authorization"
    set_auth
    echo
    echo "4. Filter"
    set_filter
    echo
    echo "========== Config Complete ========="
    echo
    read -p "Press ENTER to start. . ."
}

set_addr() {
    # Get public IP address of the server
    ip_public=`curl -s checkip.dyndns.com | cut -d ' ' -f 6  | cut -d '<' -f 1`
    if [ -z $ip_public ]; then
        ip_public=`curl -s ifconfig.me/ip`
    fi
    addr_public=$ip_public
    read -p "Input server public IP/domain[${addr_public}]: " input
    if [ "${input}" != "" ]; then addr_public=${input}; fi
    # Get local IP address of the server
    ip_local=`hostname -I | cut -d ' ' -f 1`
    read -p "Input primary DNS address[${dns1}]: " input
    if [ "${input}" != "" ]; then dns1=${input}; fi
    read -p "Input secondary DNS address[${dns2}]: " input
    if [ "${input}" != "" ]; then dns2=${input}; fi
}

set_cert() {
    echo "    1. Generate certificate"
    echo "    2. Import certificate"
    while :; do
        read -p "Please input an option[${cert_opt}]: " input
        if [ "${input}" != "" ]; then cert_opt=${input}; fi
        if [ "${cert_opt}" = "1" ]; then
            echo "Input certificate information:"
            read -p "Common Name[${cert_CN}]: " input
            if [ "${input}" != "" ]; then cert_CN=${input}; fi
            read -p "Organization[${cert_O}]: " input
            if [ "${input}" != "" ]; then cert_O=${input}; fi
            read -p "Country[${cert_C}]: " input
            if [ "${input}" != "" ]; then cert_C=${input}; fi
            echo
            read -p "Generate pkcs12[${cert_pkcs12_gen}]: " input
            if [ "${input}" != "" ]; then cert_pkcs12_gen=${input}; fi
            break
        elif [ "${cert_opt}" = "2" ]; then
            cert_path=`pwd`
            cert_path="${cert_path}/${cert_dir}"
            read -p "Input certificate path[${cert_path}]: " input
            if [ "${input}" != "" ]; then cert_path=${input}; fi
            break
        else
            echo "Unsupported option, please try again."
        fi
    done
}

set_auth() {
    read -p "Input Username[${username}]: " input
    if [ "${input}" != "" ]; then username=${input}; fi
    read -p "Input Password[${password}]: " input
    if [ "${input}" != "" ]; then password=${input}; fi
    read -p "Input PSK[${psk}]: " input
    if [ "${input}" != "" ]; then psk=${input}; fi
    read -p "Input XAuth[${xauth}]: " input
    if [ "${input}" != "" ]; then xauth=${input}; fi
}

set_filter() {
    if [ "${system_str}" = "0" ]; then
        echo "    1. Using iptables"
        echo "    2. Using firewall"
        read -p "Input an option[${filter_opt}]: " input
        if [ "${input}" != "" ]; then filter_opt=${input}; fi
    else
        echo "iptables:"
        echo
        filter_opt="1"
    fi
    if [ "${filter_opt}" = "1" ]; then
        ip address
        echo
        read -p "Select the interface listed above that connects the Internet[${interface}]: " input
        if [ "${input}" != "" ]; then interface=${input}; fi
        echo
        echo "    SNAT is faster but you must update the SNAT IP to the selected interface IP once it changed."
        echo "    1. Use SNAT"
        echo "    2. Use MASQUERADE"
        read -p "Input an option[${snat}]: " input
        if [ "${input}" != "" ]; then snat=${input}; fi
        if [ "${snat}" = "1" ]; then
            ip_snat=${ip_local}
            read -p "Input network interface IP address for SNAT[${ip_snat}]: " input
            if [ "${input}" != "" ]; then ip_snat=${input}; fi
        fi
    fi
}

install_strongswan() {
    apt update
    apt install strongswan strongswan-pki libcharon-extra-plugins libstrongswan-extra-plugins -y
    systemctl enable strongswan-starter
}

install_cert() {
    if [ "$cert_opt" = "1" ]; then
        if [ ! -d ${cert_dir} ]; then
            mkdir ${cert_dir}
        fi
        gen_ca_key
        gen_ca_cert
        gen_server_key
        gen_server_cert
        gen_client_key
        gen_client_cert
        gen_pkcs12_cert
    else
        while :; do
            if [ ! -f ${cert_path}/ca.pem ]; then
                opt=1
                echo "${cert_path}/ca.pem not found."
                echo "    1. Generate a new one."
                echo "    2. Try again."
                read -p "Please input an option[${opt}]: " input
                if [ "${input}" != "" ]; then opt=${input}; fi
                if [ "${opt}" = "1" ]; then
                    set_cert
                    gen_ca_key
                    gen_ca_cert
                    gen_server_key
                    gen_server_cert
                    gen_client_key
                    gen_client_cert
                    gen_pkcs12_cert
                else
                    continue
                fi
            elif [ ! -f ${cert_path}/ca.cert.pem ]; then
                opt=1
                echo "${cert_path}/ca.cert.pem not found."
                echo "    1. Generate a new one."
                echo "    2. Try again."
                read -p "Please input an option[${opt}]: " input
                if [ "${input}" != "" ]; then opt=${input}; fi
                if [ "${opt}" = "1" ]; then
                    set_cert
                    gen_ca_cert
                    gen_server_key
                    gen_server_cert
                    gen_client_key
                    gen_client_cert
                    gen_pkcs12_cert
                else
                    continue
                fi
            elif [ ! -f ${cert_path}/server.pem ]; then
                opt=1
                echo "${cert_path}/server.pem not found."
                echo "    1. Generate a new one."
                echo "    2. Try again."
                read -p "Please input an option[${opt}]: " input
                if [ "${input}" != "" ]; then opt=${input}; fi
                if [ "${opt}" = "1" ]; then
                    set_cert
                    gen_server_key
                    gen_server_cert
                    gen_client_key
                    gen_client_cert
                    gen_pkcs12_cert
                else
                    continue
                fi
            elif [ ! -f ${cert_path}/server.cert.pem ]; then
                opt=1
                echo "${cert_path}/server.cert.pem not found."
                echo "    1. Generate a new one."
                echo "    2. Try again."
                read -p "Please input an option[${opt}]: " input
                if [ "${input}" != "" ]; then opt=${input}; fi
                if [ "${opt}" = "1" ]; then
                    set_cert
                    gen_server_cert
                    gen_client_key
                    gen_client_cert
                    gen_pkcs12_cert
                else
                    continue
                fi
            elif [ ! -f ${cert_path}/client.pem ]; then
                opt=1
                echo "${cert_path}/client.pem not found."
                echo "    1. Generate a new one."
                echo "    2. Try again."
                read -p "Please input an option[${opt}]: " input
                if [ "${input}" != "" ]; then opt=${input}; fi
                if [ "${opt}" = "1" ]; then
                    set_cert
                    gen_client_key
                    gen_client_cert
                    gen_pkcs12_cert
                else
                    continue
                fi
            elif [ ! -f ${cert_path}/client.cert.pem ]; then
                opt=1
                echo "${cert_path}/client.cert.pem not found."
                echo "    1. Generate a new one."
                echo "    2. Try again."
                read -p "Please input an option[${opt}]: " input
                if [ "${input}" != "" ]; then opt=${input}; fi
                if [ "${opt}" = "1" ]; then
                    set_cert
                    gen_client_cert
                    gen_pkcs12_cert
                else
                    continue
                fi
            elif [ ! -f ${cert_path}/client.cert.p12 ]; then
                if [ "${cert_pkcs12_gen}" -ne "no" ]; then
                    opt=1
                    echo "${cert_path}/client.cert.p12 not found."
                    echo "    1. Generate a new one."
                    echo "    2. Try again."
                    read -p "Please input an option[${opt}]: " input
                    if [ "${input}" != "" ]; then opt=${input}; fi
                    if [ "${opt}" = "1" ]; then
                        set_cert
                        gen_pkcs12_cert
                    else
                        continue
                    fi
                fi
            else
                break
            fi
        done
    fi
    cp -f ${cert_path}/ca.cert.pem ${cert_path}/ca.cert.cer
    cp -f ${cert_path}/ca.cert.pem /etc/ipsec.d/cacerts/
    cp -f ${cert_path}/server.pem /etc/ipsec.d/private/
    cp -f ${cert_path}/server.cert.pem /etc/ipsec.d/certs/
    cp -f ${cert_path}/client.pem /etc/ipsec.d/private/
    cp -f ${cert_path}/client.cert.pem /etc/ipsec.d/certs/
    cat > ${cert_path}/cert_info<<-EOF
C=${cert_C}
O=${cert_O}
CN=${cert_CN}
ADDR=${addr_public}
EOF
}

# Creating a Certificate Authority
gen_ca_key() {
    ipsec pki --gen --outform pem > ${cert_path}/ca.pem
}

gen_ca_cert() {
    ipsec pki --self --ca --lifetime 36500 \
        --in ${cert_path}/ca.pem \
        --dn "C=${cert_C}, O=${cert_O}, CN=${cert_CN}" \
        --outform pem > ${cert_path}/ca.cert.pem
}

# Generating a certificate for the VPN Server
gen_server_key() {
    ipsec pki --gen --outform pem > ${cert_path}/server.pem
}

gen_server_cert() {
    ipsec pki --pub --in ${cert_path}/server.pem \
        | ipsec pki --issue --lifetime 3650 \
            --cacert ${cert_path}/ca.cert.pem \
            --cakey ${cert_path}/ca.pem \
            --dn "C=${cert_C}, O=${cert_O}, CN=${addr_public}" --san="${addr_public}" \
            --flag serverAuth --flag ikeIntermediate \
            --outform pem > ${cert_path}/server.cert.pem
}

# Generating a certificate for the VPN Client
gen_client_key() {
    ipsec pki --gen --outform pem > ${cert_path}/client.pem
}
gen_client_cert() {
    ipsec pki --pub --in ${cert_path}/client.pem \
        | ipsec pki --issue --lifetime 3650 \
            --cacert ${cert_path}/ca.cert.pem \
            --cakey ${cert_path}/ca.pem \
            --dn "C=${cert_C}, O=${cert_O}, CN=VPN Client" \
            --outform pem > ${cert_path}/client.cert.pem
}

# Generating a pkcs12 certificate for the VPN Client
gen_pkcs12_cert() {
    if [ "${cert_pkcs12_gen}" -ne "no" ]; then
        echo "Configure the pkcs12 certificate password(Can be empty)"
        openssl pkcs12 -export \
            -inkey ${cert_path}/client.pem \
            -in ${cert_path}/client.cert.pem \
            -name "client" \
            -certfile ${cert_path}/ca.cert.pem \
            -caname "${cert_CN}" \
            -out ${cert_path}/client.cert.p12
    fi
}

config() {
    config_strongswan
    config_ipsec
    config_secrets
    config_filter
}

# configure the strongswan.conf
config_strongswan() {
    if [ -f "/etc/strongswan.conf" ]; then
        mv --backup=t /etc/strongswan.conf{,.save}
    fi
    cat > /etc/strongswan.conf<<-EOF
# strongswan.conf - strongSwan configuration file
#
# Refer to the strongswan.conf(5) manpage for details
#
# Configuration changes should be made in the included files

charon {
	load_modular = yes
	plugins {
		include strongswan.d/charon/*.conf
	}
    dns1 = ${dns1}
    dns2 = ${dns2}
    nbns1 = ${dns1}
    nbns2 = ${dns2}
}

include strongswan.d/*.conf
EOF
}

# configure the ipsec.conf
config_ipsec() {
    if [ -f "/etc/ipsec.conf" ]; then
        mv --backup=t /etc/ipsec.conf{,.save}
    fi
    cat > /etc/ipsec.conf<<-EOF
# ipsec.conf - strongSwan IPsec configuration file

# basic configuration

# config setup
	# strictcrlpolicy=yes
	# uniqueids = no

# Add connections here.

# Sample VPN connections

#conn sample-self-signed
#      leftsubnet=10.1.0.0/16
#      leftcert=selfCert.der
#      leftsendcert=never
#      right=192.168.0.2
#      rightsubnet=10.2.0.0/16
#      rightcert=peerCert.der
#      auto=start

#conn sample-with-ca-cert
#      leftsubnet=10.1.0.0/16
#      leftcert=myCert.pem
#      right=192.168.0.2
#      rightsubnet=10.2.0.0/16
#      rightid="C=CH, O=Linux strongSwan CN=peer name"
#      auto=start

include /var/lib/strongswan/ipsec.conf.inc

config setup
    charondebug="all"
    uniqueids=never 

conn iOS_cert
    keyexchange=ikev1
    fragmentation=yes
    left=%defaultroute
    leftauth=pubkey
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=pubkey
    rightauth2=xauth
    rightsourceip=${ip_peer}
    rightcert=client.cert.pem
    auto=add

conn android_xauth_psk
    keyexchange=ikev1
    left=%defaultroute
    leftauth=psk
    leftsubnet=0.0.0.0/0
    right=%any
    rightauth=psk
    rightauth2=xauth
    rightsourceip=${ip_peer}
    auto=add

conn networkmanager-strongswan
    keyexchange=ikev2
    left=%defaultroute
    leftauth=pubkey
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=pubkey
    rightsourceip=${ip_peer}
    rightcert=client.cert.pem
    auto=add

conn ios_ikev2
    keyexchange=ikev2
    ike=aes256-sha256-modp2048,3des-sha1-modp2048,aes256-sha1-modp2048!
    esp=aes256-sha256,3des-sha1,aes256-sha1!
    rekey=no
    left=%defaultroute
    leftid=${addr_public}
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=${ip_peer}
    rightsendcert=never
    eap_identity=%any
    dpdaction=clear
    fragmentation=yes
    auto=add

conn windows7
    keyexchange=ikev2
    ike=aes256-sha1-modp1024!
    rekey=no
    left=%defaultroute
    leftauth=pubkey
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=${ip_peer}
    rightsendcert=never
    eap_identity=%any
    auto=add

EOF
}

# configure the ipsec.secrets
config_secrets() {
    if [ -f "/etc/ipsec.secrets" ]; then
        mv --backup=t /etc/ipsec.secrets{,.save}
    fi
    cat > /etc/ipsec.secrets<<-EOF
# This file holds shared secrets or RSA private keys for authentication.

# RSA private key for this host, authenticating it to any other host
# which knows the public part.

# this file is managed with debconf and will contain the automatically created private key
include /var/lib/strongswan/ipsec.secrets.inc


: RSA "server.pem"
: PSK "${psk}"
: XAUTH "${xauth}"
${username} %any : EAP "${password}"
EOF
}

config_filter() {
    while :; do
        if [ "${filter_opt}" = "1" ]; then
            config_iptables
            break
        elif [ "${filter_opt}" = "2" ]; then
            config_firewall
            break
        else
            echo "ERROR: Unsupported option (${filter_opt}), try again."
            set_filter
            continue
        fi
    done
}

config_iptables() {
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -s ${ip_peer}  -j ACCEPT
    iptables -A INPUT -i $interface -p esp -j ACCEPT
    iptables -A INPUT -i $interface -p udp --dport 500 -j ACCEPT
    iptables -A INPUT -i $interface -p udp --dport 4500 -j ACCEPT
    if [ "${snat}" = "1" ]; then
        iptables -t nat -A POSTROUTING -s ${ip_peer} -o $interface -j SNAT --to-source $ip_snat
    else
        iptables -t nat -A POSTROUTING -s ${ip_peer} -o $interface -j MASQUERADE
    fi
    if [ "$system_str" = "0" ]; then
        service iptables save
    else
        if [ -f "/etc/iptables.rules" ]; then
            mv --backup=t /etc/iptables.rules{,.save}
        fi
        iptables-save > /etc/iptables.rules
        cat > /etc/network/if-up.d/iptables<<-EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
        chmod +x /etc/network/if-up.d/iptables
    fi
}

# firewall set in CentOS7
config_firewall() {
    if ! systemctl is-active firewalld > /dev/null; then
        systemctl start firewalld
    fi
    firewall-cmd --permanent --add-service="ipsec"
    firewall-cmd --permanent --add-port=500/udp
    firewall-cmd --permanent --add-port=4500/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload
}

main "$@"
