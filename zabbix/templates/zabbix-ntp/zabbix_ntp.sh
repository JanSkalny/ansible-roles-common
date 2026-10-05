#!/usr/bin/env bash

set -u
set -o pipefail

fail() {
    echo "$*" >&2
    exit 1
}

usage() {
    fail "usage: $0 {drift|offset SERVER|selected-peer|selected-strata|selected-offset|selected-delay}"
}

selected_line() {
    LC_ALL=C ntpq -pn 2>/dev/null |
        awk '$1 ~ /^[*o]/ { print; exit }'
}

selected_value() {
    local line remote refid stratum type when poll reach delay offset jitter

    line=$(selected_line)
    [[ -n "$line" ]] || fail ""

    read -r remote refid stratum type when poll reach delay offset jitter <<<"$line"
    remote=${remote:1}

    case "$1" in
        peer)    echo "$remote" ;;
        strata) echo "$stratum" ;;
        offset) echo "$offset" ;;
        delay)  echo "$delay" ;;
    esac
}

query_offset() {
    local server=$1 output offset

    if command -v ntpdig >/dev/null 2>&1; then
        output=$(LC_ALL=C ntpdig -j -p 1 "$server" 2>/dev/null) || true
        offset=$(sed -nE 's/.*"offset"[[:space:]]*:[[:space:]]*([-+0-9.eE]+).*/\1/p' <<<"$output")
        [[ -n "$offset" ]] && { echo "$offset"; return; }
    fi

    if command -v ntpdate >/dev/null 2>&1; then
	output=$(LC_ALL=C ntpdate -q "$server" 2>/dev/null) || true
        offset=$(awk 'match($0,/offset [-+0-9.eE]+ sec/) {
            value=substr($0,RSTART,RLENGTH)
            sub(/^offset /,"",value)
            sub(/ sec$/,"",value)
            print value
        }' <<<"$output" | tail -1)
        [[ -n "$offset" ]] && { echo "$offset"; return; }
    fi

    if command -v sntp >/dev/null 2>&1; then
        output=$(LC_ALL=C sntp "$server" 2>/dev/null) || true
        offset=$(awk '{
            for (i=2; i<=NF; i++)
                if ($i == "+/-") {
                    print $(i-1)
                    exit
                }
        }' <<<"$output")
        [[ -n "$offset" ]] && { echo "$offset"; return; }
    fi

    fail "NTP query failed for $server"
}

drift() {
    local file

    for file in \
        /var/lib/ntp/ntp.drift \
        /var/lib/ntpsec/ntp.drift \
        /etc/ntp.drift
    do
        [[ -r "$file" ]] && {
            awk 'NF { print $1; exit }' "$file"
            return
        }
    done

    fail "NTP drift file not found"
}

case "${1-}" in
    drift)
        [[ $# -eq 1 ]] || usage
        drift
        ;;
    offset)
        [[ $# -eq 2 ]] || usage
        query_offset "$2"
        ;;
    selected-peer)
        [[ $# -eq 1 ]] || usage
        selected_value peer
        ;;
    selected-strata)
        [[ $# -eq 1 ]] || usage
        selected_value strata
        ;;
    selected-offset)
        [[ $# -eq 1 ]] || usage
        selected_value offset
        ;;
    selected-delay)
        [[ $# -eq 1 ]] || usage
        selected_value delay
        ;;
    *)
        usage
        ;;
esac
