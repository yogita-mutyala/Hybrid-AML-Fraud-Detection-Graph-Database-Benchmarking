WITH params AS (
    SELECT
        10000.00::NUMERIC AS reporting_threshold,
        5::INT AS min_small_deposits,
        45000.00::NUMERIC AS min_structured_total,
        INTERVAL '24 hours' AS funnel_window
),
deposit_clusters AS (
    SELECT
        t.to_account_id AS beneficiary_account_id,
        DATE_TRUNC('day', t.tx_time) AS deposit_day,
        COUNT(*) AS small_cash_deposit_count,
        SUM(t.amount) AS structured_total,
        MIN(t.tx_time) AS first_deposit_at,
        MAX(t.tx_time) AS last_deposit_at
    FROM transactions t
    CROSS JOIN params p
    WHERE t.tx_type = 'deposit'
      AND t.channel = 'cash'
      AND t.amount < p.reporting_threshold
    GROUP BY t.to_account_id, DATE_TRUNC('day', t.tx_time)
    HAVING COUNT(*) >= (SELECT min_small_deposits FROM params)
       AND SUM(t.amount) >= (SELECT min_structured_total FROM params)
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
    JOIN transactions out_tx
      ON out_tx.from_account_id = dc.beneficiary_account_id
     AND out_tx.tx_type = 'transfer'
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
