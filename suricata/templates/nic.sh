#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -ne 2 ] && fail "missing arguments"

NIC=$1
OP=$2

case $OP in
up)
	ip link set $NIC promisc on arp off up >/dev/null 2>&1
	echo 1 > /proc/sys/net/ipv6/conf/$NIC/disable_ipv6
	ip link set dev $NIC mtu 9000

	# disable RSS
	ethtool -L $NIC combined 1

	# limit interrupts
	ethtool -C $NIC adaptive-rx on rx-usecs 100

	# lower NIC ring size for better L3 cache miss rate
	ethtool -G $NIC rx 512

	ethtool --pause $NIC autoneg off rx off tx off >/dev/null 2>&1
	for i in rx tx autoneg tso ufo gso gro lro txnocachecopy rxhash ntuple sg txvlan rxvlan; do
		ethtool -K $NIC $i off >/dev/null 2>&1
	done
	;;

down)
	ifconfig $NIC down 2>&1
	;;
*)
	fail "invalid option"
	:;
esac
