from __future__ import annotations

import argparse
import csv
import random
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path


SEED = 551
COHORT_COUNT = 9
PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = PROJECT_ROOT / "data" / "synthetic"

REGULAR_PEOPLE = [
    "Alex Carter",
    "Bailey Chen",
    "Cameron Diaz",
    "Dana Park",
    "Evan Scott",
    "Farah Khan",
    "Grace Kim",
    "Henry Lopez",
    "Irene Patel",
    "Jason Yu",
    "Kylie Smith",
    "Leo Johnson",
    "Mina Choi",
    "Noah White",
    "Olivia Martin",
    "Priya Gupta",
    "Quinn Taylor",
    "Rina Suzuki",
    "Samuel Brown",
    "Tina Nguyen",
]

BUSINESS_ENTITIES = [
    ("CUST-BIZ-001", "Northstar Payroll LLC", "business", "low", "ACC-BIZ-001", "business", "US"),
    ("CUST-BIZ-002", "Harbor View Properties", "business", "low", "ACC-BIZ-002", "business", "US"),
    ("CUST-BIZ-003", "Fresh Basket Market", "business", "low", "ACC-BIZ-003", "business", "US"),
    ("CUST-BIZ-004", "City Utilities Service", "business", "low", "ACC-BIZ-004", "business", "US"),
    ("CUST-BIZ-005", "Blueline Brokerage", "business", "medium", "ACC-BIZ-005", "business", "US"),
]

SUSPICIOUS_CUSTOMERS = [
    ("CUST-AML-001", "Golden Crest Imports", "business", "high", "ACC-AML-HUB-001", "business", "US"),
    ("CUST-AML-002", "Marlin Export Consulting", "business", "high", "ACC-SHELL-001", "business", "KY"),
    ("CUST-CYCLE-001", "Orchid Metals Trading", "business", "high", "ACC-CYCLE-001", "business", "SG"),
    ("CUST-CYCLE-002", "Blue Mesa Commodities", "business", "high", "ACC-CYCLE-002", "business", "AE"),
    ("CUST-CYCLE-003", "North Gate Holdings", "business", "high", "ACC-CYCLE-003", "business", "HK"),
]

SMURFING_DEPOSIT_TEMPLATES = {
    1: [8940.00, 9180.00, 9420.00, 9760.00, 9860.00, 9640.00],
    2: [9010.00, 9260.00, 9510.00, 9725.00, 9835.00, 9585.00],
    3: [8875.00, 9145.00, 9475.00, 9685.00, 9795.00, 9555.00],
}

SMURFING_MINUTE_OFFSET_TEMPLATES = {
    1: [0, 27, 59, 96, 133, 169],
    2: [0, 24, 53, 88, 127, 164],
    3: [0, 31, 63, 99, 138, 176],
}

SMURFING_OUTBOUND_TEMPLATES = {
    1: 54900.00,
    2: 55350.00,
    3: 54780.00,
}

CYCLE_AMOUNT_TEMPLATES = {
    1: [15150.00, 14960.00, 15040.00],
    2: [15720.00, 15540.00, 15610.00],
    3: [14860.00, 14940.00, 14795.00],
}

CYCLE_MINUTE_OFFSET_TEMPLATES = {
    1: [0, 48, 121],
    2: [0, 42, 109],
    3: [0, 51, 117],
}


@dataclass(frozen=True)
class Customer:
    customer_id: str
    full_name: str
    customer_type: str
    risk_tier: str
    created_at: str


@dataclass(frozen=True)
class Account:
    account_id: str
    customer_id: str
    account_type: str
    open_date: str
    status: str
    home_country: str


@dataclass(frozen=True)
class CohortContext:
    cohort_number: int
    customer_accounts: list[str]
    feeder_accounts: list[str]
    employer: str
    landlord: str
    grocery: str
    utility: str
    brokerage: str
    suspicious_hub: str
    shell: str
    cycle_accounts: tuple[str, str, str]
    smurfing_tag: str
    cycle_tag: str


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def created_at(days_ago: int, cohort_number: int) -> str:
    base = datetime(2026, 1, 1, 9, 0, 0)
    shifted_days = days_ago + (cohort_number - 1) * 12
    return (base - timedelta(days=shifted_days)).strftime("%Y-%m-%d %H:%M:%S")


def scoped_customer_id(base_id: str, cohort_number: int) -> str:
    if cohort_number == 1:
        return base_id
    return base_id.replace("CUST-", f"CUST-C{cohort_number:02d}-", 1)


