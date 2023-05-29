#!/bin/bash

fail() {
	echo "$*" 1>&2
	exit 1
}

H="{{ strongswan_hostname }}"

{% if http_proxy|default(False) %}
export http_proxy={{ http_proxy }}
{% endif %}
{% if https_proxy|default(False) %}
export https_proxy={{ https_proxy }}
{% endif %}

certbot renew || fail "failed to renew certs"

OLD_CS=$( shasum /etc/ipsec.d/certs/server.crt | awk '{print $1}' )

# deploy certificates
cat /etc/letsencrypt/live/$H/chain.pem > /etc/ipsec.d/cacerts/chain.pem
cat /etc/letsencrypt/live/$H/cert.pem /etc/letsencrypt/live/$H/chain.pem > /etc/ipsec.d/certs/server.crt
cat /etc/letsencrypt/live/$H/privkey.pem > /etc/ipsec.d/private/server.key

NEW_CS=$( shasum /etc/ipsec.d/certs/server.crt | awk '{print $1}' )

# restart ipsec if sums changed
if [[ "$OLD_CS" != "$NEW_CS" ]]; then
	echo "restart ipsec"
	/etc/init.d/ipsec restart
	/etc/init.d/apache2 restart
fi
