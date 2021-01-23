FROM alpine

RUN apk update && apk add --no-cache wget
RUN apk add --no-cache \
python3 \
py3-pip \
py3-psycopg2
RUN pip3 install redis

WORKDIR /opt/

COPY . .

ENTRYPOINT ["/opt/generate_sql.py"]
