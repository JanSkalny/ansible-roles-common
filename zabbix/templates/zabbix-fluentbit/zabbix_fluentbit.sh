#!/bin/bash

fail() {
    echo "$*" 1>&2
    exit 1
}

usage() {
    fail "usage: $0 (discover-instances|discover-inputs|discover-outputs|discover-filters|(version|uptime|instance-metrics) [instance])"
    exit 1
}

get_port() {
    CONF="/etc/fluent-bit/$1/fluent-bit.yaml"
    [ -f "$CONF" ] || fail "missing fluent-bit.yaml file"

    PORT=$( awk '/^service:/ {found=1} found && /http_port:/ {gsub(/"/, "", $2); print $2; exit}' "$CONF" )
    [ -z "$PORT" ] && fail "invalid http_port"

    echo "$PORT"
}

list_instances() {
    systemctl list-units --all '*fluent-bit*' --no-pager --no-legend --plain \
        | grep -oP 'fluent-bit@\K[^.]*(?=\.service)'
}

discover_metrics() {
    list_instances | while read -r INSTANCE; do
        PORT=$(get_port "$INSTANCE") || continue

        # cache metrics for each instance, if older than 1 minute or missing
        CACHE_FILE="/var/run/zabbix/fluentbit-$PORT.json"
        #[ ! -f "$CACHE_FILE" ] || [ "$(find "$CACHE_FILE" -mmin +1)" ] \
        [ ! -f "$CACHE_FILE" ] || [ "$(find "$CACHE_FILE" -newermt '-55 seconds' 2>/dev/null)" = "" ] \
            && curl -sS "http://0:$PORT/api/v1/metrics" -o "$CACHE_FILE"
        [ -f "$CACHE_FILE" ] || fail "failed to get fluent metrics"

        jq -r --arg instance "$INSTANCE" '
            .'$1' // empty | keys[] as $param |
            { "{#INSTANCE}": $instance, "{#NAME}": $param }' "$CACHE_FILE"
    done | jq -s '{ "data": . }'
}

#XXX: unused
discover_metrics_all() {
    list_instances | while read -r INSTANCE; do
        PORT=$(get_port "$INSTANCE") || continue
        curl -sS "http://0:$PORT/api/v1/metrics" \
            | jq -r --arg instance "$INSTANCE" '
            to_entries[]
            | select(.key == "input" or .key == "output" or .key == "filter")
            | .key as $param
            | .value
            | to_entries[]
            | {
                "{#INSTANCE}": $instance,
                "{#PARAM}": $param,
                "{#NAME}": .key
            }'
    done | jq -s '{ "data": . }'
}

[ $# -lt 1 ] && usage

case "$1" in
discover-instances)
    [ $# -ne 1 ] && usage
    list_instances | jq -R -s 'split("\n") | map(select(length > 0)) | {data: map({"{#INSTANCE}": .})}'
    ;;

discover-inputs)
    [ $# -ne 1 ] && usage
    discover_metrics "input"
    ;;

discover-outputs)
    [ $# -ne 1 ] && usage
    discover_metrics "output"
    ;;

discover-filters)
    [ $# -ne 1 ] && usage
    discover_metrics "filter"
    ;;

discover-metrics)
    [ $# -ne 1 ] && usage
    discover_metrics_all
    ;;

instance-version)
    PORT=$( get_port "$2" )
    curl -sS "http://0:$PORT" | jq -r '.["fluent-bit"].version' || fail "failed to get version"
    ;;

instance-uptime)
    PORT=$( get_port "$2" )
    curl -sS "http://0:$PORT/api/v1/uptime" | jq .uptime_sec
    ;;

instance-metrics)
    PORT=$( get_port "$2" )
    curl -sS "http://0:$PORT/api/v1/metrics" | jq .
    ;;

*)
    usage
    ;;
esac
