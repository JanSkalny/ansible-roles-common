#!/bin/sh
#
# simple authorized_keys updater 
# 
# requires gpg and (wget or fetch) installed
#
# howto client:
# - generate your gpg keys `gpg --gen-key`
# - create your authorized_keys
# - sign it and place somewhere on the web `gpg -a -s authorized_keys`
#
# howto remote (sshd):
# - add your public certificate into gpg `gpg --import`
# - change SRC value to reflect to your authorized_keys source
# - chnage MYSIG value to public key id `gpg -k --with-colons | grep pub | cut -d':' -f 5`
# - setup crontab for this script `crontab -e`
# 
# johnny ^_^ <johnny@netvor.sk>
# 2008-09-17
# kofolaware (http://netvor.sk/~johnny/kofola-ware)
#
# -----------------------------------------------------------------------------

SRC="http://netvor.sk/~johnny/authorized_keys.asc"
MYSIG="E8E579071042824A"

PATH="$PATH:/usr/local/bin:/usr/bin"

# use wget or fetch?
if [ -x /usr/local/bin/wget ] || [ -x /usr/bin/wget ]; then
	get="wget -q -O - "
else
	get="fetch -q -o - "
fi

mkdir -p "$HOME/.ssh"

# fetch authorized_keys.asc, verify file...
# and write valid results into authorized_keys
$get "$SRC" | gpg -o "$HOME/.ssh/authorized_keys.new" --yes --status-fd 1 -d - 2>&1 | grep "GOODSIG $MYSIG" > /dev/null

if [ $? -ne "0" ]; then
	echo "failed to update authorized_keys" 1>&2
else
	mv "$HOME/.ssh/authorized_keys.new" "$HOME/.ssh/authorized_keys"
fi