def scoped_account_id(base_id: str, cohort_number: int) -> str:
    if cohort_number == 1:
        return base_id
    return base_id.replace("ACC-", f"ACC-C{cohort_number:02d}-", 1)


def scoped_tag(base_tag: str, cohort_number: int) -> str:
    if cohort_number == 1:
        return base_tag
    tag_root, _ = base_tag.rsplit("_", 1)
    return f"{tag_root}_{cohort_number:03d}"


def shifted_open_date(base: date, day_offset: int, cohort_number: int, cohort_spacing_days: int) -> str:
    return str(base + timedelta(days=day_offset + (cohort_number - 1) * cohort_spacing_days))


def cohort_variant_slot(cohort_number: int) -> int:
    return ((cohort_number - 1) % 3) + 1


def cohort_wave_index(cohort_number: int) -> int:
    return (cohort_number - 1) // 3


def smurfing_deposit_amounts(cohort_number: int) -> list[float]:
    variant_slot = cohort_variant_slot(cohort_number)
    wave_index = cohort_wave_index(cohort_number)
    template = SMURFING_DEPOSIT_TEMPLATES[variant_slot]
    if wave_index == 0:
        return template

    adjustments = [45.0, 70.0, 110.0, -20.0, -15.0, 35.0]
    amounts = [
        min(9990.0, round(base_amount + wave_index * adjustment, 2))
        for base_amount, adjustment in zip(template, adjustments, strict=True)
    ]
    return amounts


def smurfing_minute_offsets(cohort_number: int) -> list[int]:
    variant_slot = cohort_variant_slot(cohort_number)
    wave_index = cohort_wave_index(cohort_number)
    template = SMURFING_MINUTE_OFFSET_TEMPLATES[variant_slot]
    if wave_index == 0:
        return template
    return [offset + wave_index * 4 * index for index, offset in enumerate(template)]


def smurfing_outbound_amount(cohort_number: int, deposit_total: float) -> float:
    variant_slot = cohort_variant_slot(cohort_number)
    wave_index = cohort_wave_index(cohort_number)
    template = SMURFING_OUTBOUND_TEMPLATES[variant_slot]
    if wave_index == 0:
        return template

    candidate = template + wave_index * 135.0
    minimum_allowed = round(deposit_total * 0.82, 2)
    return round(max(candidate, minimum_allowed), 2)


def cycle_amounts(cohort_number: int) -> list[float]:
    variant_slot = cohort_variant_slot(cohort_number)
    wave_index = cohort_wave_index(cohort_number)
    template = CYCLE_AMOUNT_TEMPLATES[variant_slot]
    if wave_index == 0:
        return template

    adjustments = [220.0, 180.0, 205.0]
    return [round(base_amount + wave_index * adjustment, 2) for base_amount, adjustment in zip(template, adjustments, strict=True)]


def cycle_minute_offsets(cohort_number: int) -> list[int]:
    variant_slot = cohort_variant_slot(cohort_number)
    wave_index = cohort_wave_index(cohort_number)
    template = CYCLE_MINUTE_OFFSET_TEMPLATES[variant_slot]
    if wave_index == 0:
        return template
    return [template[0], template[1] + wave_index * 5, template[2] + wave_index * 9]


