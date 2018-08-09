#!/bin/bash

echo ""
echo "== renewing ssl certificates"
/root/ssl/certbot-auto renew -c cli.ini

echo ""
echo "== syncing certificates to other machines & services"
/root/ssl/sync.sh

