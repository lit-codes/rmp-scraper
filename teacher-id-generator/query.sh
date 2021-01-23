#!/bin/bash

: ${GENERATOR:=currentTeachers}
#  Generators:
## currentTeachers: Get all ratings for the current teachers in the database
## sequentialIds: Generate IDs from 1 to MAX_GENERATED_ID, and get ratings for all
## updateRatings: Update the existing ratings, do not change old ratings
: ${BATCH_SIZE:=20}
: ${EMPTY_QUEUE_THRESHOLD:=10}
: ${CACHE_DIR:=/data/}
: ${SLEEP_FULL_QUEUE:=1}
: ${MAX_GENERATED_ID:=2500000}

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

maxId() {
    $PSQL -c 'SELECT max(id) FROM teacher' | xargs
}

getCurrentTeachers() {
    $PSQL <<'EOQ'
    SELECT array_to_json(array_agg(row_to_json(t_to_tr))) FROM (
        SELECT id AS "teacherId"
          FROM teacher
      GROUP BY id
      ORDER BY id
    ) AS t_to_tr;
EOQ
}

getRatingCursors() {
    $PSQL <<'EOQ'
    SELECT array_to_json(array_agg(row_to_json(t_to_tr))) FROM (
        SELECT t.id AS "teacherId", count(tr.*) AS "ratingCursor"
          FROM teacher AS t
          JOIN teacher_ratings AS tr
            ON teacher_id = t.id
      GROUP BY t.id
      ORDER BY t.id
    ) AS t_to_tr;
EOQ
}

currentTeachers() {
    getCurrentTeachers | jq -c '.[]'
}

updateRatings() {
    getRatingCursors | jq -c '.[]'
}

sequentialIds() {
    max_id=$(maxId)
    : ${max_id:=1}
    for i in `eval "echo -n {$max_id..$MAX_GENERATED_ID} | xargs -d' ' -IXXX echo '{\"teacherId\":XXX}'"`;do echo $i;done
}

nextId() {
    generator=${1:-currentTeachers}
    RATINGS=$CACHE_DIR/rating_cursors
    BATCH=$CACHE_DIR/batch

    if [ ! -e $RATINGS ];then
        $generator > $RATINGS
        echo > $BATCH
    fi


    if [ -z "$(cat $BATCH)" ]; then
        head -n$BATCH_SIZE $RATINGS > $BATCH
        sed -i "1,${BATCH_SIZE}d" $RATINGS
    fi

    head -n1 $BATCH
    sed -i '1d' $BATCH
}

getNextBatch() {
    generator="$1"
    ids=''
    size=0
    while [ $size -lt $BATCH_SIZE ];do
        payload=`nextId $generator`
        id=`echo $payload | jq '.teacherId'`
        if [ -z "$id" ];then
            echo "$ids"
            return 1
        fi
        ids+=" $payload"
        (( size+=1 ))
    done
    echo "$ids"
}

generateRange() {
    ids=$(getNextBatch $1)
    error_code=$?
    test -z "$ids" && return 1
    warn range added: $ids
    $REDIS lpush teachers $ids
    return $error_code
}

queueIsEmpty() {
    len_sqls=`$REDIS llen teacher_rating_sqls | grep -oP '\d+'`
    len_ratings=`$REDIS llen teacher_ratings | grep -oP '\d+'`
    len=`$REDIS llen teachers | grep -oP '\d+'`
    : ${len_sqls:=0}
    : ${len_ratings:=0}
    : ${len:=0}
    (( total=$len + $len_ratings + $len_sqls ))
    test $total -le $EMPTY_QUEUE_THRESHOLD
    return $?
}

while queueIsEmpty; do
    if ! generateRange $GENERATOR; then
        exit 0
    fi
    sleep $SLEEP_FULL_QUEUE
done
