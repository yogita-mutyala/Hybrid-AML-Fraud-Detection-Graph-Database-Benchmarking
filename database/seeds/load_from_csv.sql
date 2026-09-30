TRUNCATE TABLE transactions, accounts, customers;

\copy customers FROM 'data/synthetic/customers.csv' CSV HEADER
\copy accounts FROM 'data/synthetic/accounts.csv' CSV HEADER
\copy transactions FROM 'data/synthetic/transactions.csv' CSV HEADER
