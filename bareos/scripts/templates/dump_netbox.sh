#!/bin/bash
set -euo pipefail

mkdir -p /var/backups/netbox/
docker exec netbox-docker-postgres-1 pg_dump -U netbox > /var/backups/netbox/netbox.sql
docker run --rm --volumes-from netbox-docker-netbox-1 -v /var/backups/netbox:/backup ubuntu tar -C "/opt/netbox/netbox/media" -c -z -v -f /backup/media_$(date +%F).tar.gz .
