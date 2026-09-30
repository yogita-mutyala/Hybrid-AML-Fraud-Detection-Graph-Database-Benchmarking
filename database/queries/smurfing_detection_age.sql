LOAD 'age';
SET search_path = ag_catalog, "$user", public;

WITH params AS (
    SELECT
        10000.00::NUMERIC AS reporting_threshold,
        5::INT AS min_small_deposits,
        45000.00::NUMERIC AS min_structured_total,
        INTERVAL '24 hours' AS funnel_window
),
deposit_edges AS (
    SELECT
        beneficiary_account_id::text AS beneficiary_account_id,
        (amount::text)::NUMERIC(14, 2) AS amount,
        (tx_time::text)::TIMESTAMP AS tx_time,
        channel::text AS channel
    FROM cypher(
        'aml_graph',
        $$
        MATCH (src:Account)-[tx:TRANSFER]->(dst:Account)
        WHERE tx.tx_type = 'deposit'
          AND tx.channel = 'cash'
        RETURN dst.account_id, tx.amount, tx.tx_time, tx.channel
        $$
    ) AS (
        beneficiary_account_id agtype,
        amount agtype,
        tx_time agtype,
        channel agtype
    )
),
deposit_clusters AS (
    SELECT
        de.beneficiary_account_id,
        DATE_TRUNC('day', de.tx_time) AS deposit_day,
        COUNT(*) AS small_cash_deposit_count,
        SUM(de.amount) AS structured_total,
        MIN(de.tx_time) AS first_deposit_at,
        MAX(de.tx_time) AS last_deposit_at
    FROM deposit_edges de
    CROSS JOIN params p
    WHERE de.amount < p.reporting_threshold
    GROUP BY de.beneficiary_account_id, DATE_TRUNC('day', de.tx_time)
    HAVING COUNT(*) >= (SELECT min_small_deposits FROM params)
       AND SUM(de.amount) >= (SELECT min_structured_total FROM params)
),
outbound_edges AS (
    SELECT
        from_account_id::text AS from_account_id,
        to_account_id::text AS to_account_id,
        tx_id::text AS tx_id,
        (amount::text)::NUMERIC(14, 2) AS amount,
        (tx_time::text)::TIMESTAMP AS tx_time
    FROM cypher(
        'aml_graph',
        $$
        MATCH (src:Account)-[tx:TRANSFER]->(dst:Account)
        WHERE tx.tx_type = 'transfer'
        RETURN src.account_id, dst.account_id, tx.tx_id, tx.amount, tx.tx_time
        $$
    ) AS (
        from_account_id agtype,
        to_account_id agtype,
        tx_id agtype,
        amount agtype,
        tx_time agtype
    )
),
rapid_funnel_out AS (
    SELECT
        dc.beneficiary_account_id,
        dc.deposit_day,
        dc.small_cash_deposit_count,
        dc.structured_total,
        dc.first_deposit_at,
        dc.last_deposit_at,
        out_tx.tx_id AS outbound_tx_id,
        out_tx.to_account_id AS outbound_beneficiary_account_id,
        out_tx.amount AS outbound_amount,
        out_tx.tx_time AS outbound_time
    FROM deposit_clusters dc
    CROSS JOIN params p
    JOIN outbound_edges out_tx
      ON out_tx.from_account_id = dc.beneficiary_account_id
     AND out_tx.tx_time BETWEEN dc.last_deposit_at AND dc.last_deposit_at + p.funnel_window
     AND out_tx.amount >= dc.structured_total * 0.70
)
SELECT
    rfo.deposit_day::DATE AS suspicious_day,
    rfo.beneficiary_account_id,
    beneficiary_customer.full_name AS beneficiary_owner,
    rfo.small_cash_deposit_count,
    rfo.structured_total,
    rfo.first_deposit_at,
    rfo.last_deposit_at,
    rfo.outbound_tx_id,
    rfo.outbound_amount,
    rfo.outbound_time,
    rfo.outbound_beneficiary_account_id,
    shell_customer.full_name AS outbound_beneficiary_owner
FROM rapid_funnel_out rfo
JOIN accounts beneficiary_account
  ON beneficiary_account.account_id = rfo.beneficiary_account_id
JOIN customers beneficiary_customer
  ON beneficiary_customer.customer_id = beneficiary_account.customer_id
JOIN accounts shell_account
  ON shell_account.account_id = rfo.outbound_beneficiary_account_id
JOIN customers shell_customer
  ON shell_customer.customer_id = shell_account.customer_id
ORDER BY rfo.structured_total DESC, rfo.outbound_time;
