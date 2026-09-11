CREATE TABLE IF NOT EXISTS `tagservice_collection` (
  `tagcollectionid` CHAR(36) PRIMARY KEY,
  `description` TEXT,
  `externalsourcename` VARCHAR(255) UNIQUE,
  `externalsourcedescription` TEXT,
  `name` VARCHAR(255) UNIQUE,
  `createdby` VARCHAR(255),
  `creationdate` BIGINT,
  `lastmodifiedby` VARCHAR(255),
  `lastmodificationdate` BIGINT,
  `lastsynchronizationdate` BIGINT,
  `externalupdate` BOOLEAN,
  `externalcreation` BOOLEAN,
  `lastupdatedateinexternalsystem` BIGINT
);

CREATE TABLE IF NOT EXISTS `tagservice_tag` (
  `tagid` CHAR(36) PRIMARY KEY,
  `tagcollectionid` CHAR(36) NOT NULL,
  `externalid` VARCHAR(255),
  `taglabel` VARCHAR(255),
  `description` TEXT,
  `alternativelabels` TEXT,
  `createdby` VARCHAR(255),
  `creationdate` BIGINT,
  `externalcreation` BOOLEAN,
  `externalcreationDate` BIGINT,
  `externalupdate` BOOLEAN,
  `lastmodifiedby` VARCHAR(255),
  `lastmodificationdate` BIGINT,
  `lastupdatedateinexternalsystem` BIGINT,
  `parentid` VARCHAR(255),
  `externalhierarchycode` TEXT,
  `externaltype` VARCHAR(255),
  `data` TEXT,
  INDEX tagservice_tag_taglabel (taglabel),
  INDEX tagservice_tag_tagcollectionid (tagcollectionid),
  INDEX tagservice_tag_externalid (externalid),
  FOREIGN KEY (tagcollectionid)
  REFERENCES tagservice_collection(tagcollectionid)
    ON DELETE RESTRICT
);



CREATE TABLE tagservice_tagassociation (id VARCHAR(99) PRIMARY KEY, item_id VARCHAR(255), tag_id VARCHAR(255), UNIQUE(tag_id,item_id));
CREATE TABLE CONV_TAGS (TAG_ID BIGINT PRIMARY KEY, SITE_ID VARCHAR(99), LABEL VARCHAR(255), DESCRIPTION TEXT);
CREATE TABLE CONV_TOPICS (TOPIC_ID VARCHAR(36) PRIMARY KEY, SITE_ID VARCHAR(99));
CREATE TABLE CONV_TOPIC_TAGS (TOPIC_ID VARCHAR(36), TAG BIGINT, PRIMARY KEY(TOPIC_ID,TAG));
CREATE TABLE CONV_TAGS_S (next_val BIGINT);
CREATE TABLE TAGGABLE_LINK (LINK_ID VARCHAR(36));
INSERT INTO tagservice_collection (tagcollectionid,name) VALUES ('site-one','site-one');
INSERT INTO tagservice_tag (tagid,tagcollectionid,taglabel) VALUES ('existing-tag','site-one','Same label');
INSERT INTO CONV_TAGS VALUES (1,'site-one','Same label','Original description'), (2,'site-one','Unattached','Preserve unused tags'), (3,'a-site-id-longer-than-thirty-six-characters-for-testing','数学 😊','Unicode description');
INSERT INTO CONV_TOPICS VALUES ('topic-one','site-one'),('topic-two','a-site-id-longer-than-thirty-six-characters-for-testing');
INSERT INTO CONV_TOPIC_TAGS VALUES ('topic-one',1),('topic-two',3);
