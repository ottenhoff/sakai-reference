#!/usr/bin/env python3
"""Run SAK-52889 MySQL conversion checks in a disposable Docker container."""
import pathlib
import subprocess
import time
import uuid

root = pathlib.Path(__file__).resolve().parent
fixture = (root / "SAK-52889-fixture.sql").read_text()
migration = (root.parent / "sakai_27_mysql_conversion.sql").read_text()
container = "sakai-tags-test-" + uuid.uuid4().hex[:12]


def sql(statement, database=None, check=True):
    command = ["docker", "exec", "-i", container, "mysql", "--protocol=TCP", "-h127.0.0.1", "-uroot", "-N", "-B"]
    if database:
        command.append(database)
    result = subprocess.run(command, input=statement, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr)
    return result


try:
    subprocess.run(["docker", "run", "--detach", "--rm", "--name", container,
                    "-e", "MYSQL_ALLOW_EMPTY_PASSWORD=yes", "mysql:8.4"], check=True)
    for attempt in range(60):
        if sql("SELECT 1", check=False).returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError("MySQL did not become ready")

    for name in ["valid_tags", "invalid_links", "id_collision"]:
        sql("CREATE DATABASE " + name + " CHARACTER SET utf8mb4")
        sql(fixture, name)

    sql(migration, "valid_tags")
    sql(migration, "valid_tags")  # completed migrations can be rerun
    result = sql("SELECT COUNT(*) FROM tagservice_tag; SELECT COUNT(*) FROM tagservice_tagassociation;", "valid_tags")
    assert result.stdout.splitlines() == ["4", "2"], result.stdout
    result = sql("SELECT taglabel, description FROM tagservice_tag WHERE tagcollectionid LIKE 'a-site%';", "valid_tags")
    assert result.stdout.strip() == "数学 😊\tUnicode description", result.stdout
    result = sql("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='valid_tags' AND table_name IN ('CONV_TAGS','CONV_TOPIC_TAGS','TAGGABLE_LINK','CONV_TAGS_S');", "valid_tags")
    assert result.stdout.strip() == "0", result.stdout

    sql("INSERT INTO CONV_TOPIC_TAGS VALUES ('topic-one', 3)", "invalid_links")
    result = sql(migration, "invalid_links", check=False)
    assert result.returncode != 0 and "cross-site" in result.stderr, result.stderr
    assert sql("SELECT COUNT(*) FROM CONV_TAGS", "invalid_links").stdout.strip() == "3"
    sql("DELETE FROM CONV_TOPIC_TAGS WHERE TOPIC_ID='topic-one' AND TAG=3", "invalid_links")
    sql(migration, "invalid_links")  # retry after correcting bad source data

    sql("INSERT INTO tagservice_tag (tagid,tagcollectionid,taglabel) VALUES (CONCAT('conv-',LPAD('1',31,'0')),'site-one','Conflicting data')", "id_collision")
    result = sql(migration, "id_collision", check=False)
    assert result.returncode != 0 and "verification failed" in result.stderr, result.stderr
    assert sql("SELECT COUNT(*) FROM CONV_TAGS", "id_collision").stdout.strip() == "3"
    print("PASS: preservation, long site IDs, Unicode, rerun, invalid links, and ID collision")
finally:
    subprocess.run(["docker", "rm", "--force", container], check=False)
