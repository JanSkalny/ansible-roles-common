#!/bin/bash

DIR={{ backup_sql_dump_dir }}/pgsql
mkdir -p $DIR
chown postgres:postgres $DIR
PSQL_PREPEND="sudo -u postgres "
DB_LIST=$($PSQL_PREPEND psql -t -l | awk '{print $1;}' | grep -v "^|$" | grep -v "^$" | grep -v "template0\|template1\|postgres")

for db in $DB_LIST; do
    f="$DIR/$db.sql"
    $PSQL_PREPEND pg_dump -f $f $db
done
