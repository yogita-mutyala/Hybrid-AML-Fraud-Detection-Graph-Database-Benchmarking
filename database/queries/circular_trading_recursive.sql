WITH RECURSIVE transfer_edges AS (
    SELECT
        tx_id,
        from_account_id,
        to_account_id,
        amount,
        tx_time
    FROM transactions
    WHERE tx_type = 'transfer'
      AND NULLIF(from_account_id, '') IS NOT NULL
      AND NULLIF(to_account_id, '') IS NOT NULL
),
paths AS (
    SELECT
        tx_id AS start_tx_id,
        ARRAY[tx_id] AS tx_ids,
        from_account_id AS origin_account_id,
        to_account_id AS current_account_id,
        ARRAY[from_account_id, to_account_id] AS node_path,
        tx_time AS first_tx_time,
        tx_time AS last_tx_time,
        1 AS depth
    FROM transfer_edges

    UNION ALL

    SELECT
        p.start_tx_id,
        p.tx_ids || e.tx_id,
        p.origin_account_id,
        e.to_account_id,
        CASE
            WHEN e.to_account_id = p.origin_account_id THEN p.node_path
            ELSE p.node_path || e.to_account_id
        END AS node_path,
        p.first_tx_time,
        e.tx_time AS last_tx_time,
        p.depth + 1
    FROM paths p
    JOIN transfer_edges e
      ON e.from_account_id = p.current_account_id
     AND e.tx_time >= p.last_tx_time
     AND e.tx_time <= p.first_tx_time + INTERVAL '6 hours'
     AND e.tx_id <> ALL(p.tx_ids)
    WHERE p.depth < 3
      AND (
            e.to_account_id = p.origin_account_id
            OR e.to_account_id <> ALL(p.node_path)
      )
)
SELECT
    p.origin_account_id AS account_a,
    p.node_path[2] AS account_b,
    p.node_path[3] AS account_c,
    p.tx_ids[1] AS tx_1,
    p.tx_ids[2] AS tx_2,
    p.tx_ids[3] AS tx_3,
    p.first_tx_time,
    p.last_tx_time
FROM paths p
WHERE p.depth = 3
  AND p.current_account_id = p.origin_account_id
  AND array_length(p.node_path, 1) = 3
  AND p.origin_account_id < p.node_path[2]
  AND p.origin_account_id < p.node_path[3]
ORDER BY p.first_tx_time;
