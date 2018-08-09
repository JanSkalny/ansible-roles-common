CREATE TABLE `access` (
  `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  `source` varchar(128) NOT NULL DEFAULT '',
  `access` varchar(128) NOT NULL DEFAULT '',
  `type` enum('recipient','sender','client') NOT NULL DEFAULT 'recipient',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

