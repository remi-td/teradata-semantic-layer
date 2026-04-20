-- Global temporary table used by export procedures to buffer YAML lines.
-- Materialized instance is session-local; catalog entry is persistent.
CREATE GLOBAL TEMPORARY TABLE demo_user.yaml_tmp
(
    line_no    INTEGER NOT NULL,
    line_text  VARCHAR(32000) CHARACTER SET UNICODE
)
PRIMARY INDEX (line_no)
ON COMMIT PRESERVE ROWS;
