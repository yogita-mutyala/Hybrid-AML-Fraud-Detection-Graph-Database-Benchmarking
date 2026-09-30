LOAD 'age';
SET search_path = ag_catalog, "$user", public;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM ag_graph WHERE name = 'aml_graph') THEN
        PERFORM drop_graph('aml_graph', true);
    END IF;
END
$$;

SELECT create_graph('aml_graph');
SELECT create_vlabel('aml_graph', 'Account');
SELECT create_elabel('aml_graph', 'TRANSFER');

DO $$
DECLARE
    account_row RECORD;
BEGIN
    FOR account_row IN
        SELECT
            account_id,
            customer_id,
            account_type,
            status,
            home_country
        FROM public.accounts
        ORDER BY account_id
    LOOP
        EXECUTE format(
            $stmt$
            SELECT *
            FROM cypher(
                'aml_graph',
                $cypher$
                CREATE (:Account {
                    account_id: %L,
                    customer_id: %L,
                    account_type: %L,
                    status: %L,
                    home_country: %L
                })
                RETURN 1
                $cypher$
            ) AS (result agtype);
            $stmt$,
            account_row.account_id,
            account_row.customer_id,
            account_row.account_type,
            account_row.status,
            account_row.home_country
        );
    END LOOP;
END
$$;

DO $$
DECLARE
    tx_row RECORD;
BEGIN
    FOR tx_row IN
        SELECT
            tx_id,
            from_account_id,
            to_account_id,
            amount,
            tx_time,
            EXTRACT(EPOCH FROM tx_time)::BIGINT AS tx_epoch,
            channel,
            tx_type,
            is_fraud_label,
            COALESCE(scenario_tag, '') AS scenario_tag
        FROM public.transactions
        WHERE NULLIF(from_account_id, '') IS NOT NULL
          AND NULLIF(to_account_id, '') IS NOT NULL
        ORDER BY tx_time, tx_id
    LOOP
        EXECUTE format(
            $stmt$
            SELECT *
            FROM cypher(
                'aml_graph',
                $cypher$
                MATCH (src:Account {account_id: %L}), (dst:Account {account_id: %L})
                CREATE (src)-[:TRANSFER {
                    tx_id: %L,
                    amount: %s,
                    tx_time: %L,
                    tx_epoch: %s,
                    channel: %L,
                    tx_type: %L,
                    is_fraud_label: %L,
                    scenario_tag: %L
                }]->(dst)
                RETURN 1
                $cypher$
            ) AS (result agtype);
            $stmt$,
            tx_row.from_account_id,
            tx_row.to_account_id,
            tx_row.tx_id,
            tx_row.amount,
            tx_row.tx_time,
            tx_row.tx_epoch,
            tx_row.channel,
            tx_row.tx_type,
            tx_row.is_fraud_label,
            tx_row.scenario_tag
        );
    END LOOP;
END
$$;

ANALYZE aml_graph."Account";
ANALYZE aml_graph."TRANSFER";

SELECT
    (SELECT COUNT(*) FROM aml_graph."Account") AS account_vertices,
    (SELECT COUNT(*) FROM aml_graph."TRANSFER") AS transfer_edges;
