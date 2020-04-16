#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

usage() {
	fail "usage: $0 (discover|processed) [ITEM]"
	exit 1
}

syslog_stats() {
	RES=$( syslog-ng-ctl stats | sed 's/;/_/' | sed 's/;/_/'| grep "^$2;" | grep ";$1;[0-9]*$" | cut -d';' -f4 | head -n1 )
	[[ $RES =~ ^[0-9]+ ]] || fail "no such item $2"
	echo "$RES"
}

[ "$#" -lt 1 ] && usage

case "$1" in
discover)
	syslog-ng-ctl stats | grep ';processed;[0-9]*$' | cut -d';' -f1-3 | sed 's/;/_/g' | sort | uniq | jq -Rs '(. / "\n") - [""] | {data: [{ "{#SYSLOG_NG_QUEUE}": .[] }] }'
	;; 

processed | written | dropped | queued)
	syslog_stats "$1" "$2" || fail "syslog-ng-ctl stats failed!"
	;;

*)
	usage
	;;
esac

