#!/bin/bash

#apt-get install jq

HPA="sudo /usr/sbin/hpacucli"
LOCK="/var/run/zabbix/zabbix_hpacucli.lock"

unlock() {
	rm -f $LOCK >/dev/null 2>&1
}

fail() {
	echo "$*" 1>&2
	exit 1
}

# mutex
exec 666>$LOCK
flock -x -w 60 666 || fail "failed to obtain lock"
echo $$ 1>&666

case "$1" in
log-discover)
	OUT=""
	for SLOT in $( $HPA controller all show | grep Slot | sed 's/.*Slot \([0-9]*\) .*/\1/' ); do
		for DRIVE in $( $HPA controller slot=$SLOT logicaldrive all show | grep logicaldrive | sed 's/.*logicaldrive \([0-9]*\) .*/\1/' ); do
			OUT="$OUT$SLOT $DRIVE|"
		done
	done
	echo "$OUT" | jq -Rn '
	( input | split("|") - [""]) as $drives | 
	{ data: [($drives[] | ( split(" ") | {"{#SLOT_ID}":.[0]|tonumber, "{#DRIVE_ID}":.[1]|tonumber}))]}'
	;;

log-status)
	STATUS=$( $HPA controller slot="$2" logicaldrive "$3" show | grep '  Status: ' | sed 's/.*Status: \(.*\)$/\1/' )
	if [ "x$STATUS" == "x" ]; then
		sleep 10
		echo -n "Retried "
		$HPA controller slot="$2" logicaldrive "$3" show | grep '  Status: ' | sed 's/.*Status: \(.*\)$/\1/'
	else
		echo $STATUS
	fi
	;;

phy-discover)
	OUT=""
	for SLOT in $( $HPA controller all show | grep Slot | sed 's/.*Slot \([0-9]*\) .*/\1/' ); do
		for DRIVE in $( $HPA controller slot=$SLOT physicaldrive all show | grep physical | sed 's/.*physicaldrive \([^ ]*\) .*/\1/' ); do
			OUT="$OUT$SLOT $DRIVE|"
		done
	done
	echo "$OUT" | jq -Rn '
	( input | split("|") - [""]) as $drives | 
	{ data: [($drives[] | ( split(" ") | {"{#SLOT_ID}":.[0]|tonumber, "{#DRIVE_ID}":.[1]}))]}'
	;;

phy-status)
	STATUS=$( $HPA controller slot="$2" physicaldrive "$3" show | grep '  Status: ' | sed 's/.*Status: \(.*\)$/\1/' )
	#XXX: retry 
	if [ "x$STATUS" == "x" ]; then
		sleep 10
		echo -n "Retried "
		$HPA controller slot="$2" physicaldrive "$3" show | grep '  Status: ' | sed 's/.*Status: \(.*\)$/\1/'
	else
		echo $STATUS
	fi
	;;

*) 
	unlock
	fail "unknown op $1"
	;;
esac

unlock
