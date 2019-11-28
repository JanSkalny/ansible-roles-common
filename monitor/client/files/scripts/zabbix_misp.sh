#!/bin/bash

# config
MISP_DIR=/var/www/MISP/
MISP_USER="www-data"

fail() {
	echo "$*" 1>&2
	exit 1
}

server_list() {
	sudo -u $MISP_USER $MISP_DIR/app/Console/cake server list 2>/dev/null | grep servers
}

server_test() {
	sudo -u $MISP_USER $MISP_DIR/app/Console/cake server test "$1" 2>/dev/null | grep status
}

[ $# -eq 0 ] && fail "missing params"

case "$1" in
	server-discovery)
		#server_list | jq -r '.servers | .[] | .id' | jq -Rs '(. / "\n") - [""] | {data: [{ "{#MISP_SERVER}": .[] }] }'
		server_list | jq -r '.servers | {data: [ .[] | { "{#MISP_SERVER}": .id, "{#MISP_SERVER_NAME}": .name }] }'
		;;

	server-test)
		[ $# -ne 3 ] && fail "usage: $0 server-test PARAM SERVER_ID"
		case "$2" in
			status)
				server_test $3 | jq -r '.status'
				;;
			sync)
				server_test $3 | jq -r '.message.perm_sync'
				;;
			version)
				server_test $3 | jq -r '.message.version'
				;;
			*)
				fail "invalid server-test PARAM"
		esac
		;;

	version)
		jq -r '([.major,.minor,.hotfix | tostring] | join("."))' "$MISP_DIR/VERSION.json"
		;;

	*)
		fail "unknown param"
esac

