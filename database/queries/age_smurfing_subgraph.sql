LOAD 'age';
SET search_path = ag_catalog, "$user", public;

SELECT *
FROM cypher(
    'aml_graph',
    $$
    MATCH (src:Account)-[tx:TRANSFER]->(dst:Account)
    WHERE tx.scenario_tag = 'smurfing_funnel_001'
    RETURN src.account_id, tx.tx_id, tx.amount, tx.channel, tx.tx_time, dst.account_id
    $$
) AS (
    from_account agtype,
    tx_id agtype,
    amount agtype,
    channel agtype,
    tx_time agtype,
    to_account agtype
);
