#!/usr/bin/env python3

import os
import sys
import re
import json
from base64 import b64decode
import psycopg2
from redis import Redis

def enterSchool(db, school):
    departments = school['departments']
    ratings = school['ratings']

    db.run("INSERT INTO school VALUES (%(legacyId)s, %(name)s, %(state)s, %(city)s) on conflict do nothing", school)

    for rating in ratings:
        rating['schoolId'] = school['legacyId']
        rating['crTimestamp'] = int(rating['crTimestamp'] / 1000)
        db.run("""
            INSERT INTO school_ratings (
                id,
                condition,
                location,
                career_opportunities,
                events,
                comment,
                creation_date,
                food,
                internet,
                library,
                reputation,
                safety,
                satisfaction,
                activities,
                status,
                time,
                helpful_votes,
                not_helpful_votes,
                school_id
            ) VALUES (
                %(id)s,
                %(crCampusCondition)s,
                %(crCampusLocation)s,
                %(crCareerOpportunities)s,
                %(crClubAndEventActivities)s,
                %(crComments)s,
                %(crCreateDate)s,
                %(crFoodQuality)s,
                %(crInternetSpeed)s,
                %(crLibraryCondition)s,
                %(crSchoolReputation)s,
                %(crSchoolSafety)s,
                %(crSchoolSatisfaction)s,
                %(crSocialActivities)s,
                %(crStatus)s,
                to_timestamp(%(crTimestamp)s),
                %(helpCount)s,
                %(notHelpCount)s,
                %(schoolId)s
            ) on conflict do nothing
        """, rating)

    for department in departments:
        db.run("INSERT INTO department VALUES (%(id)s, %(name)s) on conflict do nothing", department)
        db.run("INSERT INTO school_departments VALUES (%s, %s) on conflict do nothing", (school['legacyId'], department['id']))

class FileDB:
    def __init__(self):
        self.query = ''
    def mogrify(self, query, params):
        if isinstance(params, dict):
            params_copy = params.copy()
            for key in params_copy:
                if isinstance(params_copy[key], dict) or isinstance(params_copy[key], list):
                    continue
                adapted = psycopg2.extensions.adapt(params_copy[key])
                if isinstance(params_copy[key], str):
                    adapted.encoding = "utf-8"
                params_copy[key] = adapted.getquoted().decode('utf8')
        else:
            params_copy = params
        return query % params_copy
    def run(self, query, params=()):
        if 'comment' in params:
            params['comment'] = params['comment'].replace('\x00', ' ')
        self.query += self.mogrify(query, params) + ';\n'
    def get(self):
        return self.query

if __name__ == '__main__':
    redis_host = os.environ.get('REDIS_HOST') or 'shared-redis'
    redis_port = os.environ.get('REDIS_PORT') or 6379
    redis = Redis(host=redis_host, port=redis_port)
    while True:
        db = FileDB()
        stored_value = redis.brpop(['school_ratings'], timeout = 0)[1].decode('utf8')
        regex = re.compile(r'schoolId:(\d+),(.*)', re.DOTALL|re.MULTILINE)
        match = re.match(regex, stored_value)

        schoolId = match.group(1)
        print('Generating SQL for school: %s' % schoolId)
        db.run("--schoolId:%s", schoolId)

        try:
            payload = json.loads(match.group(2))
        except Exception as e:
            redis.hincrby('school_failure_count', schoolId, 1)
            print('Invalid JSON response for %s' % schoolId, flush=True)
            continue

        if not payload:
            redis.hincrby('school_failure_count', schoolId, 1)
            continue

        try:
            print('School added: %s' % schoolId, flush=True)
            payload['legacyId'] = schoolId
            enterSchool(db, payload)
            redis.lpush('school_rating_sqls', db.get())
        except Exception as e:
            print('Failed adding school %s, error is: %s' % (schoolId, str(e)), flush=True)
            redis.hincrby('school_failure_count', schoolId, 1)
