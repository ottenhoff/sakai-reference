-- SAK-52889 Conversations use the shared tag service; retire legacy Taggable.
-- Run with Sakai stopped, after the Sakai 26 conversions and before starting Sakai 27.
-- Back up the database first. This script removes the obsolete source tables.
DROP PROCEDURE IF EXISTS migrate_conversations_tags_52889;
DELIMITER //
CREATE PROCEDURE migrate_conversations_tags_52889()
BEGIN
    DECLARE fk_name VARCHAR(64);
    DECLARE source_exists INT DEFAULT 0;
    DECLARE invalid_links INT DEFAULT 0;
    DECLARE links_exist INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Site IDs can be up to 99 characters. Preserve the existing collection FK.
    SELECT MAX(CONSTRAINT_NAME) INTO fk_name FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tagservice_tag'
        AND COLUMN_NAME = 'tagcollectionid' AND REFERENCED_TABLE_NAME = 'tagservice_collection';
    IF fk_name IS NOT NULL THEN
        SET @drop_tag_fk = CONCAT('ALTER TABLE tagservice_tag DROP FOREIGN KEY `', fk_name, '`');
        PREPARE tag_fk_statement FROM @drop_tag_fk;
        EXECUTE tag_fk_statement;
        DEALLOCATE PREPARE tag_fk_statement;
    END IF;
    ALTER TABLE tagservice_collection MODIFY tagcollectionid VARCHAR(99) NOT NULL;
    ALTER TABLE tagservice_tag MODIFY tagcollectionid VARCHAR(99) NOT NULL;
    ALTER TABLE tagservice_tag ADD CONSTRAINT tagservice_tag_fk
      FOREIGN KEY (tagcollectionid) REFERENCES tagservice_collection(tagcollectionid);

    SELECT COUNT(*) INTO source_exists FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'CONV_TAGS';
    SELECT COUNT(*) INTO links_exist FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'CONV_TOPIC_TAGS';
    START TRANSACTION;
    IF source_exists > 0 THEN
        IF links_exist > 0 THEN
            -- Reject orphaned or cross-site links rather than silently dropping them.
            SELECT COUNT(*) INTO invalid_links FROM CONV_TOPIC_TAGS ct
              LEFT JOIN CONV_TAGS t ON t.TAG_ID = ct.TAG
              LEFT JOIN CONV_TOPICS topic ON topic.TOPIC_ID = ct.TOPIC_ID
              WHERE t.TAG_ID IS NULL OR topic.TOPIC_ID IS NULL OR t.SITE_ID <> topic.SITE_ID;
            IF invalid_links > 0 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SAK-52889: repair orphaned or cross-site Conversations tag links before conversion';
            END IF;

        END IF;
        INSERT INTO tagservice_collection
          (tagcollectionid, name, description, creationdate, lastmodificationdate,
           lastsynchronizationdate, externalupdate, externalcreation, lastupdatedateinexternalsystem)
          SELECT DISTINCT t.SITE_ID, t.SITE_ID, 'Site tags', 0, 0, 0, 0, 0, 0
          FROM CONV_TAGS t WHERE NOT EXISTS
            (SELECT 1 FROM tagservice_collection c WHERE c.tagcollectionid = t.SITE_ID);

        -- Full-width, deterministic IDs avoid collisions with existing UUID tags and permit reruns.
        INSERT INTO tagservice_tag
          (tagid, tagcollectionid, taglabel, description, creationdate, lastmodificationdate,
           externalcreation, externalcreationDate, externalupdate, lastupdatedateinexternalsystem)
          SELECT CONCAT('conv-', LPAD(CAST(t.TAG_ID AS CHAR), 31, '0')), t.SITE_ID,
            t.LABEL, t.DESCRIPTION, 0, 0, 0, 0, 0, 0 FROM CONV_TAGS t
          WHERE NOT EXISTS (SELECT 1 FROM tagservice_tag shared
            WHERE shared.tagid = CONCAT('conv-', LPAD(CAST(t.TAG_ID AS CHAR), 31, '0')));

        SELECT COUNT(*) INTO invalid_links FROM CONV_TAGS t
          LEFT JOIN tagservice_tag shared ON shared.tagid = CONCAT('conv-', LPAD(CAST(t.TAG_ID AS CHAR), 31, '0'))
          WHERE shared.tagid IS NULL OR NOT (shared.tagcollectionid <=> t.SITE_ID)
            OR NOT (BINARY shared.taglabel <=> BINARY t.LABEL) OR NOT (BINARY shared.description <=> BINARY t.DESCRIPTION);
        IF invalid_links > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SAK-52889: migrated tag verification failed; source tables retained';
        END IF;

        IF links_exist > 0 THEN
            INSERT INTO tagservice_tagassociation (id, item_id, tag_id)
              SELECT UUID(), ct.TOPIC_ID, CONCAT('conv-', LPAD(CAST(ct.TAG AS CHAR), 31, '0'))
              FROM CONV_TOPIC_TAGS ct WHERE NOT EXISTS
                (SELECT 1 FROM tagservice_tagassociation a WHERE a.item_id = ct.TOPIC_ID
                  AND a.tag_id = CONCAT('conv-', LPAD(CAST(ct.TAG AS CHAR), 31, '0')));

        END IF;
    END IF;
    IF links_exist > 0 THEN
        SELECT COUNT(*) INTO invalid_links FROM CONV_TOPIC_TAGS ct
          WHERE NOT EXISTS (SELECT 1 FROM tagservice_tagassociation a
            WHERE a.item_id = ct.TOPIC_ID AND a.tag_id = CONCAT('conv-', LPAD(CAST(ct.TAG AS CHAR), 31, '0')));
        IF invalid_links > 0 THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SAK-52889: tag association verification failed';
        END IF;
    END IF;
    COMMIT;
    -- Each drop is independent so an interrupted cleanup can be resumed.
    DROP TABLE IF EXISTS CONV_TOPIC_TAGS;
    DROP TABLE IF EXISTS CONV_TAGS;
    DROP TABLE IF EXISTS CONV_TAGS_S;
    DROP TABLE IF EXISTS TAGGABLE_LINK;
END //
DELIMITER ;
CALL migrate_conversations_tags_52889();
DROP PROCEDURE migrate_conversations_tags_52889;
-- END SAK-52889
