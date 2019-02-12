#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

instance_list() {
	find /etc/openvpn -name '*.conf' -printf "%f\n" | sed 's/\.conf//' 
}

get_status() {
	PID_FILE="/run/openvpn/$1.pid"
	STATUS_FILE="/run/openvpn/$1.status"

	# check if pid and status files are present
	[ -f "$PID_FILE" ] || fail "missing PID file"
	[ -f "$STATUS_FILE" ] || fail "missing status file"

	PID=$(cat $PID_FILE)

	# check if process is alive
	PROC=$(ps -q $PID -o comm=)
	[ $PROC == "openvpn" ] || fail "unexpected process name"

	echo "OK"
}

client_list() {
	awk '/CLIENT LIST/,/ROUTING TABLE/' /run/openvpn/$1.status 2>/dev/null | tail -n +4 | head -n -1 
}


[ $# -eq 0 ] && fail "missing param"

case "$1" in
	discovery)
		instance_list | jq -Rs '(. / "\n") - [""] | {data: [{ "{#INSTANCE}": .[] }] }'
		;;

	status)
		get_status "$2"
		;;

	client-cnt)
		client_list "$2" | wc -l
		;;

	*)
		fail "unknown param"
esac

