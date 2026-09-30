CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

SELECT extname, extversion
FROM pg_extension
WHERE extname = 'age';

SELECT graphid, name, namespace
FROM ag_graph
ORDER BY graphid;
