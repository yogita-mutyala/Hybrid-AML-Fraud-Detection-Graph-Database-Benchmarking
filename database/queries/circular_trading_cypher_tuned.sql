LOAD 'age';
SET search_path = ag_catalog, "$user", public;

SELECT *
FROM cypher(
    'aml_graph_tuned',
    $$
    MATCH (a:Account)-[t1:TRANSFER]->(b:Account)-[t2:TRANSFER]->(c:Account)-[t3:TRANSFER]->(a)
    WHERE id(a) < id(b)
      AND id(a) < id(c)
      AND id(b) <> id(c)
      AND t1.tx_epoch <= t2.tx_epoch
      AND t2.tx_epoch <= t3.tx_epoch
      AND t3.tx_epoch - t1.tx_epoch <= 21600
    RETURN
        a.account_id,
        b.account_id,
        c.account_id,
        t1.tx_id,
        t2.tx_id,
        t3.tx_id,
        t1.tx_time,
        t3.tx_time
    ORDER BY t1.tx_epoch
    $$
) AS (
    account_a agtype,
    account_b agtype,
    account_c agtype,
    tx_1 agtype,
    tx_2 agtype,
    tx_3 agtype,
    first_tx_time agtype,
    last_tx_time agtype
);
