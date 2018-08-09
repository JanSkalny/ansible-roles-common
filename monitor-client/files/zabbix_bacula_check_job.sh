#!/bin/bash

fail() {
	echo "$*" 1>&1
	exit 1
}

# load database configuration form bacula-dir.conf
export $( grep -i "dbname" /etc/bacula/bacula-dir.conf | grep -v '^#' | head -n 1 | sed 's/ //g' | sed 's/;/\n/g' | sed 's/"//g' )

JOB="$1"
FIELD="$2"
LEVEL="$3"

# validate input
[[ "$JOB" =~ ^[a-z0-9\.-]*$ ]] || fail "invalid job id"
[[ "$FIELD" =~ ^(jobbytes|duration|lastexecution|jobstatus)$ ]] || fail "invalid field selected" 
[[ "$LEVEL" =~ ^([dfiDFI]|)$ ]] || fail "invalid level selected"

SQL_WHERE="name='$JOB'"
SQL_FIELD="$FIELD"

case "$FIELD" in
lastexecution)
	SQL_FIELD="TIMESTAMPDIFF(SECOND,EndTime,NOW())"
	;;
jobbytes)
	SQL_WHERE="name='$JOB' AND jobstatus='T' AND level='$LEVEL'"
	;;
duration)
	SQL_WHERE="name='$JOB' AND jobstatus='T' AND level='$LEVEL'"
	SQL_FIELD="TIMESTAMPDIFF(SECOND,StartTime,EndTime)"
esac

Q="SELECT $SQL_FIELD FROM Job WHERE $SQL_WHERE ORDER BY jobid DESC LIMIT 1 OFFSET 0"

/usr/bin/mysql -u $dbuser -p$dbpassword -D $dbname -e "$Q" --skip-column-names 2>/dev/null
#echo $status_job

