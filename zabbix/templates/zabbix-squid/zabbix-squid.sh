#!/bin/bash

LAST_RUN="/run/zabbix/zabbix-squid.lastest"

ITEM_OID_MAP=$( cat <<EOF
1.3.6.1.4.1.3495.1.3.1.5.0	cacheCpuUsage
1.3.6.1.4.1.3495.1.3.1.12.0	cacheCurrentFileDescrCnt
1.3.6.1.4.1.3495.1.3.1.13.0	cacheCurrentFileDescrMax
1.3.6.1.4.1.3495.1.3.1.8.0	cacheCurrentLRUExpiration
1.3.6.1.4.1.3495.1.3.1.11.0	cacheCurrentResFileDescrCnt
1.3.6.1.4.1.3495.1.3.2.1.14.0	cacheCurrentSwapSize
1.3.6.1.4.1.3495.1.3.1.9.0	cacheCurrentUnlinkRequests
1.3.6.1.4.1.3495.1.3.1.10.0	cacheCurrentUnusedFDescrCnt
1.3.6.1.4.1.3495.1.4.3.2.0	cacheDnsReplies
1.3.6.1.4.1.3495.1.4.3.1.0	cacheDnsRequests
1.3.6.1.4.1.3495.1.3.2.2.1.8.5	cacheDnsSvcTime.5
1.3.6.1.4.1.3495.1.3.2.2.1.8.60	cacheDnsSvcTime.60
1.3.6.1.4.1.3495.1.4.2.3.0	cacheFqdnHits
1.3.6.1.4.1.3495.1.4.2.6.0	cacheFqdnMisses
1.3.6.1.4.1.3495.1.4.2.2.0	cacheFqdnRequests
1.3.6.1.4.1.3495.1.3.2.2.1.2.5	cacheHttpAllSvcTime.5
1.3.6.1.4.1.3495.1.3.2.2.1.2.60	cacheHttpAllSvcTime.60
1.3.6.1.4.1.3495.1.3.2.1.3.0	cacheHttpErrors
1.3.6.1.4.1.3495.1.3.2.2.1.5.5	cacheHttpHitSvcTime.5
1.3.6.1.4.1.3495.1.3.2.2.1.5.60	cacheHttpHitSvcTime.60
1.3.6.1.4.1.3495.1.3.2.1.2.0	cacheHttpHits
1.3.6.1.4.1.3495.1.3.2.1.4.0	cacheHttpInKb
1.3.6.1.4.1.3495.1.3.2.2.1.3.5	cacheHttpMissSvcTime.5
1.3.6.1.4.1.3495.1.3.2.2.1.3.60	cacheHttpMissSvcTime.60
1.3.6.1.4.1.3495.1.3.2.1.5.0	cacheHttpOutKb
1.3.6.1.4.1.3495.1.3.2.1.9.0	cacheIcpKbRecv
1.3.6.1.4.1.3495.1.3.2.1.8.0	cacheIcpKbSent
1.3.6.1.4.1.3495.1.3.2.1.7.0	cacheIcpPktsRecv
1.3.6.1.4.1.3495.1.3.2.1.6.0	cacheIcpPktsSent
1.3.6.1.4.1.3495.1.3.2.2.1.6.5	cacheIcpQuerySvcTime.5
1.3.6.1.4.1.3495.1.3.2.2.1.6.60	cacheIcpQuerySvcTime.60
1.3.6.1.4.1.3495.1.3.2.2.1.7.5	cacheIcpReplySvcTime.5
1.3.6.1.4.1.3495.1.3.2.2.1.7.60	cacheIcpReplySvcTime.60
1.3.6.1.4.1.3495.1.4.1.3.0	cacheIpHits
1.3.6.1.4.1.3495.1.4.1.6.0	cacheIpMisses
1.3.6.1.4.1.3495.1.4.1.2.0	cacheIpRequests
1.3.6.1.4.1.3495.1.3.1.6.0	cacheMaxResSize
1.3.6.1.4.1.3495.1.2.5.1.0	cacheMemMaxSize
1.3.6.1.4.1.3495.1.3.1.3.0	cacheMemUsage
1.3.6.1.4.1.3495.1.3.1.7.0	cacheNumObjCount
1.3.6.1.4.1.3495.1.3.2.1.1.0	cacheProtoClientHttpRequests
1.3.6.1.4.1.3495.1.3.2.2.1.10.1	cacheRequestByteRatio.1
1.3.6.1.4.1.3495.1.3.2.2.1.10.5	cacheRequestByteRatio.5
1.3.6.1.4.1.3495.1.3.2.2.1.10.60	cacheRequestByteRatio.60
1.3.6.1.4.1.3495.1.3.2.2.1.9.1	cacheRequestHitRatio.1
1.3.6.1.4.1.3495.1.3.2.2.1.9.5	cacheRequestHitRatio.5
1.3.6.1.4.1.3495.1.3.2.2.1.9.60	cacheRequestHitRatio.60
1.3.6.1.4.1.3495.1.2.5.3.0	cacheSwapHighWM
1.3.6.1.4.1.3495.1.2.5.4.0	cacheSwapLowWM
1.3.6.1.4.1.3495.1.2.5.2.0	cacheSwapMaxSize
1.3.6.1.4.1.3495.1.3.1.1.0	cacheSysPageFaults
1.3.6.1.4.1.3495.1.1.3.0	cacheUptime
1.3.6.1.4.1.3495.1.2.3.0	cacheVersionId
EOF
)

fail() {
	echo "$*" 1>&2
	exit 1
}

[ $# -eq 0 ] && fail "missing params"

case "$1" in
	get)
		[ $# -ne 2 ] && fail "usage: $0 get ITEM"
    OID=$( echo "$ITEM_OID_MAP" | grep "	$2\$" | awk '{print $1}' )
    [ "x$OID" == "x" ] && fail "ITEM not found in ITEM_OID_MAP"
    [ -f "$LAST_RUN" ] || fail "missing LAST_RUN file"
    #TODO: add check for stale LAST_RUN file

    grep "^.$OID " "$LAST_RUN" | awk '{print $4}' | tr -d '()"'
		;;

  update-stats)
    snmpwalk -Cc -On -v2c -c zabbix 127.0.0.1:3401 1.3.6.1.4.1.3495  | grep '= \(Counter32\|STRING\|INTEGER\|Gauge32\|Timeticks\):' > $LAST_RUN || exit 1
    wc -l "$LAST_RUN" | awk '{print $1}'
    ;;

	*)
		fail "unknown param"
esac
