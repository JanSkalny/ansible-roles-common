#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "ZBX_NOTSUPPORTED: $*" >&2
    exit 1
}

usage() {
    fail "usage:
  $0 discovery 
  $0 load <cgroup> <some|full> <10|60|300>"
}

validate_path() {
    [[ -n "$1" ]] || fail "empty cgroup path"
    [[ "$1" != *".."* ]] || fail "invalid cgroup path"
}

discovery() {
    find /sys/fs/cgroup -type f -name cpu.max -readable -print0 |
        while IFS= read -r -d '' file; do
            read -r quota _ < "$file"
            [[ "$quota" != "max" ]] || continue

            cgroup="${file#/sys/fs/cgroup/}"
            cgroup="${cgroup%/cpu.max}"

            jq -cn --arg cgroup "$cgroup" \
                '{"{#CGROUP}":$cgroup}'
        done |
        jq -s '{data:.}'
}

load() {
    local cgroup="${1#/}"
    local type="$2"
    local period="$3"
    local field file

    validate_path "$cgroup"

    [[ "$type" == "some" || "$type" == "full" ]] ||
        fail "type must be some or full"

    case "$period" in
        10)  field="avg10" ;;
        60)  field="avg60" ;;
        300) field="avg300" ;;
        *) fail "period must be 10, 60 or 300" ;;
    esac

    file="/sys/fs/cgroup/$cgroup/cpu.pressure"
    [[ -r "$file" ]] || fail "cannot read $file"

    awk -v type="$type" -v field="$field" '
        $1 == type {
            for (i = 2; i <= NF; i++) {
                split($i, value, "=")
                if (value[1] == field) {
                    print value[2]
                    found = 1
                    exit
                }
            }
        }
        END {
            if (!found)
                exit 1
        }
    ' "$file" || fail "$type $field not found"
}

case "${1:-}" in
    discovery)
        [[ $# -eq 1 ]] || usage
        discovery
        ;;
    load)
        [[ $# -eq 4 ]] || usage
        load "$2" "$3" "$4"
        ;;
    *)
        usage
        ;;
esac
