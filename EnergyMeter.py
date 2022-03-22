#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import requests
import random
import re
import time
import os
import sys
import smtplib
from email.mime.text import MIMEText
from email.header import Header
import threading
import socket
import yaml

# Energy Meter Config
meter_user = 'user'
meter_pass = 'pass'
#              Jan    Feb     Mar    Apr    May    Jun    Jul    Aug    Sep    Oct    Nov    Dec
price_tab = [0.805, 0.711, 0.8251, 0.711, 0.711, 0.711, 0.738, 0.738, 0.738, 0.711, 0.711, 0.711]
balance_low = -80
data_intv = 30
clock_offset = 1
power_max = 15
energy_err_max = 0.01

# Communication Config
host = 'localhost'
port = 12345
max_connect = 1
proxy = None

# File Path
energy_meter_path = os.path.dirname(os.path.abspath(__file__))
data_path = f'{energy_meter_path}/EnergyMeter'
log_path = f'{energy_meter_path}/EnergyMeter.log'
cfg_file = f'{energy_meter_path}/EnergyMeterCfg.yaml'

# Mail Server
mail_host = 'smtp.qq.com'
mail_port = 465
mail_user = "user@qq.com"
mail_pass = "pass"
# Mail Address
mail_from_addr = 'user@qq.com'
mail_to_addrs = ['dest@qq.com']
# Mail Content
mail_from = 'Energy Meter Server <noreply@energymeter.com>'
mail_subject = 'Energy Meter Low Balance'
mail_text = 'Error message.'

def log(msg):
    print(msg)
    t = time.strftime(r'%Y/%m/%d %H:%M:%S', time.localtime())
    try:
        with open(log_path, 'a') as f:
            f.write(f'{t}: {msg}\n')
    except:
        pass
    return

def login(meter_user, meter_pass):
    url_login = 'http://tzjz.acrel-eem.com/Ajax/UserLogin.ashx?Id=' + str(random.random()) + '&username=' + meter_user + '&password=' + meter_pass
    r = requests.get(url=url_login, proxies=proxy)
    return requests.utils.dict_from_cookiejar(r.cookies)

def get_balance(cookie):
    r = requests.get(url='http://tzjz.acrel-eem.com/Ajax/CheckUserLogin.ashx?Id=2', cookies=cookie, proxies=proxy)
    m = re.search(r'id="(.+?)"', r.text)
    cookie['InterID'] = requests.utils.quote(m.group(1))
    m = re.search(r'(-?\d+\.\d+)' + b'\xe5\x85\x83'.decode(), r.text)
    return float(m.group(1))

def get_energy(cookie):
    if not cookie['InterID']:
        get_balance(cookie)
    StartDate = time.strftime(r'%Y-%m-%d', time.localtime(time.time() - 24 * 3600))
    EndDate = time.strftime(r'%Y-%m-%d', time.localtime(time.time() + 24 * 3600))
    url_data = 'http://tzjz.acrel-eem.com/Ajax/CheckUserLogin.ashx?Id=7&StartDate=' + StartDate + '&EndDate=' + EndDate
    r = requests.get(url=url_data, cookies=cookie, proxies=proxy)
    m = re.search(r'(\d+\.\d+)' + b'\xe5\xba\xa6'.decode() + '</p>', r.text)
    return float(m.group(1))

def get_topup(cookie):
    r = requests.get(url='http://tzjz.acrel-eem.com/Ajax/CheckUserLogin.ashx?Id=6', cookies=cookie, proxies=proxy)
    m = re.findall(r'(\d+\.\d+)' + b'\xe5\x85\x83'.decode(), r.text)
    topup = 0
    for t in m:
        topup += float(t)
    return topup

def metering(balance, topup, energy_real):
    global tm, cost, cost_prev, energy, energy_prev, power, price_tab, power_max, data_intv, energy_err_max, clock_offset
    price = price_tab[time.localtime().tm_mon - 1]
    cost_delta = topup - balance - cost
    cost = topup - balance
    if price:
        energy_delta = cost_delta / price
        energy += energy_delta
    else:
        energy = energy_real
    # Calib energy and price
    if (time.localtime().tm_min - clock_offset) == 0:
        if abs(energy_real - energy) > energy_err_max and (energy_real - energy_prev) != 0:
            price = (cost - cost_prev) / (energy_real - energy_prev)
            if price:
                energy_delta = cost_delta / price
            else:
                energy_delta = (energy_real - energy_prev) * data_intv / 60
            energy = energy_real
        energy_prev = energy_real
        cost_prev = cost
    elif abs(energy_real - energy) > power_max * data_intv / 60:
        energy = energy_real
    # Calculate power
    t_delta = time.mktime(time.localtime()) - time.mktime(tm)
    if t_delta >= data_intv * 60 * 2:
        power = energy_delta * 3600 / t_delta
    elif energy_delta > 0 or t_delta > data_intv * 60:
        power = energy_delta * 60 / data_intv
    if power > power_max:
        power = 0
    return price

