#!/bin/bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

# Finish collection before printing JSON, so errors cannot look like zeros.
stats=$(conntrack -S)
ipv4=$(conntrack -L -f ipv4 2>/dev/null)
ipv6=$(conntrack -L -f ipv6 2>/dev/null)

{
    printf '%s\n' "$stats"
    printf '%s\n' "$ipv4"
    printf '%s\n' "$ipv6"
} | awk '
BEGIN {
    n = split("NONE SYN_SENT SYN_RECV ESTABLISHED FIN_WAIT CLOSE_WAIT LAST_ACK TIME_WAIT CLOSE LISTEN SYN_SENT2", names, " ")
    for (i = 1; i <= n; i++) states[names[i]] = 0
}
$1 ~ /^cpu=/ {
    for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "drop" || kv[1] == "early_drop") {
            if (kv[2] !~ /^[0-9]+$/) bad = 1
            counters[kv[1]] += kv[2]
            seen[kv[1]] = 1
        }
    }
    next
}
$1 == "udp" { udp++; next }
$1 == "tcp" {
    state = $4
    if (state !~ /^[A-Z][A-Z0-9_]*$/) { bad = 1; next }
    if (!(state in states)) names[++n] = state
    states[state]++
}
END {
    if (bad || !seen["drop"] || !seen["early_drop"]) {
        print "Invalid or missing conntrack statistics" > "/dev/stderr"
        exit 1
    }
    printf "{\"drop\":%.0f,\"early_drop\":%.0f,\"udp\":%.0f", counters["drop"], counters["early_drop"], udp
    for (i = 1; i <= n; i++) {
        key = (names[i] == "ESTABLISHED" ? "tcp_open" : "tcp_" tolower(names[i]))
        printf ",\"%s\":%.0f", key, states[names[i]]
    }
    print "}"
}'

