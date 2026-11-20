#!/bin/sh

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -eq 1 ] || fail "usage: $0 WWID"

# remove leading "3" from WWID
WWID="$1"
WWN=$( echo $1 | sed 's/^3//' )

# make sure we have at least one device with matching WWN
CNT_BEFORE=$( lsscsi -u | grep " $WWN[ ]\+/dev/" | wc -l )
[ $CNT_BEFORE -gt 0 ] || fail "no such WWN"

# try to close multipath device first
MP_NAME=$(multipath -l "$WWID" | awk -v w="$WWID" 'NR == 1 { if ($2 == "(" w ")") print $1; exit }')
[ -n "$MP_NAME" ] || fail "no matching multipath map found for WWID $WWID"
multipath -f "$MP_NAME" || fail "cannot remove multipath map; refusing to delete SCSI paths"

# delete block devices with matching wwid
for DISK in $( lsscsi -u | grep " $WWN[ ]\+/dev/" | rev | cut -d '/' -f1 | rev ); do
	echo "delete $DISK"
	echo 1 > /sys/block/$DISK/device/delete
done

# make sure we removed them all
CNT_AFTER=$( lsscsi -u | grep " $WWN[ ]\+/dev/" | wc -l )
[ $CNT_AFTER -eq 0 ] || fail "failed to remove all disks"

# like, *really* sure. ok?
CNT_MP_AFTER=$( multipath -d -v3 2>/dev/null | grep "^$1 " | wc -l )
[ $CNT_MP_AFTER -eq 0 ] || fail "failed to remove all disks (multipath)"
