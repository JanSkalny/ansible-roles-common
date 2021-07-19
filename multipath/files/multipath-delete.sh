#!/bin/sh

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -eq 1 ] || fail "usage: $0 WWID"

# remove leading "3" from WWID
WWID=$( echo $1 | sed 's/^3//' )

# make sure we have at least one device with matching WWID
CNT_BEFORE=$( lsscsi -u | grep " $WWID[ ]\+/dev/" | wc -l )
[ $CNT_BEFORE -gt 0 ] || fail "no such WWID"

# delete block devices with matching wwid
for DISK in $( lsscsi -u | grep " $WWID[ ]\+/dev/" | rev | cut -d '/' -f1 | rev ); do
	echo "delete $DISK"
	echo 1 > /sys/block/$DISK/device/delete
done

# make sure we removed them all
CNT_AFTER=$( lsscsi -u | grep " $WWID[ ]\+/dev/" | wc -l )
[ $CNT_AFTER -eq 0 ] || fail "failed to remove all disks"

# like, *really* sure. ok?
CNT_MP_AFTER=$( multipath -d -v3 2>/dev/null | grep "^$1 " | wc -l )
[ $CNT_MP_AFTER -eq 0 ] || fail "failed to remove all disks (multipath)"
