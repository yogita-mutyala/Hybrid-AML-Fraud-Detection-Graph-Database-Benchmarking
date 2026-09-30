# Circular Trading Benchmark Summary

Benchmark date: 2026-05-03
Database: PostgreSQL with Apache AGE
Runs per query: 20 warm-cache `EXPLAIN ANALYZE` executions

## Query Variants

- Recursive SQL over the relational `transactions` table
- Cypher on the baseline `aml_graph`
- Cypher on the tuned `aml_graph_tuned`

## Execution Results

| Query | Median Execution (ms) | Trimmed Mean Execution (ms) |
| --- | ---: | ---: |
| Recursive SQL | 1.341 | 1.387 |
| Cypher on AGE | 6.946 | 6.998 |
| Cypher on AGE (tuned) | 2.705 | 2.716 |

## Interpretation

The tuned Cypher graph reduces execution time relative to the baseline graph by narrowing the graph to transfer edges only and by comparing internal graph identifiers and numeric timestamps. Even after tuning, the bounded 3-hop cycle detection workload remains faster in recursive SQL on the current small synthetic dataset.
