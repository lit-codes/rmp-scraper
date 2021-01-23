#!/usr/bin/env python3

import os
import sys
import re
import json
from base64 import b64decode
import psycopg2
from redis import Redis

def enterTeacher(db, teacher):
    db.run('set time zone UTC')

    school = teacher['school']
    if school:
        teacher['schoolId'] = school['legacyId']
        db.run("INSERT INTO school VALUES (%(legacyId)s, %(name)s, %(state)s, %(city)s) on conflict do nothing", school)
    else:
        teacher['schoolId'] = None

    db.run("""
        INSERT INTO teacher VALUES (
            %(legacyId)s,
            %(firstName)s,
            %(lastName)s,
            (select id from department where name = %(department)s),
            %(schoolId)s
        ) ON CONFLICT DO NOTHING
    """, teacher)

    for tag in teacher['teacherRatingTags']:
        tag['teacherId'] = teacher['legacyId']
        db.run("""
            INSERT INTO teacher_tags (
                id,
                name,
                count,
                teacher_id
            ) VALUES (
                %(legacyId)s,
                %(tagName)s,
                %(tagCount)s,
                %(teacherId)s
            ) ON CONFLICT (id) DO UPDATE SET (
                count
            ) = ROW(
                EXCLUDED.count
            )
        """, tag)

    for related_teacher in teacher['relatedTeachers']:
        related_teacher['teacherId'] = teacher['legacyId']
        db.run("""
            INSERT INTO related_teachers (
                teacher_id,
                related_teacher_id
            ) VALUES (
                %(teacherId)s,
                %(legacyId)s
            ) ON CONFLICT DO NOTHING
        """, related_teacher)

    for edge in teacher['ratings']['edges']:
        rating = edge['node']
        rating['teacherId'] = teacher['legacyId']
        db.run("""
            INSERT INTO teacher_ratings (
                id,
                admin_review_timestamp,
                is_attendance_mandatory,
                clarity,
                class_name,
                comment,
                is_for_credit,
                timestamp,
                difficulty,
                grade,
                helpful,
                is_online_class,
                tags,
                is_textbook_used,
                helpful_votes,
                not_helpful_votes,
                is_retake_worthy,
                teacher_id
            ) VALUES (
                %(legacyId)s,
                to_timestamp(%(adminReviewedAt)s, 'YYYY-MM-DD hh24:mi:ss'),
                (select (case when %(attendanceMandatory)s is null then null else (case when lower(%(attendanceMandatory)s) like 'y%%' or lower(%(attendanceMandatory)s) = 'mandatory' then 1 else 0 end)::boolean end)),
                %(clarityRating)s,
                %(class)s,
                %(comment)s,
                %(isForCredit)s::boolean,
                to_timestamp(%(date)s, 'YYYY-MM-DD hh24:mi:ss'),
                %(difficultyRating)s,
                %(grade)s,
                %(helpfulRating)s,
                %(isForOnlineClass)s,
                %(ratingTags)s,
                (select (case when %(textbookUse)s is null then null else (case when %(textbookUse)s > 2 then 1 else 0 end)::boolean end)),
                %(thumbsUpTotal)s,
                %(thumbsDownTotal)s,
                %(wouldTakeAgain)s::boolean,
                %(teacherId)s
            ) ON CONFLICT (id) DO UPDATE SET (
                admin_review_timestamp,
                is_attendance_mandatory,
                is_for_credit,
                timestamp,
                is_textbook_used
            ) = ROW(
                EXCLUDED.admin_review_timestamp,
                EXCLUDED.is_attendance_mandatory,
                EXCLUDED.is_for_credit,
                EXCLUDED.timestamp,
                EXCLUDED.is_textbook_used
            )
        """, rating)


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
    redis_pass = os.environ.get('REDIS_PASS') or None
    redis = Redis(host=redis_host, port=redis_port, password=redis_pass)
    while True:
        db = FileDB()
        stored_value = redis.brpop(['teacher_ratings'], timeout = 0)[1].decode('utf8')
        regex = re.compile(r'teacherId:(\d+),(.*)', re.DOTALL|re.MULTILINE)
        match = re.match(regex, stored_value)

        teacherId = match.group(1)
        print('Generating SQL for teacher: %s' % teacherId)
        db.run("--teacherId:%s", teacherId)

        try:
            payload = json.loads(match.group(2))['data']['node']
        except Exception as e:
            redis.hincrby('teacher_failure_count', teacherId, 1)
            print('Invalid JSON response for %s' % teacherId, flush=True)
            continue

        if not payload:
            redis.hincrby('teacher_failure_count', teacherId, 1)
            continue

        try:
            print('Teacher added: %s' % teacherId, flush=True)
            payload['legacyId'] = teacherId
            enterTeacher(db, payload)
            redis.lpush('teacher_rating_sqls', db.get())
        except Exception as e:
            print('Failed adding teacher %s, error is: %s' % (teacherId, str(e)), flush=True)
            redis.hincrby('teacher_failure_count', teacherId, 1)
