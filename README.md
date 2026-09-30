# Hybrid-AML: Graph-on-Relational Fraud Detection

**Course:** DSCI 551 Course Project, Spring '26  
**Team Members:** Chanyoung Kim, Yogita Mutyala

## Project Overview

Hybrid-AML studies whether PostgreSQL with Apache AGE can support AML-style graph analysis without leaving a relational database system. The project uses one PostgreSQL instance as the system of record, projects account-to-account transaction flows into Apache AGE graphs, and compares relational SQL detection paths with graph-oriented Cypher detection paths.

The application is a reproducible command-line pipeline rather than a web dashboard. A user resets the Dockerized database, regenerates synthetic data, loads relational tables, builds AGE graph projections, runs detection queries, and reruns benchmark scripts from the repository.

## Research Question

Can PostgreSQL with Apache AGE efficiently support graph traversal workloads compared with native relational approaches, and what storage and execution tradeoffs appear in this hybrid model?

## Implemented Final Scope

- Docker-based PostgreSQL + Apache AGE environment
- Relational schema for `customers`, `accounts`, and `transactions`
- Synthetic transaction generator with fixed-seed reproducibility
- Nine planted smurfing funnel scenarios
- Nine planted circular trading scenarios
- SQL and AGE-backed smurfing detection queries
- Recursive SQL circular trading detection query
- Baseline Cypher circular trading query on AGE with a six-hour cycle window
- Tuned Cypher variant on a transfer-only AGE graph projection
- Demo query runner for live verification
- Benchmark script for 20-run warm-cache `EXPLAIN ANALYZE` comparisons

## Repository Structure

```text
.
├── assets/                  # Static assets for documentation
├── data/
│   ├── raw/                 # Reserved; no external raw dataset is required
│   └── synthetic/           # Generated CSVs used in the prototype
├── database/
│   ├── migrations/          # Relational schema creation scripts
│   ├── queries/             # SQL and Cypher detection queries
│   ├── seeds/               # CSV loading and AGE graph projection scripts
│   └── setup_age.sql        # AGE extension setup
├── docs/
│   ├── demo/                # Final demo deck and live demo materials
│   ├── guidelines/          # Course guidelines
│   ├── proposal/            # Phase 1 proposal
│   └── reports/             # Phase 2/3 reports and benchmark artifacts
├── scripts/
│   ├── reset_pipeline.sh    # One-command Docker + PostgreSQL + AGE reset
│   └── run_demo_queries.sh  # Live demo detection query runner
├── src/
│   ├── analysis/            # Benchmark and analysis scripts
│   ├── dashboard/           # Reserved for optional UI work
│   └── data_generation/     # Synthetic data generation scripts
└── tests/
    └── smoke_test.sh        # Fresh-clone runtime verification
```

## Prerequisites

- Docker Desktop running locally
- Python 3.10 or newer on the host machine
- Optional: `psql` on the host if you want to connect outside the container

No third-party Python packages are required. The Python scripts use the standard library only.

This prototype does not require an Apache web server. The runtime stack is:

- Dockerized PostgreSQL + Apache AGE
- Host-side Python for synthetic data generation and benchmarking
- Shell scripts for reset, loading, demo, and smoke-test workflows

## Clone and Enter the Repo

```bash
git clone https://github.com/KHUCHAN/DSCI-551-Data-Base-Course-Project.git
cd DSCI-551-Data-Base-Course-Project
```

All commands below assume you are running them from the repository root. If shell execute permissions are missing after download, either run `chmod +x scripts/*.sh tests/*.sh` once or invoke scripts with `bash`.

## Quick Start

From the repository root:

```bash
./scripts/reset_pipeline.sh
```

That script will:

1. Pull the Apache AGE Docker image if needed.
2. Start a Docker container named `apache-age`.
3. Generate the synthetic CSV data.
4. Create the relational schema.
5. Load CSV data into PostgreSQL.
6. Enable the AGE extension.
7. Build the baseline and tuned graph projections.
8. Print final row counts.

Expected final table sizes:

| Table | Expected rows |
| --- | ---: |
| `customers` | 324 |
| `accounts` | 369 |
| `transactions` | 1,896 |

If you want to recreate the database volume from scratch:

```bash
RESET_DB_VOLUME=1 ./scripts/reset_pipeline.sh
```

## Local Configuration

The default settings are intended for a local course-project demo:

| Variable | Default | Purpose |
| --- | --- | --- |
| `IMAGE_NAME` | `apache/age:latest` | Docker image used for PostgreSQL + AGE |
| `CONTAINER_NAME` | `apache-age` | Docker container name |
| `DB_NAME` | `hybrid_aml` | PostgreSQL database name |
| `POSTGRES_USER` | `postgres` | Local demo database user |
| `POSTGRES_PASSWORD` | `postgres` | Local demo database password |
| `HOST_PORT` | `5455` | Host port mapped to container port `5432` |
| `DB_VOLUME` | `age_pg18data` | Docker volume for PostgreSQL storage |
| `RESET_DB_VOLUME` | `0` | Set to `1` to recreate the database volume |

Example override:

```bash
POSTGRES_PASSWORD=your_local_password HOST_PORT=5456 ./scripts/reset_pipeline.sh
```

An optional [.env.example](.env.example) file documents the same settings. The scripts do not require a `.env` file.

## Secrets and Credentials

No API keys, external credentials, private tokens, or paid services are required. The default PostgreSQL password `postgres` is only for the local Docker demo and should not be reused for public or production systems. For any custom local setup, override `POSTGRES_PASSWORD` through the environment.

## Data and Reproducibility

This project does not use a private or external raw dataset. All demo data is synthetic and can be regenerated from source code.

To regenerate the dataset manually:

