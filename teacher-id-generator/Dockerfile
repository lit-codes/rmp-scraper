FROM alpine

RUN apk update && apk add --no-cache wget
RUN apk add --no-cache \
grep \
perl \
curl \
bash \
redis \
postgresql-client \
jq

WORKDIR /opt/

COPY . .

ENTRYPOINT ["/opt/query.sh"]
