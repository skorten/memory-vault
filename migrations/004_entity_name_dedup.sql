-- Memory Vault — Entity dedup by name only (drop type from unique key)
--
-- The prior unique index on (lower(name), type, space_id) allowed the same
-- entity name with different NER-assigned types to create separate graph nodes
-- (e.g. "CloudZero" as Project vs "Cloudzero" as Tool).  Dedup should be
-- case-insensitive by name within a space, regardless of NER type.
--
-- Before dropping the old index we collapse any existing name-collisions so
-- the new constraint can be applied cleanly.

-- Merge any surviving duplicates: for each set of entities sharing
-- lower(name)+space_id, keep the one with the most mentions (highest
-- engagement) and redirect all references to it.
DO $$
DECLARE
    dup RECORD;
    keep_id UUID;
BEGIN
    FOR dup IN
        SELECT lower(name) AS lname, space_id,
               array_agg(id ORDER BY
                   (SELECT count(*) FROM entity_mentions em WHERE em.entity_id = e.id) DESC,
                   created_at ASC) AS ids
        FROM entities e
        GROUP BY lower(name), space_id
        HAVING count(*) > 1
    LOOP
        keep_id := dup.ids[1];
        FOR i IN 2..array_length(dup.ids, 1) LOOP
            UPDATE entity_mentions SET entity_id = keep_id WHERE entity_id = dup.ids[i];
            UPDATE relationships SET source_entity_id = keep_id WHERE source_entity_id = dup.ids[i];
            UPDATE relationships SET target_entity_id = keep_id WHERE target_entity_id = dup.ids[i];
            DELETE FROM entities WHERE id = dup.ids[i];
        END LOOP;
    END LOOP;
END $$;

-- Replace the old index with one that ignores type.
DROP INDEX IF EXISTS entities_name_type_space_idx;

CREATE UNIQUE INDEX entities_name_space_idx
    ON entities (lower(name), space_id);
