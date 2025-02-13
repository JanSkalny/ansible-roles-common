#!/bin/bash

# avoid race conditions
flock -n /tmp/suricata-log.lock || exit 1

# compress json files after than 7 days
find /var/log/suricata/ -type f -name "*.json" -mtime +{{ suricata_eve_compress_after | default(7) }} -exec gzip {} \;

# remove json.gz files after than 90 days
find /var/log/suricata/ -type f -name "*.json.gz" -mtime +{{ suricata_eve_erase_after | default(90) }} -exec rm {} \;
