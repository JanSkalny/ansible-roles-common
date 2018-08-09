#!/bin/bash

# Simple mysql bacula pre-backup script
# Last edit: 2016-10-26

DIR="/var/backups/mysql/"
MYSQLARGS="-u {{ backup_sql_user }} -p{{ backup_sql_password }}"

mkdir -p $DIR
DATABASES=`mysql $MYSQLARGS -B -e "SHOW DATABASES;" | grep -v '^\(performance_schema\|sys\|information_schema\|Database\)$' | xargs -L 1 -I% echo -n "% "`

for db in $DATABASES; do
	f="$DIR/$db.sql"
	mysqldump $MYSQLARGS $db > $f
done
