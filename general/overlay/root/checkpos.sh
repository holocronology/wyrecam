#!/bin/sh
#
# Run from cron every minute: restart positron if it is not running.

pospid=`cat /var/run/positron.pid 2>/dev/null`
[ -n "$pospid" ] && grep -q '^positron' /proc/${pospid}/comm 2>/dev/null && exit 0
echo "didn't find running positron"

killall -15 positron
/etc/init.d/S95videosys start
