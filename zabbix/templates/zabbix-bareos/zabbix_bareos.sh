#!/usr/bin/env bash
set -euo pipefail

clients() {
    echo 'list clients' | bconsole |
        awk -F'|' '$2 ~ /^[[:space:]]*[0-9]+[[:space:]]*$/ {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3
        }'
}

case "${1:-}" in
    discovery)
        clients | jq -Rn '{data: [inputs | {"{#CLIENT}": .}]}'
        ;;
    status)
        client=${2:?Specify a client}
        case "$client" in
            *[!a-zA-Z0-9_.:@-]*) echo 'Unsupported client name' >&2; exit 1 ;;
        esac
        clients | grep -Fx -- "$client" >/dev/null || {
            echo "Unknown client: $client" >&2; exit 1;
        }
        printf 'status client="%s"\n' "$client" | bconsole
        ;;
    jobs)
        printf 'list jobs days=3\n' | bconsole |
            awk -F'|' 'BEGIN {OFS="\t"}
                /^\|/ {
                    for (i=2; i<=11; i++)
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
                    if ($2 ~ /^[0-9,]+$/ && $7 == "B") {
                        gsub(/,/, "", $2); gsub(/,/, "", $9); gsub(/,/, "", $10)
                        print $4, $2, $5, $6, $8, $9, $10, $11
                    }
                }' |
            jq -Rn '[inputs | split("\t") | {
                key: .[0], value: {
                    jobid: (.[1]|tonumber), starttime: .[2],
                    duration: (.[3] | split(":") | map(tonumber) |
                               .[0]*3600 + .[1]*60 + .[2]),
                    level: .[4], files: (.[5]|tonumber),
                    bytes: (.[6]|tonumber), status: .[7]
                }
            }] | sort_by(.value.jobid) | from_entries'
        ;;
    *)
        echo "Usage: $0 discovery | status CLIENT | jobs [DAYS]" >&2
        exit 1
        ;;
esac

