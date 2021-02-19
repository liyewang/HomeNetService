#!/bin/bash
while true
do
echo `date '+%Y/%m/%d %H:%M:%S'`: `/opt/vc/bin/vcgencmd measure_temp`
# cat /sys/class/thermal/thermal_zone0/temp
sleep 0.5
done
