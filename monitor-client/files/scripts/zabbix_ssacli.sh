#!/bin/bash

# apt-get install jq

fail() {
	echo "$*" 1>&2
	exit 1
}

OUT_FILE="/var/run/zabbix/ssacli.json"
TMP_FILE="/var/run/zabbix/ssacli.tmp"

#TODO:
# - delete $TMP_FILE older than 5 minutes
# - error handling (missing file, invalid drive_id, ...)

dump_state() {
	for I in 1 2 3 4 5; do
		# dump to TMP file
		sudo /usr/sbin/ssacli controller all show config | \
			grep 'drive ' | sed 's/.* \([^ ]*drive\) \([^ ]*\) .*,[ ]*\([^)]*\)).*/\1;\2;\3/' | \
			jq --arg ATTEMPT "$I" -Rs 'split("\n") - [""] | {drives: [( (.[] | split(";")) | {type: .[0], id: .[1], status: .[2] }) ], last_update: now, attempt: $ATTEMPT }' > $TMP_FILE

		# make sure run was successful. if so, save output and return
		grep last_update "$TMP_FILE" >/dev/null 2>&1 && mv "$TMP_FILE" "$OUT_FILE" && return

		# retry
		sleep 0.5
	done



	# failed! cleanup and exit
	for F in "$OUT_FILE" "$TMP_FILE"; do 
		[ -f "$F" ] && rm "$F"
	done
	fail "failed to dump ssacli state"
}

case "$1" in
dump)
	dump_state 
	jq ".last_update" "$OUT_FILE"
	;;

log-discover)
	jq '{data: [ { "{#DRIVE_ID}": .drives[] | select(.type=="logicaldrive") | .id } ]}' $OUT_FILE
	;;

log-status)
	jq -r --arg ID "$2" '.drives[] | select(.type=="logicaldrive" and .id==$ID) | .status' $OUT_FILE
	;;

phy-discover)
	jq '{data: [ { "{#DRIVE_ID}": .drives[] | select(.type=="physicaldrive") | .id } ]}' $OUT_FILE
	;;

phy-status)
	jq -r --arg ID "$2" '.drives[] | select(.type=="physicaldrive" and .id==$ID) | .status' $OUT_FILE
	;;

*) 
	fail "unknown op $1"
	;;
esac
