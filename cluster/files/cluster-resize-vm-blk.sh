#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -eq 1 ] || fail "usage: $0 vm-xxx"

VM="$1"

# make sure vm is running
virsh list | grep " $VM " > /dev/null 2>&1
[ $? -eq 0 ] || fail "vm is not running"

#XXX assume /dev/mapper/$VM
PHY="$( virsh domblkinfo "$VM" "/dev/mapper/$VM" | grep Phys | awk '{print $2}' )"
CAP="$( virsh domblkinfo "$VM" "/dev/mapper/$VM" | grep Cap | awk '{print $2}' )"

if [[ "$PHY" != "$CAP" ]] ; then
	echo "vm storage is underprovisioned. resizing"
	echo "$PHY -> $CAP"
	virsh blockresize --domain "$VM" --path "/dev/mapper/$VM" --size "${CAP}B"
	echo "done res=$?"
	echo "now refresh and resize2fs from guest"
fi