def balance_notify(balance):
    global mail_balance
    if balance <= mail_balance:
        mail_text = f'Low balance: {balance:.2f}'
        try:
            smtpObject = smtplib.SMTP_SSL(mail_host, mail_port)
            smtpObject.login(mail_user, mail_pass)
            for mail_to_addr in mail_to_addrs:
                message = MIMEText(mail_text, 'plain', 'utf-8')
                message['From'] = Header(mail_from, 'utf-8')
                message['To'] =  Header('<' + mail_to_addr + '>', 'utf-8')
                message['Subject'] = Header(mail_subject, 'utf-8')
                try:
                    smtpObject.sendmail(mail_from_addr, [mail_to_addr], message.as_string())
                except:
                    log(f'Mail to [{mail_to_addr}] blocked.')
                else:
                    log(f'Mail to [{mail_to_addr}] sent.')
        except:
            log('Sending mail failed.')
        else:
            mail_balance = int(balance / 10 - 1) * 10 
        finally:
            try:
                smtpObject.quit()
            except:
                pass
    elif balance > balance_low:
        mail_balance = balance_low

def comm_task():
    global s, msg
    while True:
        try:
            c = s.accept()[0]
            c.sendall(msg.encode())
            c.close()
        except:
            try:
                c.close()
            except:
                pass
            log('Send data failed.')
            time.sleep(1)

def comm_read():
    global host, port
    attempt = 5
    while attempt:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect((host, port))
            data = s.recv(256).decode()
            s.close()
            m = re.search(r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) (-?\d+) -?\d+\.\d{2} (\d+\.\d{2}) \d+\.\d{4} (\d+\.\d{3}) \d+\.\d{2}', data)
            print(m.group(0))
            break
        except:
            try:
                s.close()
            except:
                pass
            log(f'Read data failed ({attempt}).')
            attempt -= 1
            time.sleep(1)

if __name__ == '__main__':
    # Load config
    with open(cfg_file, 'r') as f:
        cfg = yaml.safe_load(f)
    # Energy Meter Config
    meter_user = cfg.get('meter_user', meter_user)
    meter_pass = cfg.get('meter_pass', meter_pass)
    price_tab = cfg.get('price_tab', price_tab)
    balance_low = cfg.get('balance_low', balance_low)
    data_intv = cfg.get('data_intv', data_intv)
    clock_offset = cfg.get('clock_offset', clock_offset)
    power_max = cfg.get('power_max', power_max)
    energy_err_max = cfg.get('energy_err_max', energy_err_max)
    # Communication Config
    host = cfg.get('host', host)
    port = cfg.get('port', port)
    max_connect = cfg.get('max_connect', max_connect)
    proxy = cfg.get('proxy', proxy)
    # Mail Server
    mail_host = cfg.get('mail_host', mail_host)
    mail_port = cfg.get('mail_port', mail_port)
    mail_user = cfg.get('mail_user', mail_user)
    mail_pass = cfg.get('mail_pass', mail_pass)
    # Mail Address
    mail_from_addr = cfg.get('mail_from_addr', mail_from_addr)
    mail_to_addrs = cfg.get('mail_to_addrs', mail_to_addrs)

    # Task selection
    if len(sys.argv) == 2:
        if sys.argv[1] == 'read':
            comm_read()
        exit()
    elif len(sys.argv) > 2:
        exit()
    # Init merter
    tm = time.localtime()
    energy_prev = 0
    cost_prev = 0
    energy = energy_prev
    cost = cost_prev
    power = 0
    mail_balance = balance_low
    cookie = {}
    msg = ''
    data_intv = round(data_intv)
    if data_intv <= 0:
        data_intv = 1
    # Get previous data
    try:
        with open(data_path, 'a+') as f:
            f.seek(0)
            data = f.read()
            # Verify previous data
            m = re.search(r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) (-?\d+) -?\d+\.\d{2} (\d+\.\d{2}) \d+\.\d{4} (\d+\.\d{3}) (\d+\.\d{2})', data)
            tm = time.strptime(m.group(1), r'%Y/%m/%d %H:%M:%S')
            mail_balance = int(m.group(2))
            cost = float(m.group(3))
            energy = float(m.group(4))
            power = float(m.group(5))
    except:
        log('Get previous data failed.')
    else:
        log('Get previous data success.')
    # Start tasks
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.bind((host, port))
        s.listen(max_connect)
        threading.Thread(target=comm_task).start()
    except:
        log('Task start failed.')
    else:
        log('Task start success.')
        # Main loop
        while True:
            if not cookie:
                try:
                    cookie = login(meter_user, meter_pass)
                except:
                    cookie = {}
                    log('Login failed.')
                else:
                    log('Login success.')
            while cookie:
                try:
                    balance = get_balance(cookie)
                    topup = get_topup(cookie)
                    energy_real = get_energy(cookie)
                except:
                    cookie = {}
                    break
                else:
                    price = metering(balance, topup, energy_real)
                    balance_notify(balance)
                    tm = time.localtime()
                    t = time.strftime(r'%Y/%m/%d %H:%M:%S', tm)
                    msg = f'{t} {mail_balance} {balance:.2f} {cost:.2f} {price:.4f} {energy:.3f} {power:.2f}'
                    try:
                        with open(data_path, 'w') as f:
                            f.write(msg)
                    except:
                        pass
                    print(f'{t}: {mail_balance:4d} CNY {balance:7.2f} CNY, {cost:8.2f} CNY, {price:6.4f} CNY/kWh, {energy:9.3f} kWh, {energy_real:8.2f} kWh, {power:5.2f} kW')
                    while time.localtime().tm_min == tm.tm_min or (time.localtime().tm_min - clock_offset) % data_intv:
                        time.sleep(1)
            time.sleep(10)
