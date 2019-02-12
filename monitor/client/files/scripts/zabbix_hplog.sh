#!/bin/bash

#apt-get install jq

HPL="sudo /sbin/hplog"

fail() {
	echo "$*" 1>&2
	exit 1
}

case "$1" in
fan-discover)  $HPL -f | tail -n +2 | head -n -1 | awk '{ print $1 }' | jq -Rsc '. / "\n" - [""]' |  jq -Mc '{data: [{"{#FAN_ID}":.[]}]}' ;;
fan-status)    $HPL -f | grep "^[ ]*$2 " | cut -c 34-44 | awk '{print $1}' ;;
fan-speed)     $HPL -f | grep "^[ ]*$2 " | sed 's/.*([ ]*\(.*\))$/\1/' ;;

pwr-discover)  $HPL -p | tail -n +2 | head -n -1 | awk '{ print $1 }' | jq -Rsc '. / "\n" - [""]' |  jq -Mc '{data: [{"{#PWR_ID}":.[]}]}' ;;
pwr-status)    $HPL -p | grep "^[ ]*$2 " | cut -c 34-44 | awk '{print $1}' ;;

temp-discover) $HPL -t | tail -n +2 | head -n -1 | grep -v '\-\-C' | awk '{print "{ \"{#TEMP_ID}\":" $1 ", \"{#TEMP_THRESHOLD}\":" substr($0, 58, 3) ", \"{#TEMP_LOCATION}\": \"" substr($0,18,15) "\" }" }' | jq -s ' {data: . }' ;;
temp-status)   $HPL -t | grep "^[ ]*$2 " | cut -c 34-44 | awk '{print $1}' ;;
temp-cur)      $HPL -t | grep "^[ ]*$2 " | cut -c 48-50 | awk '{print $1}' ;;

*) fail "unknown op $1"
esac


