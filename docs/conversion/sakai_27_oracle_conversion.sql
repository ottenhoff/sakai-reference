-- SAK-52889 Conversations use the shared tag service; retire legacy Taggable.
-- Run with Sakai stopped, after the Sakai 26 conversions and before starting Sakai 27.
-- Back up the database first. This script removes the obsolete source tables.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
ALTER TABLE tagservice_collection MODIFY tagcollectionid VARCHAR2(99 CHAR);
ALTER TABLE tagservice_tag MODIFY tagcollectionid VARCHAR2(99 CHAR);

DECLARE
    source_exists NUMBER;
    invalid_links NUMBER;
BEGIN
    SELECT COUNT(*) INTO source_exists FROM user_tables WHERE table_name = 'CONV_TAGS';
    IF source_exists > 0 THEN
        -- Dynamic SQL permits a completed conversion to be rerun after source tables are gone.
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CONV_TOPIC_TAGS ct
          LEFT JOIN CONV_TAGS t ON t.TAG_ID = ct.TAG
          LEFT JOIN CONV_TOPICS topic ON topic.TOPIC_ID = ct.TOPIC_ID
          WHERE t.TAG_ID IS NULL OR topic.TOPIC_ID IS NULL OR t.SITE_ID <> topic.SITE_ID'
          INTO invalid_links;
        IF invalid_links > 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'SAK-52889: repair orphaned or cross-site Conversations tag links before conversion');
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
        EXECUTE IMMEDIATE 'INSERT INTO tagservice_tagassociation (id, item_id, tag_id)
          SELECT RAWTOHEX(SYS_GUID()), ct.TOPIC_ID, ''conv-'' || LPAD(TO_CHAR(ct.TAG), 31, ''0'')
          FROM CONV_TOPIC_TAGS ct WHERE NOT EXISTS
            (SELECT 1 FROM tagservice_tagassociation a WHERE a.item_id = ct.TOPIC_ID
              AND a.tag_id = ''conv-'' || LPAD(TO_CHAR(ct.TAG), 31, ''0''))';
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CONV_TOPIC_TAGS ct
          WHERE NOT EXISTS (SELECT 1 FROM tagservice_tagassociation a
            WHERE a.item_id = ct.TOPIC_ID AND a.tag_id = ''conv-'' || LPAD(TO_CHAR(ct.TAG), 31, ''0''))'
          INTO invalid_links;
        IF invalid_links > 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'SAK-52889: tag association verification failed');
        END IF;
        COMMIT;
        EXECUTE IMMEDIATE 'DROP TABLE CONV_TOPIC_TAGS';
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
