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

def rec_purge(cam_name, rec_dst, max_size, max_days):
    size = 0
    items = os.listdir(rec_dst)
    items.sort(reverse=True)
    for item in items:
        item_path = os.path.join(rec_dst, item)
        if os.path.isfile(item_path):
            m = re.search(f'^{cam_name}_(\d{{14}})\.mp4$', item)
            if m:
                while size > 0:
                    if max_size > 0:
                        size += os.lstat(item_path).st_size
                        if size > max_size:
                            size = -1
                            continue
                    if max_days > 0:
                        days = (time.time() - time.mktime(time.strptime(m.group(1), r'%Y%m%d%H%M%S'))) / (3600 * 24)
                        if days > max_days:
                            size = -1
                            continue
                    break
                else:
                    if size < 0:
                        try:
                            os.remove(item_path)
                        except:
                            log(f'Delete file [{item_path}] failed.')
                    else:
                        size += os.lstat(item_path).st_size
                        if size <= 0:
                            size = 1
    return

def recorder(cam_name, cam_src, rec_dst, seg_time, timeout, max_size, max_days):
    flag = True
    while not os.path.isdir(rec_dst):
        try:
            os.makedirs(rec_dst)
        except:
            if flag:
                log(f'{cam_name} recording path error.')
                flag = False
            time.sleep(1)
        else:
            log(f'{cam_name} recording path created.')
    cmd = f'ffmpeg -v level+error -stimeout {int(timeout * 1000000)} -i "{cam_src}" -c copy -f segment -segment_atclocktime 1 -segment_time {seg_time} -segment_format_options movflags=+faststart -strftime 1 "{os.path.join(rec_dst, cam_name)}_%Y%m%d%H%M%S.mp4" -y'
    purge_timer = 0
    while True:
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
        flag = True
        while p.poll() == None:
            free = shutil.disk_usage(rec_dst).free
            if free < min_free:
                if flag:
                    log(f'Insufficient free space: {free} in {rec_dst}')
                    flag = False
                try:
                    out, err = p.communicate(input='q', timeout=5)
                except subprocess.TimeoutExpired:
                    p.kill()
                    out, err = p.communicate()
                if out:
                    log(f'{cam_name} {out}')
                if err:
                    log(f'{cam_name} {err}')
            elif time.time() - purge_timer > seg_time:
                rec_purge(cam_name, rec_dst, max_size, max_days)
                purge_timer = time.time()
            time.sleep(1)
        log(f'{cam_name} recording stopped.')
        while free < rst_free:
            time.sleep(1)
            free = shutil.disk_usage(rec_dst).free
        if not flag:
            log(f'Sufficient free space: {free} in {rec_dst}')

if __name__ == '__main__':
    t = []
    # Load config
    with open(cfg_file, 'r') as f:
        cfg = yaml.safe_load(f)
    cams = len(cfg)
    if cams > max_cams:
        log(f'Number of cameras over limit ({cams} > {max_cams}).')
        cams = max_cams
    for i in range(cams):
        # Camera Config
        cam_name = str(cfg[i].get('cam_name'))
        cam_src = str(cfg[i].get('cam_src'))
        timeout = float(cfg[i].get('timeout', timeout))
        # Recoder Config
        rec_dst = str(cfg[i].get('rec_dst', os.path.join(cam_rec_path, cam_name)))
        seg_time = int(cfg[i].get('seg_time', seg_time))
        max_size = float(cfg[i].get('max_size', max_size) * 1024 ** 3)
        max_days = float(cfg[i].get('max_days', max_days))
        t.append(threading.Thread(target=recorder, args=(cam_name, cam_src, rec_dst, seg_time, timeout, max_size, max_days)))
        t[i].daemon = True
        t[i].start()
        log(f'{cam_name} thread started.')
    while True:
        for i in range(cams):
            if not t[i].is_alive():
                log(f'{cfg[i].get("cam_name")} thread stopped.')
                t[i].daemon = True
                t[i].start()
                log(f'{cfg[i].get("cam_name")} thread restarted.')
        time.sleep(1)
