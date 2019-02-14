#!/bin/bash

# Simple mysql bacula pre-backup script
# Last edit: 2016-10-26

DIR={{ backup_sql_dump_dir }}
MYSQLARGS="-u {{ backup_sql_user }} -p{{ backup_sql_password }}"

mkdir -p $DIR

for db in $DATABASES; do
    ENGINE=$(mysql $MYSQLARGS --skip-column-names -e "SHOW TABLE STATUS FROM $db;" | grep -v InnoDB | wc -l)
    if [ $ENGINE -eq 0 ]; then
        DUMPARGS="--single-transaction"
    else
        DUMPARGS=""
    fi
    f="$DIR/$db.sql"
    mysqldump $MYSQLARGS $DUMPARGS $db > $f

done
