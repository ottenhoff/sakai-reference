-- SAK-52889: migrate Conversations tags and retire Taggable.
-- Run once after the Sakai 26 conversions, with Sakai stopped and a database backup.
-- Use the MySQL client without --force so SQL errors stop execution.
ALTER TABLE tagservice_tag DROP FOREIGN KEY tagservice_tag_ibfk_1;
ALTER TABLE tagservice_collection MODIFY tagcollectionid VARCHAR(99) NOT NULL;
ALTER TABLE tagservice_tag MODIFY tagcollectionid VARCHAR(99) NOT NULL;
ALTER TABLE tagservice_tag ADD CONSTRAINT tagservice_tag_fk
    FOREIGN KEY (tagcollectionid) REFERENCES tagservice_collection(tagcollectionid);

START TRANSACTION;
INSERT INTO tagservice_collection
    (tagcollectionid, name, description, creationdate, lastmodificationdate,
     lastsynchronizationdate, externalupdate, externalcreation, lastupdatedateinexternalsystem)
    SELECT DISTINCT t.SITE_ID, t.SITE_ID, 'Site tags', 0, 0, 0, 0, 0, 0
    FROM CONV_TAGS t WHERE NOT EXISTS
        (SELECT 1 FROM tagservice_collection c WHERE c.tagcollectionid = t.SITE_ID);

INSERT INTO tagservice_tag
    (tagid, tagcollectionid, taglabel, description, creationdate, lastmodificationdate,
     externalcreation, externalcreationDate, externalupdate, lastupdatedateinexternalsystem)
    SELECT CONCAT('conv-', LPAD(CAST(TAG_ID AS CHAR), 31, '0')), SITE_ID,
        LABEL, DESCRIPTION, 0, 0, 0, 0, 0, 0 FROM CONV_TAGS;

INSERT INTO tagservice_tagassociation (id, item_id, tag_id)
    SELECT UUID(), TOPIC_ID, CONCAT('conv-', LPAD(CAST(TAG AS CHAR), 31, '0'))
    FROM CONV_TOPIC_TAGS;
COMMIT;

DROP TABLE CONV_TOPIC_TAGS;
DROP TABLE CONV_TAGS;
DROP TABLE CONV_TAGS_S;
DROP TABLE TAGGABLE_LINK;
