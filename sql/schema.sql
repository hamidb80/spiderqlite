PRAGMA encoding="UTF-8";

-- tables

CREATE TABLE IF NOT EXISTS nodes (
    id          INTEGER PRIMARY KEY,
    tag         TEXT,
    data        JSON NOT NULL
);

CREATE TABLE IF NOT EXISTS edges (
    id          INTEGER PRIMARY KEY,
    tag         TEXT,
    data        JSON    NOT NULL,
    source      INTEGER,
    target      INTEGER,

    FOREIGN KEY (source) REFERENCES nodes(id),
    FOREIGN KEY (target) REFERENCES nodes(id)
);

-- indexes

CREATE INDEX IF NOT EXISTS node_index         ON nodes(id);
CREATE INDEX IF NOT EXISTS node_tag_index     ON nodes(tag);

CREATE INDEX IF NOT EXISTS edges_index        ON edges(id);
CREATE INDEX IF NOT EXISTS edges_source_index ON edges(source);
CREATE INDEX IF NOT EXISTS edges_target_index ON edges(target);
