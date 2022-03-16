#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import socket
import requests
import os
import re
import time
import smtplib
from email.mime.text import MIMEText
from email.header import Header
import yaml

# File Path
ip_monitor_path = os.path.dirname(os.path.abspath(__file__))
ip_store_path = f'{ip_monitor_path}/ip_address'
log_path = f'{ip_monitor_path}/ip_monitor.log'
cfg_file = f'{ip_monitor_path}/ip_monitor_cfg.yaml'
cert_path = '/root/IPsec_Certs'
cert_info_path = f'{cert_path}/cert_info'
ipsec_conf_path = '/etc/ipsec.conf'

# Mail Server
mail_host = 'smtp.qq.com'
mail_port = 465
mail_user = "username@qq.com"
mail_pass = "password"
# Mail Address
mail_from_addr = 'username@qq.com'
mail_to_addrs = ['destination@qq.com']
# Mail Content
mail_from = 'VPN Server <noreply@vpn.com>'
mail_subject = 'VPN Server Update'
mail_text = 'Error message.'

def log(msg):
    print(msg)
    t = time.strftime(r'%Y/%m/%d %H:%M:%S', time.localtime())
    try:
        with open(log_path, 'a') as fileObject:
            fileObject.write(f'{t}: {msg}\n')
    except:
        pass
    return

def ipsec_update():
    # Update cert_info
    try:
        with open(cert_info_path, 'r') as fileObject:
            fileStr = fileObject.read()
        searchObject = re.search(r'ADDR=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', fileStr)
        if searchObject:
            cert_addr_prev = searchObject.group(1)
        else:
            log('Get previous cert address failed.')
            raise RuntimeError('Key process failed.')
        fileStrUpdate = re.sub(cert_addr_prev, ip, fileStr)
        with open(cert_info_path, 'w') as fileObject:
            fileObject.write(fileStrUpdate)
    except:
        log('Update cert_info failed.')
        raise RuntimeError('Key process failed.')
    else:
        log('Update cert_info success.')
        # Extract cert_info
        cert_C = None
        searchObject = re.search(r'C=(.+)', fileStrUpdate)
        if searchObject:
            cert_C = searchObject.group(1)
        cert_O = None
        searchObject = re.search(r'O=(.+)', fileStrUpdate)
        if searchObject:
            cert_O = searchObject.group(1)
        addr_public = None
        searchObject = re.search(r'ADDR=(.+)', fileStrUpdate)
        if searchObject:
            addr_public = searchObject.group(1)
        # Check cert_info
        if cert_C and cert_O and addr_public:
            log('Extract cert_info success.')
        else:
            log('Extract cert_info failed.')
            raise RuntimeError('Key process failed.')

    # Update server.cert.pem
    try:
        os.system(f'ipsec pki --pub --in {cert_path}/server.pem \
            | ipsec pki --issue --lifetime 3650 \
                --cacert {cert_path}/ca.cert.pem \
                --cakey {cert_path}/ca.pem \
                --dn "C={cert_C}, O={cert_O}, CN={addr_public}" --san="{addr_public}" \
                --flag serverAuth --flag ikeIntermediate \
                --outform pem > {cert_path}/server.cert.pem')
        os.system(f'cp -f {cert_path}/server.cert.pem /etc/ipsec.d/certs/')
    except:
        log('Update server.cert.pem failed.')
        raise RuntimeError('Key process failed.')
    else:
        log('Update server.cert.pem success.')

    # Update ipsec.conf
    try:
        with open(ipsec_conf_path, 'r') as fileObject:
            fileStr = fileObject.read()
        fileStrUpdate = re.sub(cert_addr_prev, ip, fileStr)
        with open(ipsec_conf_path, 'w') as fileObject:
            fileObject.write(fileStrUpdate)
    except:
        log('Update ipsec.conf failed.')
        raise RuntimeError('Key process failed.')
    else:
        log('Update ipsec.conf success.')

    # Reload ipsec
    log('Reload ipsec.')
    os.system('systemctl daemon-reload')
    os.system('systemctl restart ipsec')
    return

if __name__ == '__main__':
    # Load config
    with open(cfg_file, 'r') as f:
        cfg = yaml.safe_load(f)
    # File Path
    cert_path = cfg.get('cert_path', cert_path)
    ipsec_conf_path = cfg.get('ipsec_conf_path', ipsec_conf_path)
    # Mail Server
    mail_host = cfg.get('mail_host', mail_host)
    mail_port = cfg.get('mail_port', mail_port)
    mail_user = cfg.get('mail_user', mail_user)
    mail_pass = cfg.get('mail_pass', mail_pass)
    # Mail Address
    mail_from_addr = cfg.get('mail_from_addr', mail_from_addr)
    mail_to_addrs = cfg.get('mail_to_addrs', mail_to_addrs)

    # Get current IP address
    try:
        socketObject = socket.create_connection(('ns1.dnspod.net', 6666))
        ip = socketObject.recv(16).decode('utf-8')
        socketObject.close()
    except:
        try:
            socketObject.close()
        except:
            pass
        try:
            ip = requests.get('http://checkip.dyndns.com', timeout=5).text.strip()
        except:
            try:
                ip = requests.get('http://ifconfig.me/ip', timeout=5).text.strip()
            except:
                ip = ''

    # Verify current IP address
    searchObject = re.search(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', ip)
    if searchObject:
        ip = searchObject.group()

        # Get previous IP address
        with open(ip_store_path, 'a+') as fileObject:
            fileObject.seek(0)
            ip_prev = fileObject.read()
        # Verify previous IP address
        searchObject = re.search(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', ip_prev)
        if searchObject:
            ip_prev = searchObject.group()
        else:
            log('Get previous IP address failed.')

        # Check IP address change
        if ip != ip_prev:
            log(f'IP address changed from [{ip_prev}] to [{ip}]')
            with open(ip_store_path, 'w') as fileObject:
                fileObject.write(ip)
            ipsec_update()

            # Mail IP address change message
            mail_text = f'New VPN Server IP address: {ip}'
            try:
                smtpObject = smtplib.SMTP_SSL(mail_host, mail_port)
                smtpObject.login(mail_user, mail_pass)
                for mail_to_addr in mail_to_addrs:
                    message = MIMEText(mail_text, 'plain', 'utf-8')
                    message['From'] = Header(mail_from, 'utf-8')
                    message['To'] =  Header('<' + mail_to_addr + '>', 'utf-8')
                    message['Subject'] = Header(mail_subject, 'utf-8')
                    smtpObject.sendmail(mail_from_addr, [mail_to_addr], message.as_string())
                    log(f'Mail to [{mail_to_addr}] sent.')
            except:
                log('Sending mail failed.')
            else:
                log('Sending mail success.')
            finally:
                smtpObject.quit()
        else:
            print(f'IP address [{ip}] unchanged.')
    else:
        log('Get IP address failed.')
