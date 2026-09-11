-- SAK-52889 Conversations use the shared tag service; retire legacy Taggable.
-- Run with Sakai stopped, after the Sakai 26 conversions and before starting Sakai 27.
-- Back up the database first. This script removes the obsolete source tables.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
BEGIN
    FOR fk IN (SELECT c.constraint_name FROM user_constraints c
        JOIN user_cons_columns col ON col.constraint_name = c.constraint_name
        JOIN user_constraints parent ON parent.constraint_name = c.r_constraint_name
        WHERE c.table_name = 'TAGSERVICE_TAG' AND c.constraint_type = 'R'
          AND col.column_name = 'TAGCOLLECTIONID' AND parent.table_name = 'TAGSERVICE_COLLECTION') LOOP
        EXECUTE IMMEDIATE 'ALTER TABLE tagservice_tag DROP CONSTRAINT ' || DBMS_ASSERT.ENQUOTE_NAME(fk.constraint_name);
    END LOOP;
END;
/
ALTER TABLE tagservice_collection MODIFY tagcollectionid VARCHAR2(99 CHAR);
ALTER TABLE tagservice_tag MODIFY tagcollectionid VARCHAR2(99 CHAR);
ALTER TABLE tagservice_tag ADD CONSTRAINT tagservice_tag_fk
    FOREIGN KEY (tagcollectionid) REFERENCES tagservice_collection(tagcollectionid);

DECLARE
    source_exists NUMBER;
    invalid_links NUMBER;
    links_exist NUMBER;
BEGIN
    SELECT COUNT(*) INTO source_exists FROM user_tables WHERE table_name = 'CONV_TAGS';
    SELECT COUNT(*) INTO links_exist FROM user_tables WHERE table_name = 'CONV_TOPIC_TAGS';
    IF source_exists > 0 THEN
        IF links_exist > 0 THEN
            -- Dynamic SQL permits a completed conversion to be rerun after source tables are gone.
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CONV_TOPIC_TAGS ct
              LEFT JOIN CONV_TAGS t ON t.TAG_ID = ct.TAG
              LEFT JOIN CONV_TOPICS topic ON topic.TOPIC_ID = ct.TOPIC_ID
              WHERE t.TAG_ID IS NULL OR topic.TOPIC_ID IS NULL OR t.SITE_ID <> topic.SITE_ID'
              INTO invalid_links;
            IF invalid_links > 0 THEN
                RAISE_APPLICATION_ERROR(-20001, 'SAK-52889: repair orphaned or cross-site Conversations tag links before conversion');
            END IF;
        END IF;
        EXECUTE IMMEDIATE 'INSERT INTO tagservice_collection
          (tagcollectionid, name, description, creationdate, lastmodificationdate,
           lastsynchronizationdate, externalupdate, externalcreation, lastupdatedateinexternalsystem)
          SELECT DISTINCT t.SITE_ID, t.SITE_ID, ''Site tags'', 0, 0, 0, 0, 0, 0
          FROM CONV_TAGS t WHERE NOT EXISTS
            (SELECT 1 FROM tagservice_collection c WHERE c.tagcollectionid = t.SITE_ID)';
        EXECUTE IMMEDIATE 'INSERT INTO tagservice_tag
          (tagid, tagcollectionid, taglabel, description, creationdate, lastmodificationdate,
           externalcreation, externalcreationDate, externalupdate, lastupdatedateinexternalsystem)
          SELECT ''conv-'' || LPAD(TO_CHAR(t.TAG_ID), 31, ''0''), t.SITE_ID,
            t.LABEL, t.DESCRIPTION, 0, 0, 0, 0, 0, 0 FROM CONV_TAGS t
          WHERE NOT EXISTS (SELECT 1 FROM tagservice_tag shared
            WHERE shared.tagid = ''conv-'' || LPAD(TO_CHAR(t.TAG_ID), 31, ''0''))';
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CONV_TAGS t
          LEFT JOIN tagservice_tag shared ON shared.tagid = ''conv-'' || LPAD(TO_CHAR(t.TAG_ID), 31, ''0'')
          WHERE shared.tagid IS NULL OR DECODE(shared.tagcollectionid, t.SITE_ID, 0, 1) = 1
            OR DECODE(shared.taglabel, t.LABEL, 0, 1) = 1
            OR (shared.description IS NULL AND t.DESCRIPTION IS NOT NULL)
            OR (shared.description IS NOT NULL AND t.DESCRIPTION IS NULL)
            OR DBMS_LOB.COMPARE(shared.description, TO_CLOB(t.DESCRIPTION)) <> 0'
          INTO invalid_links;
        IF invalid_links > 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'SAK-52889: migrated tag verification failed; source tables retained');
        END IF;
        IF links_exist > 0 THEN
            EXECUTE IMMEDIATE 'INSERT INTO tagservice_tagassociation (id, item_id, tag_id)
              SELECT RAWTOHEX(SYS_GUID()), ct.TOPIC_ID, ''conv-'' || LPAD(TO_CHAR(ct.TAG), 31, ''0'')
              FROM CONV_TOPIC_TAGS ct WHERE NOT EXISTS
                (SELECT 1 FROM tagservice_tagassociation a WHERE a.item_id = ct.TOPIC_ID
                  AND a.tag_id = ''conv-'' || LPAD(TO_CHAR(ct.TAG), 31, ''0''))';
        END IF;
    END IF;
    IF links_exist > 0 THEN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CONV_TOPIC_TAGS ct
          WHERE NOT EXISTS (SELECT 1 FROM tagservice_tagassociation a
            WHERE a.item_id = ct.TOPIC_ID AND a.tag_id = ''conv-'' || LPAD(TO_CHAR(ct.TAG), 31, ''0''))'
          INTO invalid_links;
        IF invalid_links > 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'SAK-52889: tag association verification failed');
        END IF;
    END IF;
    COMMIT;
    -- Each drop is independent so an interrupted cleanup can be resumed.
    IF links_exist > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE CONV_TOPIC_TAGS';
    END IF;
    IF source_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE CONV_TAGS';
    END IF;
    SELECT COUNT(*) INTO source_exists FROM user_sequences WHERE sequence_name = 'CONV_TAGS_S';
    IF source_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP SEQUENCE CONV_TAGS_S';
    END IF;
    SELECT COUNT(*) INTO source_exists FROM user_tables WHERE table_name = 'TAGGABLE_LINK';
    IF source_exists > 0 THEN
        EXECUTE IMMEDIATE 'DROP TABLE TAGGABLE_LINK';
    END IF;
END;
/
-- END SAK-52889
