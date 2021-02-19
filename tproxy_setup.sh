#!/bin/bash

interface="eth0"

# If you want to run as another user, please modify $UID to be owned by this user
if [[ "$UID" -ne '0' ]]; then
    echo
    echo "ERROR: This script must be run as root!"
    exit 1
fi

# iptables config
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 127.0.0.1/32 -j RETURN
iptables -t mangle -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY -d 192.168.0.0/16 -p tcp -j RETURN
iptables -t mangle -A V2RAY -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A PREROUTING -j V2RAY

iptables -t mangle -N V2RAY_MASK
iptables -t mangle -A V2RAY_MASK -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY_MASK -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY_MASK -d 192.168.0.0/16 -p tcp -j RETURN
iptables -t mangle -A V2RAY_MASK -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
iptables -t mangle -A V2RAY_MASK -j RETURN -m mark --mark 0xff
iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1
iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -j V2RAY_MASK

# iptables save
if [ -f "/etc/iptables.rules" ]; then
    mv --backup=t /etc/iptables.rules{,.save}
fi
iptables-save > /etc/iptables.rules

# ip rule and ip route config
cat > /etc/network/if-up.d/tproxy<<-EOF
#!/bin/sh
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
EOF
chmod +x /etc/network/if-up.d/tproxy

# enable forward
if [ "`sysctl -p | grep -xc "net.ipv4.ip_forward = 1"`" = "0" ]; then
    cat net.ipv4.ip_forward=1 >> /etc/sysctl.conf
fi

# static gateway config
if [ "`grep -xc "interface ${interface}" /etc/dhcpcd.conf`" = "0" ]; then
    ip address
    echo
    read -p "Select the interface listed above that connects the Internet[${interface}]: " input
    if [ "${input}" != "" ]; then interface=${input}; fi
    echo
    read -p "Input the IP address of the router this device is connected to: " gateway
    if [ "${gateway}" != "" ]; then
        cat >> /etc/dhcpcd.conf<<-EOF
interface ${interface}
static routers=${gateway}
EOF
        echo "Gateway configuration changed, reboot to take effect."
    else
        echo "Please  manually configure the static gateway to the router this device is connected to."
    fi
else
    echo "Please  manually configure the static gateway to the router this device is connected to."
fi

echo 'Success'
exit 0
