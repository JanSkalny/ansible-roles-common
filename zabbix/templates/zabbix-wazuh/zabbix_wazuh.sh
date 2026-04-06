#!/bin/bash

fail() {
    echo "$*" 1>&2
    exit 1
}

usage() {
    fail "usage: $0 (discover-agents|agents-total|agents-active|agents-inactive)"
    exit 1
}

list_agents() {
    CACHE_FILE="/var/run/zabbix/wazuh-agents.json"
    [ ! -f "$CACHE_FILE" ] || [ "$(find "$CACHE_FILE" -newermt '-55 seconds' 2>/dev/null)" = "" ] \
		&& docker exec wazuh.manager /var/ossec/bin/agent_control -l -j | jq . > "$CACHE_FILE"
    [ -f "$CACHE_FILE" ] || fail "failed to list agents"
	cat "$CACHE_FILE"
}

[ $# -lt 1 ] && usage

case "$1" in
discover-agents)
    [ $# -ne 1 ] && usage
	list_agents | jq '{ data: [ .data[] | select(.name?) | { "{#AGENT_NAME}": .name } ] }'
    ;;

agent-status)
    [ $# -ne 2 ] && usage
	STATUS=$( list_agents | jq --arg AGENT "$2" -r '.data[]|select(.name == $AGENT)|.status' )
	[ "x$STATUS" == "x" ] && fail "no such agent"
	echo $STATUS
	;;

agents-total)
	list_agents | jq '.data|length'
	;;

agents-active)
	list_agents | jq '[.data[]|select(.status=="Active")]|length'
	;;

agents-inactive)
	list_agents | jq '[.data[]|select(.status!="Active")]|length'
	;;

*)
    usage
    ;;
esac
