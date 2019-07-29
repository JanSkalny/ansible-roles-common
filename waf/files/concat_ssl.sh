#!/bin/bash

DOMAINS=$( ls /etc/letsencrypt/live/ | grep -v README )

#XXX: acmetool want:
# certbot -n --standalone --email admin@netvor.sk --agree-tos --http-01-port 402 -d misp.netvor.sk certonly

# try to renew letsencrypt certificates
/usr/bin/certbot -q -n --standalone --http-01-port 402 renew

# concatenate certificates, so haproxy can accept them...
MODIFIED=0
for DOMAIN in $DOMAINS; do
	PEM="/etc/haproxy/ssl/$DOMAIN.pem"

	# concat certificates together
	ORIG_SUM=$( sha1sum $PEM 2>/dev/null )
	cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem > $PEM
	NEW_SUM=$( sha1sum $PEM 2>/dev/null )

	[[ "x$ORIG_SUM" == "x$NEW_SUM" ]] || MODIFIED=1
done

# reload haproxy, if there was any change
[[ $MODIFIED -eq 1 ]] && /etc/init.d/haproxy reload

exit 0