def build_customers(cohort_count: int = COHORT_COUNT) -> tuple[list[Customer], list[Account], list[CohortContext]]:
    customers: list[Customer] = []
    accounts: list[Account] = []
    cohorts: list[CohortContext] = []

    for cohort_number in range(1, cohort_count + 1):
        customer_to_primary_account: dict[str, str] = {}
        customer_accounts: list[str] = []
        feeder_accounts: list[str] = []

        for index, full_name in enumerate(REGULAR_PEOPLE, start=1):
            customer_id = scoped_customer_id(f"CUST-IND-{index:03d}", cohort_number)
            primary_account_id = scoped_account_id(f"ACC-CHK-{index:03d}", cohort_number)
            risk_tier = "low" if index % 5 else "medium"

            customers.append(
                Customer(
                    customer_id=customer_id,
                    full_name=full_name,
                    customer_type="individual",
                    risk_tier=risk_tier,
                    created_at=created_at(300 + index * 6, cohort_number),
                )
            )
            accounts.append(
                Account(
                    account_id=primary_account_id,
                    customer_id=customer_id,
                    account_type="checking",
                    open_date=shifted_open_date(date(2024, 1, 10), index * 4, cohort_number, 28),
                    status="active",
                    home_country="US",
                )
            )
            customer_to_primary_account[customer_id] = primary_account_id
            customer_accounts.append(primary_account_id)

            if index % 4 == 0:
                accounts.append(
                    Account(
                        account_id=scoped_account_id(f"ACC-SAV-{index:03d}", cohort_number),
                        customer_id=customer_id,
                        account_type="savings",
                        open_date=shifted_open_date(date(2024, 5, 1), index * 3, cohort_number, 28),
                        status="active",
                        home_country="US",
                    )
                )

        for customer_id, full_name, customer_type, risk_tier, account_id, account_type, home_country in BUSINESS_ENTITIES:
            scoped_customer = scoped_customer_id(customer_id, cohort_number)
            scoped_account = scoped_account_id(account_id, cohort_number)
            customers.append(
                Customer(
                    customer_id=scoped_customer,
                    full_name=full_name,
                    customer_type=customer_type,
                    risk_tier=risk_tier,
                    created_at=created_at(540, cohort_number),
                )
            )
            accounts.append(
                Account(
                    account_id=scoped_account,
                    customer_id=scoped_customer,
                    account_type=account_type,
                    open_date=shifted_open_date(date(2023, 7, 1), 0, cohort_number, 35),
                    status="active",
                    home_country=home_country,
                )
            )
            customer_to_primary_account[scoped_customer] = scoped_account

        suspicious_customers = list(SUSPICIOUS_CUSTOMERS)
        for index in range(1, 7):
            suspicious_customers.append(
                (
                    f"CUST-FEED-{index:03d}",
                    f"Feeder Client {index}",
                    "individual",
                    "medium",
                    f"ACC-FEED-{index:03d}",
                    "checking",
                    "US",
                )
            )

        for customer_id, full_name, customer_type, risk_tier, account_id, account_type, home_country in suspicious_customers:
            scoped_customer = scoped_customer_id(customer_id, cohort_number)
            scoped_account = scoped_account_id(account_id, cohort_number)
            customers.append(
                Customer(
                    customer_id=scoped_customer,
                    full_name=full_name,
                    customer_type=customer_type,
                    risk_tier=risk_tier,
                    created_at=created_at(120, cohort_number),
                )
            )
            accounts.append(
                Account(
                    account_id=scoped_account,
                    customer_id=scoped_customer,
                    account_type=account_type,
                    open_date=shifted_open_date(date(2025, 8, 1), 0, cohort_number, 21),
                    status="active",
                    home_country=home_country,
                )
            )
            customer_to_primary_account[scoped_customer] = scoped_account

            if customer_id.startswith("CUST-FEED-"):
                feeder_accounts.append(scoped_account)

        cohorts.append(
            CohortContext(
                cohort_number=cohort_number,
                customer_accounts=customer_accounts,
                feeder_accounts=feeder_accounts,
                employer=customer_to_primary_account[scoped_customer_id("CUST-BIZ-001", cohort_number)],
                landlord=customer_to_primary_account[scoped_customer_id("CUST-BIZ-002", cohort_number)],
                grocery=customer_to_primary_account[scoped_customer_id("CUST-BIZ-003", cohort_number)],
                utility=customer_to_primary_account[scoped_customer_id("CUST-BIZ-004", cohort_number)],
                brokerage=customer_to_primary_account[scoped_customer_id("CUST-BIZ-005", cohort_number)],
                suspicious_hub=customer_to_primary_account[scoped_customer_id("CUST-AML-001", cohort_number)],
                shell=customer_to_primary_account[scoped_customer_id("CUST-AML-002", cohort_number)],
                cycle_accounts=(
                    customer_to_primary_account[scoped_customer_id("CUST-CYCLE-001", cohort_number)],
                    customer_to_primary_account[scoped_customer_id("CUST-CYCLE-002", cohort_number)],
                    customer_to_primary_account[scoped_customer_id("CUST-CYCLE-003", cohort_number)],
                ),
                smurfing_tag=scoped_tag("smurfing_funnel_001", cohort_number),
                cycle_tag=scoped_tag("circular_trading_001", cohort_number),
            )
        )

    return customers, accounts, cohorts


