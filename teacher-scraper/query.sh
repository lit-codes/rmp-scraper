#!/bin/bash

: ${DATA_DIR:=/data}
: ${USE_CURSOR:=}

: ${REDIS_HOST:=shared-redis}
: ${REDIS_PORT:=6379}
: ${REDIS_PASS:=password}
: ${REDIS_CONNECTION:=redis://garbage:$REDIS_PASS@$REDIS_HOST:$REDIS_PORT}
REDIS="redis-cli --no-auth-warning -u $REDIS_CONNECTION"

warn() {
    echo $@ 1>&2
}

output() {
    $REDIS -x --raw lpush teacher_ratings
}

input() {
    $REDIS brpop teachers 0 | grep -v '^teachers$'
}

incr_error_count() {
    $REDIS hincrby teacher_failure_count $1 1
}

getTeacher() {
    id=$1
    rating_cursor=${2:-0}
    # Cursor should point to the rating before :(
    (( rating_cursor-= 1 ))
    if [ -f $DATA_DIR/$id ]; then
        warn reading $id from cache
        cat $DATA_DIR/$id
        return 0
    fi
    encoded_id=`echo -n Teacher-$id |base64`
    encoded_query=`perl -pe 's/\n/\\\\n/g' query.graphql`
    encoded_query=${encoded_query::-2}
    encoded_rating_cursor=`echo -n arrayconnection:$rating_cursor |base64`
    encoded_query='{"query":"'"$encoded_query"'","variables":{"id":"'$encoded_id'","ratingCursor":"'$encoded_rating_cursor'"}}'
    curl -s 'https://www.ratemyprofessors.com/graphql' \
        -H 'Connection: keep-alive' \
        -H 'Pragma: no-cache' \
        -H 'Cache-Control: no-cache' \
        -H 'Authorization: Basic dGVzdDp0ZXN0' \
        -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.138 Safari/537.36' \
        -H 'Content-Type: application/json' \
        -H 'Accept: */*' \
        -H 'Origin: https://www.ratemyprofessors.com' \
        -H 'Sec-Fetch-Site: same-origin' \
        -H 'Sec-Fetch-Mode: cors' \
        -H 'Sec-Fetch-Dest: empty' \
        -H 'Accept-Language: en-US,en;q=0.9' \
        -H 'Cookie: ajs_user_id=null; ajs_group_id=null; ajs_anonymous_id=%22e330be45-a1d9-4f1c-9e3e-61800a141eb2%22; promotionIndex=0; ccpa-notice-viewed-02=true' \
        --data-binary "$encoded_query" \
        --compressed | tee $DATA_DIR/$id
}

while :; do
    teacher=$(input)
    teacher_id=`echo $teacher | jq '.teacherId'`
    rating_cursor=`echo $teacher | jq '.ratingCursor'`
    if [ -n "$USE_CURSOR" ]; then
        warn Scraping teacher: $teacher_id Rating: $rating_cursor
        output=$(getTeacher $teacher_id $rating_cursor)
        ratings_count=`echo -e "$output"|jq -c '.data.node.ratings.edges | length'`
        if [ $ratings_count -gt 0 ]; then
            warn "New ratings found for $teacher_id Ratings: $rating_cursor"
            echo "teacherId:$teacher_id,$output" | output
        fi
    else
        warn Scraping teacher: $teacher_id
        output=$(getTeacher $teacher_id)
        echo "teacherId:$teacher_id,$output" | output
    fi
    if [ $? == 0 ]; then
        warn "Success for: $teacher_id"
    else
        warn "Failed to get teacher: $teacher_id"
        incr_error_count $teacher_id
    fi
done
