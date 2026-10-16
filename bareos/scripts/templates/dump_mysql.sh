#!/usr/bin/env bash
set -euo pipefail
umask 077

DIR=/var/backups/mysql
AUTH=(
    --user={{ bareos_mysql_user | quote }}
{% if bareos_mysql_password is defined %}
    --password={{ bareos_mysql_password | quote }}
{% endif %}
)

mkdir -p "$DIR"

mysql "${AUTH[@]}" -NBe 'SHOW DATABASES' |
while IFS= read -r db; do
    case "$db" in
        information_schema|performance_schema|sys) continue ;;
    esac

    qdb=${db//\`/\`\`}
    status=$(mysql "${AUTH[@]}" -NBe "SHOW TABLE STATUS FROM \`$qdb\`")

    if awk '$2 && $2!="InnoDB" && $2!="NULL" {exit 1}' <<<"$status"; then
        option=--single-transaction
    else
        option=--lock-tables
    fi

    mysqldump "${AUTH[@]}" "$option" "$db" >"$DIR/$db.sql"
done
