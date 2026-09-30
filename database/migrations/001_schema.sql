DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    customer_type TEXT NOT NULL CHECK (customer_type IN ('individual', 'business')),
    risk_tier TEXT NOT NULL CHECK (risk_tier IN ('low', 'medium', 'high')),
    created_at TIMESTAMP NOT NULL
);

CREATE TABLE accounts (
    account_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL REFERENCES customers(customer_id),
    account_type TEXT NOT NULL CHECK (account_type IN ('checking', 'savings', 'business')),
    open_date DATE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'closed')),
    home_country TEXT NOT NULL
);

CREATE TABLE transactions (
    tx_id TEXT PRIMARY KEY,
    from_account_id TEXT REFERENCES accounts(account_id),
    to_account_id TEXT REFERENCES accounts(account_id),
    amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    tx_time TIMESTAMP NOT NULL,
    channel TEXT NOT NULL CHECK (channel IN ('ach', 'wire', 'cash', 'card', 'internal', 'crypto')),
    merchant_category TEXT,
    tx_type TEXT NOT NULL CHECK (tx_type IN ('deposit', 'transfer', 'withdrawal')),
    is_fraud_label TEXT NOT NULL CHECK (is_fraud_label IN ('normal', 'smurfing', 'cycle')),
    scenario_tag TEXT
);

CREATE INDEX idx_accounts_customer_id ON accounts (customer_id);
CREATE INDEX idx_transactions_from_account_time ON transactions (from_account_id, tx_time);
CREATE INDEX idx_transactions_to_account_time ON transactions (to_account_id, tx_time);
CREATE INDEX idx_transactions_tx_time ON transactions (tx_time);
CREATE INDEX idx_transactions_label ON transactions (is_fraud_label);
