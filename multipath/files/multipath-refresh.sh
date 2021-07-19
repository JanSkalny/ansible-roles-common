#!/bin/sh

fail() {
	echo "$*" 1>&2
	exit 1
}

# make sure we have lsscsi
which lsscsi > /dev/null || fail 'missing lsscsi'

# rescan iscsi and FC hosts
for I in $(lsscsi -tH | grep ' \(iscsi\|fc\):' | cut -d ']' -f 1 | tr -d '['); do
	echo "- - -" > /sys/class/scsi_host/host$I/scan
done

# LIP on FC hosts
#for I in $(lsscsi -tH | grep ' fc:' | cut -d ']' -f 1 | tr -d '['); do
#	echo "1" > /sys/class/fc_host/host${I}/issue_lip
#done

multipath > /dev/null

#dmsetup remove_all

/etc/init.d/multipath-tools reload
