#!/bin/sh

for HOST in $(ls -1d /sys/class/fc_host/*); do echo "1" > ${HOST}/issue_lip; done
for HOST in $(ls -1d /sys/class/scsi_host/*); do echo "- - -" > ${HOST}/scan ; done

multipath > /dev/null
#dmsetup remove_all

/etc/init.d/multipath-tools reload
