#!/bin/sh

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -eq 1 ] || fail "usage: $0 NAME"

# identify WWID from block device name
NAME="$1"
WWID=$( multipath -l | grep "^$NAME " | awk '{print $2}' | tr -d '()' | sed 's/^3//' )
[ "x$WWID" = "x" ] && fail "failed to find WWID for $NAME"

# make sure we have at least one device with matching WWID
CNT=$( lsscsi -u | grep " $WWID[ ]\+/dev/" | wc -l )
[ $CNT -gt 0 ] || fail "no such WWID"

# rescan block devices with matching wwid
for DISK in $( lsscsi -u | grep " $WWID[ ]\+/dev/" | rev | cut -d '/' -f1 | rev ); do
	echo "rescan $DISK"
	echo 1 > /sys/block/$DISK/device/rescan
done

multipathd resize map "$NAME" || fail "multipathd resize map failed"
