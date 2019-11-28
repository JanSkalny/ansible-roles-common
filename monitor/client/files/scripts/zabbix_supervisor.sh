#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -eq 0 ] && fail "usage: $0 (enabled|...)"


case "$1" in
enabled)
	systemctl list-unit-files | grep supervisor.service | grep enabled | wc -l
	;;

count)
	supervisorctl status | wc -l
	;;
	
discover-services)
	supervisorctl status | awk '{print $1}' | jq -Rs '(. / "\n") - [""] | {data: [{ "{#SUPERVISOR_SERVICE}": .[] }]}'
	;;

service-status)
	[ $# -eq 2 ] || fail "usage: $0 service-status SERVICE"
	supervisorctl status "$2" | awk '{print $2}'
	;;

*)
	fail "usage..."
	exit 1
esac

