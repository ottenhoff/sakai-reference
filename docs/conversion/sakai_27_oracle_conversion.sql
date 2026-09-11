-- SAK-52889: migrate Conversations tags and retire Taggable.
-- Run once after the Sakai 26 conversions, with Sakai stopped and a database backup.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
ALTER TABLE tagservice_tag DROP CONSTRAINT tagservice_tag_fk;
ALTER TABLE tagservice_collection MODIFY tagcollectionid VARCHAR2(99 CHAR);
ALTER TABLE tagservice_tag MODIFY tagcollectionid VARCHAR2(99 CHAR);
ALTER TABLE tagservice_tag ADD CONSTRAINT tagservice_tag_fk
    FOREIGN KEY (tagcollectionid) REFERENCES tagservice_collection(tagcollectionid);

INSERT INTO tagservice_collection
    (tagcollectionid, name, description, creationdate, lastmodificationdate,
     lastsynchronizationdate, externalupdate, externalcreation, lastupdatedateinexternalsystem)
    SELECT DISTINCT t.SITE_ID, t.SITE_ID, 'Site tags', 0, 0, 0, 0, 0, 0
    FROM CONV_TAGS t WHERE NOT EXISTS
        (SELECT 1 FROM tagservice_collection c WHERE c.tagcollectionid = t.SITE_ID);

INSERT INTO tagservice_tag
    (tagid, tagcollectionid, taglabel, description, creationdate, lastmodificationdate,
     externalcreation, externalcreationDate, externalupdate, lastupdatedateinexternalsystem)
    SELECT 'conv-' || LPAD(TO_CHAR(TAG_ID), 31, '0'), SITE_ID,
        LABEL, DESCRIPTION, 0, 0, 0, 0, 0, 0 FROM CONV_TAGS;

INSERT INTO tagservice_tagassociation (id, item_id, tag_id)
    SELECT RAWTOHEX(SYS_GUID()), TOPIC_ID, 'conv-' || LPAD(TO_CHAR(TAG), 31, '0')
    FROM CONV_TOPIC_TAGS;
COMMIT;

DROP TABLE CONV_TOPIC_TAGS;
DROP TABLE CONV_TAGS;
DROP SEQUENCE CONV_TAGS_S;
DROP TABLE TAGGABLE_LINK;