def build_transactions(cohorts: list[CohortContext], seed: int = SEED) -> list[dict[str, str]]:
    transactions: list[dict[str, str]] = []
    tx_counter = 1

    def add_tx(
        from_account_id: str | None,
        to_account_id: str | None,
        amount: float,
        tx_time: datetime,
        channel: str,
        merchant_category: str | None,
        tx_type: str,
        is_fraud_label: str = "normal",
        scenario_tag: str | None = None,
    ) -> None:
        nonlocal tx_counter
        transactions.append(
            {
                "tx_id": f"TX-{tx_counter:05d}",
                "from_account_id": from_account_id or "",
                "to_account_id": to_account_id or "",
                "amount": f"{amount:.2f}",
                "tx_time": tx_time.strftime("%Y-%m-%d %H:%M:%S"),
                "channel": channel,
                "merchant_category": merchant_category or "",
                "tx_type": tx_type,
                "is_fraud_label": is_fraud_label,
                "scenario_tag": scenario_tag or "",
            }
        )
        tx_counter += 1

    base_day = datetime(2026, 2, 1, 8, 0, 0)
    suspicious_day = datetime(2026, 2, 18, 9, 5, 0)
    cycle_day = datetime(2026, 2, 22, 10, 15, 0)

    for cohort in cohorts:
        rng = random.Random(seed + cohort_variant_slot(cohort.cohort_number) - 1)
        cohort_base_day = base_day + timedelta(days=(cohort.cohort_number - 1) * 23)

        for account_id in cohort.customer_accounts:
            payroll_day = cohort_base_day + timedelta(days=rng.randint(0, 2), hours=rng.randint(0, 5))
            payroll_amount = rng.uniform(1800, 3400)
            add_tx(cohort.employer, account_id, payroll_amount, payroll_day, "ach", "payroll", "transfer")

            rent_day = payroll_day + timedelta(days=rng.randint(2, 4), hours=rng.randint(1, 8))
            rent_amount = rng.uniform(950, 2200)
            add_tx(account_id, cohort.landlord, rent_amount, rent_day, "ach", "housing", "transfer")

            utility_day = payroll_day + timedelta(days=rng.randint(3, 8), hours=rng.randint(1, 6))
            utility_amount = rng.uniform(80, 240)
            add_tx(account_id, cohort.utility, utility_amount, utility_day, "ach", "utilities", "withdrawal")

            for _ in range(rng.randint(3, 6)):
                grocery_day = cohort_base_day + timedelta(
                    days=rng.randint(0, 20),
                    hours=rng.randint(8, 21),
                    minutes=rng.randint(0, 59),
                )
                grocery_amount = rng.uniform(22, 190)
                add_tx(account_id, cohort.grocery, grocery_amount, grocery_day, "card", "groceries", "withdrawal")

            if rng.random() < 0.45:
                invest_day = cohort_base_day + timedelta(
                    days=rng.randint(5, 20),
                    hours=rng.randint(8, 18),
                    minutes=rng.randint(0, 59),
                )
                invest_amount = rng.uniform(250, 1800)
                add_tx(account_id, cohort.brokerage, invest_amount, invest_day, "ach", "investment", "transfer")

            if rng.random() < 0.35:
                cash_day = cohort_base_day + timedelta(
                    days=rng.randint(0, 18),
                    hours=rng.randint(8, 19),
                    minutes=rng.randint(0, 59),
                )
                cash_amount = rng.uniform(150, 2800)
                add_tx(account_id, account_id, cash_amount, cash_day, "cash", "branch_deposit", "deposit")

        for _ in range(35):
            sender, receiver = rng.sample(cohort.customer_accounts, 2)
            p2p_time = cohort_base_day + timedelta(
                days=rng.randint(0, 20),
                hours=rng.randint(8, 22),
                minutes=rng.randint(0, 59),
            )
            p2p_amount = rng.uniform(20, 420)
            add_tx(sender, receiver, p2p_amount, p2p_time, "internal", "p2p_transfer", "transfer")

        cohort_suspicious_day = suspicious_day + timedelta(days=(cohort.cohort_number - 1) * 9)
        deposit_amounts = smurfing_deposit_amounts(cohort.cohort_number)
        deposit_offsets = smurfing_minute_offsets(cohort.cohort_number)
        for index, amount in enumerate(deposit_amounts):
            add_tx(
                cohort.feeder_accounts[index],
                cohort.suspicious_hub,
                amount,
                cohort_suspicious_day + timedelta(minutes=deposit_offsets[index]),
                "cash",
                "branch_deposit",
                "deposit",
                "smurfing",
                cohort.smurfing_tag,
            )

        last_deposit_time = cohort_suspicious_day + timedelta(minutes=deposit_offsets[-1])
        add_tx(
            cohort.suspicious_hub,
            cohort.shell,
            smurfing_outbound_amount(cohort.cohort_number, sum(deposit_amounts)),
            last_deposit_time + timedelta(minutes=76 + cohort.cohort_number * 3),
            "wire",
            "consulting_services",
            "transfer",
            "smurfing",
            cohort.smurfing_tag,
        )

        add_tx(
            cohort.suspicious_hub,
            cohort.brokerage,
            1400.00 + (cohort.cohort_number - 1) * 160.00,
            cohort_suspicious_day + timedelta(days=2, minutes=70 + cohort.cohort_number * 5),
            "ach",
            "brokerage",
            "transfer",
        )

        cohort_cycle_day = cycle_day + timedelta(days=(cohort.cohort_number - 1) * 8)
        cycle_offsets = cycle_minute_offsets(cohort.cohort_number)
        cycle_amounts_for_cohort = cycle_amounts(cohort.cohort_number)
        cycle_a, cycle_b, cycle_c = cohort.cycle_accounts
        cycle_legs = [
            (cycle_a, cycle_b, cycle_amounts_for_cohort[0], cohort_cycle_day + timedelta(minutes=cycle_offsets[0])),
            (cycle_b, cycle_c, cycle_amounts_for_cohort[1], cohort_cycle_day + timedelta(minutes=cycle_offsets[1])),
            (cycle_c, cycle_a, cycle_amounts_for_cohort[2], cohort_cycle_day + timedelta(minutes=cycle_offsets[2])),
        ]
        for from_account_id, to_account_id, amount, tx_time in cycle_legs:
            add_tx(
                from_account_id,
                to_account_id,
                amount,
                tx_time,
                "wire",
                "brokerage_settlement",
                "transfer",
                "cycle",
                cohort.cycle_tag,
            )

    transactions.sort(key=lambda row: (row["tx_time"], row["tx_id"]))
    return transactions


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate the Hybrid-AML synthetic CSV dataset.")
    parser.add_argument("--seed", type=int, default=SEED, help=f"Random seed. Default: {SEED}.")
    parser.add_argument("--cohorts", type=int, default=COHORT_COUNT, help=f"Number of synthetic cohorts. Default: {COHORT_COUNT}.")
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR, help=f"Output directory. Default: {OUTPUT_DIR}.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    customers, accounts, cohorts = build_customers(args.cohorts)
    transactions = build_transactions(cohorts, args.seed)

    customer_rows = [customer.__dict__ for customer in customers]
    account_rows = [account.__dict__ for account in accounts]

    write_csv(
        args.output_dir / "customers.csv",
        ["customer_id", "full_name", "customer_type", "risk_tier", "created_at"],
        customer_rows,
    )
    write_csv(
        args.output_dir / "accounts.csv",
        ["account_id", "customer_id", "account_type", "open_date", "status", "home_country"],
        account_rows,
    )
    write_csv(
        args.output_dir / "transactions.csv",
        [
            "tx_id",
            "from_account_id",
            "to_account_id",
            "amount",
            "tx_time",
            "channel",
            "merchant_category",
            "tx_type",
            "is_fraud_label",
            "scenario_tag",
        ],
        transactions,
    )

    smurfing_totals: dict[str, float] = defaultdict(float)
    cycle_totals: dict[str, float] = defaultdict(float)
    for row in transactions:
        scenario_tag = row["scenario_tag"]
        if not scenario_tag:
            continue
        if scenario_tag.startswith("smurfing_funnel_") and row["tx_type"] == "deposit":
            smurfing_totals[scenario_tag] += float(row["amount"])
        if scenario_tag.startswith("circular_trading_"):
            cycle_totals[scenario_tag] += float(row["amount"])

    print(f"Wrote {len(customer_rows)} customers to {args.output_dir / 'customers.csv'}")
    print(f"Wrote {len(account_rows)} accounts to {args.output_dir / 'accounts.csv'}")
    print(f"Wrote {len(transactions)} transactions to {args.output_dir / 'transactions.csv'}")
    for scenario_tag in sorted(smurfing_totals):
        print(f"Smurfing inbound total for {scenario_tag}: ${smurfing_totals[scenario_tag]:,.2f}")
    for scenario_tag in sorted(cycle_totals):
        print(f"Circular trading notional total for {scenario_tag}: ${cycle_totals[scenario_tag]:,.2f}")


if __name__ == "__main__":
    main()