```bash
python3 src/data_generation/generate_synthetic_data.py
```

The default generator settings are:

| Setting | Value |
| --- | --- |
| Seed | `551` |
| Cohorts | `9` |
| Output directory | `data/synthetic` |

Generated files:

- `data/synthetic/customers.csv`
- `data/synthetic/accounts.csv`
- `data/synthetic/transactions.csv`

Expected generated sizes, excluding CSV headers:

- `customers.csv`: 324 rows
- `accounts.csv`: 369 rows
- `transactions.csv`: 1,896 rows

The generator also supports overrides:

```bash
python3 src/data_generation/generate_synthetic_data.py --seed 551 --cohorts 9 --output-dir data/synthetic
```

Regenerating the dataset overwrites the generated CSV files in the selected output directory.

## Manual Setup

The reset script is the recommended setup path. To run the same steps manually:

```bash
docker pull apache/age:latest

docker run -d \
  --name apache-age \
  -p 5455:5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=hybrid_aml \
  -v age_pg18data:/var/lib/postgresql \
  -v "$PWD":/workspace \
  apache/age:latest

python3 src/data_generation/generate_synthetic_data.py

docker exec -i -w /workspace apache-age \
  psql -v ON_ERROR_STOP=1 -U postgres -d hybrid_aml \
  < database/migrations/001_schema.sql

docker exec -i -w /workspace apache-age \
  psql -v ON_ERROR_STOP=1 -U postgres -d hybrid_aml \
  < database/seeds/load_from_csv.sql

docker exec -i -w /workspace apache-age \
  psql -v ON_ERROR_STOP=1 -U postgres -d hybrid_aml \
  < database/setup_age.sql

docker exec -i -w /workspace apache-age \
  psql -v ON_ERROR_STOP=1 -U postgres -d hybrid_aml \
  < database/seeds/load_age_graph.sql

docker exec -i -w /workspace apache-age \
  psql -v ON_ERROR_STOP=1 -U postgres -d hybrid_aml \
  < database/seeds/load_age_graph_tuned.sql
```

The CSV loader uses paths relative to `/workspace` inside the container. The reset script mounts the repository there automatically.

## Demo Queries

After resetting the database, run the live demo query runner:

```bash
./scripts/run_demo_queries.sh
```

That script warms the cache, prints detected rows, and summarizes visible run times for:

- Smurfing detection through relational SQL
- Smurfing detection through Apache AGE
- Circular trading detection through recursive SQL
- Circular trading detection through Apache AGE

To run the tuned AGE cycle query in the demo runner:

```bash
CYCLE_GRAPH_VARIANT=tuned ./scripts/run_demo_queries.sh
```

The core query files can also be executed directly:

```bash
docker exec -i -w /workspace apache-age \
  psql -U postgres -d hybrid_aml \
  < database/queries/smurfing_detection.sql

docker exec -i -w /workspace apache-age \
  psql -U postgres -d hybrid_aml \
  < database/queries/smurfing_detection_age.sql

docker exec -i -w /workspace apache-age \
  psql -U postgres -d hybrid_aml \
  < database/queries/circular_trading_recursive.sql

docker exec -i -w /workspace apache-age \
  psql -U postgres -d hybrid_aml \
  < database/queries/circular_trading_cypher.sql

docker exec -i -w /workspace apache-age \
  psql -U postgres -d hybrid_aml \
  < database/queries/circular_trading_cypher_tuned.sql
```

Expected detection counts after the default reset:

| Query | Expected detections |
| --- | ---: |
| Smurfing SQL | 9 |
| Smurfing AGE | 9 |
| Circular trading recursive SQL | 9 |
| Circular trading AGE baseline | 9 |
| Circular trading AGE tuned | 9 |

## Smoke Test

After `./scripts/reset_pipeline.sh` finishes, run:

```bash
./tests/smoke_test.sh
```

The smoke test checks row counts and expected detection counts against the running Dockerized database.

## Benchmarks

To rerun the cycle-detection benchmark and refresh the saved `EXPLAIN ANALYZE` artifacts:

```bash
python3 src/analysis/benchmark_cycle_queries.py
```

Run `./scripts/reset_pipeline.sh` before benchmarking. The benchmark script writes the latest plans to:

- `docs/reports/cycle_recursive_explain.txt`
- `docs/reports/cycle_cypher_explain.txt`
- `docs/reports/cycle_cypher_tuned_explain.txt`

Benchmark configuration can be overridden with the same environment variable names used by the reset script:

```bash
CONTAINER_NAME=apache-age DB_NAME=hybrid_aml POSTGRES_USER=postgres BENCHMARK_RUNS=20 \
  python3 src/analysis/benchmark_cycle_queries.py
```

## Deliverables in This Repository

- Final report: [docs/reports/Phase 3_ Final Report.pdf](docs/reports/Phase%203_%20Final%20Report.pdf)
- Final live demo PDF: [docs/demo/Phase 3 Live Demo Presentation_vf.pdf](docs/demo/Phase%203%20Live%20Demo%20Presentation_vf.pdf)
- Final demo deck source: [docs/demo/hybrid_aml_demo_deck.pptx](docs/demo/hybrid_aml_demo_deck.pptx)
- Phase 1 proposal: [docs/proposal/Phase 1_ Project Proposal.pdf](docs/proposal/Phase%201_%20Project%20Proposal.pdf)
- Phase 2 report: [docs/reports/Phase2_MidtermReport_ChanyoungKim_YogitaMutyala.pdf](docs/reports/Phase2_MidtermReport_ChanyoungKim_YogitaMutyala.pdf)
- Cycle benchmark summary: [docs/reports/cycle_benchmark_summary.md](docs/reports/cycle_benchmark_summary.md)

## License

DSCI 551 Course Project
