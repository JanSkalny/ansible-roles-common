#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

case "$1" in
discover)
	multipath -l -v1 | jq -Rs '(. / "\n") - [""] | {data: [{ "{#MULTIPATH}": .[] }] }'
	;;

size)
	multipath -ll "$2" | grep 'size=' | sed 's/.*size=\([^ ]*\).*/\1/'
	;;

features)
	multipath -ll "$2" | grep 'features=' | sed "s/.*features='\([^']*\)'.*/\1/"
	;;

status)
	multipath -ll "$2"  | grep 'status=' | sed 's/.*status=//' | head -n 1
	;;

path-cnt-ok)
	multipath -ll "$2"  | grep 'status=active' | wc -l
	;;

path-cnt-faulty)
	multipath -ll "$2"  | grep 'status=' | grep -v 'status=active' | wc -l
	;;

dm-cnt-ok)
	multipath -ll "$2" | grep '  sd[a-z]' | grep 'active ready  running' | wc -l
	;;

dm-cnt-faulty)
	multipath -ll "$2" | grep '  sd[a-z]' | grep -v 'active ready  running' | wc -l
	;;

*)
	fail "unknown op $1"
	;;
esac
