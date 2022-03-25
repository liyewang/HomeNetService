import subprocess
import threading
import time
import os
import yaml
import re
import shutil

# Camera Config
timeout = 5

# Recoder Config
seg_time = 3600
max_size = 0
max_days = 0
max_cams = 8
min_free = 1024 ** 3
rst_free = min_free * 2

# File Path
cam_rec_path = os.path.dirname(os.path.abspath(__file__))
log_path = f'{cam_rec_path}/CamRec.log'
cfg_file = f'{cam_rec_path}/CamRecCfg.yaml'

def log(msg):
    print(msg)
    t = time.strftime(r'%Y/%m/%d %H:%M:%S', time.localtime())
    try:
        with open(log_path, 'a') as f:
            f.write(f'{t}: {msg}\n')
    except:
        pass
    return

def rec_size(cam_name, cam_rec_path):
    size = 0
    for item in os.listdir(cam_rec_path):
        if os.path.isfile(item):
            m = re.search(f'^{cam_name}_\d{{14}}\.mp4$', item)
            if m:
                size += os.lstat(os.path.join(cam_rec_path, item)).st_size
    return size

def rec_days(cam_name, cam_rec_path):
    days = 0
    for item in os.listdir(cam_rec_path):
        if os.path.isfile(item):
            m = re.search(f'^{cam_name}_(\d{{14}})\.mp4$', item)
            if m:
                 tm = time.strptime(m.group(1), r'%Y%m%d%H%M%S')
                 days = (time.mktime(time.localtime()) - time.mktime(tm)) / (3600 * 24)
                 break
    return days

def rec_purge(cam_name, cam_rec_path, max_size, max_days):
    while True:
        if max_days > 0:
            if rec_days(cam_name, cam_rec_path) > max_days:
                break
        if max_size > 0:
            if rec_size(cam_name, cam_rec_path) > max_size:
                break
        return
    for item in os.listdir(cam_rec_path):
        if os.path.isfile(item):
            m = re.search(f'^{cam_name}_\d{{14}}\.mp4$', item)
            if m:
                if del_file:
                    try:
                        os.remove(del_file)
                    finally:
                        break
                else:
                    del_file = item

def recorder(cam_name, cam_src, rec_dst, seg_time, timeout, max_size, max_days):
    global free
    act = True
    while not os.path.isdir(rec_dst):
        try:
            os.makedirs(rec_dst)
        except:
            if act:
                log(f'{cam_name} recording path error.')
                act = False
            time.sleep(10)
        else:
            log(f'{cam_name} recording path created.')
    cmd = f'ffmpeg -v level+error -stimeout {timeout * 1000000} -i "{cam_src}" -c copy -f segment -segment_atclocktime 1 -segment_time {seg_time} -strftime 1 "{os.path.join(rec_dst, cam_name)}_%Y%m%d%H%M%S.mp4" -y'
    act = True
    while act:
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, encoding='utf-8')
        count = 0
        while p.poll() == None:
            if count <= timeout:
                time.sleep(1)
                count += 1
            else:
                log(f'{cam_name} recording started.')
                break
        else:
            out, err = p.communicate()
            if out:
                log(f'{cam_name} {out}')
            if err:
                log(f'{cam_name} {err}')
            time.sleep(10)
            continue
        while p.poll() == None:
            if act:
                rec_purge(cam_name, cam_rec_path, max_size, max_days)
                free = shutil.disk_usage(cam_rec_path).free
                if free < min_free:
                    try:
                        out, err = p.communicate(input='q', timeout=5)
                    except subprocess.TimeoutExpired:
                        p.kill()
                        out, err = p.communicate()
                    finally:
                        if out:
                            log(f'{cam_name} {out}')
                        if err:
                            log(f'{cam_name} {err}')
                    act = False
            time.sleep(seg_time)
        else:
            log(f'{cam_name} recording stopped.')

if __name__ == '__main__':
    t = []
    free = min_free
    # Load config
    with open(cfg_file, 'r') as f:
        cfg = yaml.safe_load(f)
    cams = len(cfg)
    if cams > max_cams:
        log(f'Number of cameras over limit ({cams} > {max_cams}).')
        cams = max_cams
    for i in range(cams):
        # Camera Config
        cam_name = cfg[i].get('cam_name')
        cam_src = cfg[i].get('cam_src')
        timeout = cfg[i].get('timeout', timeout)
        # Recoder Config
        rec_dst = cfg[i].get('rec_dst', os.path.join(cam_rec_path, cam_name))
        seg_time = cfg[i].get('seg_time', seg_time)
        max_size = cfg[i].get('max_size', max_size) * 1024 ** 3
        max_days = cfg[i].get('max_days', max_days)
        t.append(threading.Thread(target=recorder, args=(cam_name, cam_src, rec_dst, seg_time, timeout, max_size, max_days)))
        t[i].start()
        log(f'{cam_name} thread started.')
    while True:
        for i in range(cams):
            if not t[i].is_alive():
                if free < min_free:
                    log('Insufficient free space.')
                    for i in range(cams):
                        t[i].join()
                        log(f'{cfg[i].get("cam_name")} thread stopped.')
                    while free < rst_free:
                        time.sleep(1)
                        free = shutil.disk_usage(cam_rec_path).free
                    log('Sufficient free space.')
                else:
                    log(f'{cfg[i].get("cam_name")} thread stopped.')
                t[i].start()
                log(f'{cfg[i].get("cam_name")} thread restarted.')
        time.sleep(1)
