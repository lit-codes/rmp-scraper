#!/bin/bash

: ${REDIS_HOST:=shared-redis}
: ${REDIS_PORT:=6379}
: ${REDIS_PASS:=password}
: ${REDIS_CONNECTION:=redis://garbage:$REDIS_PASS@$REDIS_HOST:$REDIS_PORT}
REDIS="redis-cli --no-auth-warning -u $REDIS_CONNECTION"

: ${DB_HOST:=shared-db}
: ${DB_PORT:=5432}
: ${DB_USER:=rmp}
: ${DB_PASS:=pass}
: ${DB_NAME:=rmp}
: ${DB_CONNECTION:=postgres://$DB_HOST:$DB_PORT/$DB_NAME?user=$DB_USER&password=$DB_PASS}
PSQL="psql -v ON_ERROR_STOP=1 -t -d $DB_CONNECTION"

warn() {
    echo $@ 1>&2
}

apply() {
    $PSQL >/dev/null
}

getSQL() {
    $REDIS brpop teacher_rating_sqls 0 | grep -v '^teacher_rating_sqls$'
}

incr_error_count() {
    $REDIS hincrby teacher_failure_count $1 1
}

while :; do
    sql=$(getSQL)
    teacherId=`echo $sql | grep -oP -- '--teacherId:\K\d+'`
    warn "Applying SQL for teacher: $teacherId"
    echo "$sql" | apply
    if [ $? == 0 ]; then
        warn "Teacher $teacherId added"
    else
        warn "Failed to apply SQL for $teacherId"
        incr_error_count $teacherId
    fi
done
