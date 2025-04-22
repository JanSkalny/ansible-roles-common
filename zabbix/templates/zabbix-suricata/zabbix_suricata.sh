#!/bin/bash

fail() {
    echo "$*" 1>&2
    exit 1
}

usage() {
    fail "usage: $0 (discover-apps|get KEY|json)"
    exit 1
}

[ $# -lt 1 ] && usage

STATS="/var/log/suricata/stats.last"

case "$1" in
discover-apps)
    [ $# -ne 1 ] && usage

    [ -f "$STATS" ] || fail "missing stats.last file"

    # list all enabled app layer protocols
    cat "$STATS" | grep '^app_layer' | cut -d '|' -f 1 | cut -d '.' -f 3 | sort | uniq \
        | jq -Rs 'split("\n") - [""] | map({"{#APP}": .}) | {data: .}'
    ;;

get)
    [ $# -ne 2 ] && usage
    OP="$2"

    [ -f "$STATS" ] || fail "missing stats.last file"

    # get requested metric
    RES=$( grep "^$OP|" "$STATS" | cut -d '|' -f 3 )
    [ "x$RES" != "x" ] || fail "invalid key"
    echo "$RES"
    ;;

json)
    [ $# -ne 1 ] && usage
    [ -f "$STATS" ] || fail "missing stats.last file"
    jq -Rn '[inputs | split("|") | {(.[0]): (.[2]|tonumber)}] | add ' "$STATS"
    ;;

*)
    usage
    ;;
esac
