#!/bin/bash
while true
do
# echo `date '+%Y/%m/%d %H:%M:%S'`: `/opt/vc/bin/vcgencmd measure_temp`
temp=`cat /sys/class/thermal/thermal_zone0/temp`
echo `date '+%Y/%m/%d %H:%M:%S'`: `expr $temp / 1000`.`expr $temp % 1000`
sleep 0.5
done
