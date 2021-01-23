#!/bin/bash

: ${CACHE_DIR:=/tmp}
: ${DATA_DIR:=/data}
: ${REDIS_HOST:=shared-redis}
: ${REDIS_PORT:=6379}
: ${REDIS_CONNECTION:=redis://$REDIS_HOST:$REDIS_PORT}

output() {
    redis-cli -u $REDIS_CONNECTION -x --raw lpush school_ratings
}

input() {
    redis-cli -u $REDIS_CONNECTION brpop schools 0 | grep -v '^schools$'
}

incr_error_count() {
    redis-cli -u $REDIS_CONNECTION hincrby school_failure_count $1 1
}

querySchool() {
    id=$1
    encoded_id=`echo -n School-$id |base64`
    encoded_query=`perl -pe 's/\n/\\\\n/g' query.graphql`
    encoded_query=${encoded_query::-2}
    encoded_query='{"query":"'"$encoded_query"'","variables":{"id":"'$encoded_id'"}}'
    curl -fs 'https://www.ratemyprofessors.com/graphql' \
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
        --compressed
    return $?
}

getSchool() {
    sid=$1
    if [ -f $DATA_DIR/$sid ]; then
        cat $DATA_DIR/$sid
        return 0
    fi
    for i in {1..10000}; do
        file=$CACHE_DIR/$sid-$i
        curl -o $file -fs https://www.ratemyprofessors.com/campusrating/paginatecampusRatings\?page\=$i\&sid\=$sid
        if ! grep '"remaining' $file &>/dev/null; then
            echo not found $sid
            rm $CACHE_DIR/$sid-*
            return 1
        fi
        if grep '"remaining":0' $file &>/dev/null; then
            cat $CACHE_DIR/$sid-* | jq -s 'reduce .[] as $s ([]; . + $s.ratings)|{ratings: .}' > $CACHE_DIR/$sid-flatten
            querySchool $sid |jq -s '.[0].data.node' > $CACHE_DIR/$sid-query
            jq -s '.[0] + .[1]' $CACHE_DIR/$sid-flatten $CACHE_DIR/$sid-query | tee -a $DATA_DIR/$sid
            rm $CACHE_DIR/$sid-*
            return 0
        fi
    done
    return $?
}

while :; do
    school=$(input)
    echo Scraping school: $school
    output=$(getSchool $school)
    echo "schoolId:$school,$output" | output
    if [ $? == 0 ]; then
        echo "School added: $school"
    else
        echo "Failed to get school: $school"
        incr_error_count $school
    fi
done
