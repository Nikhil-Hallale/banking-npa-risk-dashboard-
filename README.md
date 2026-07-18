# Banking NPA Risk Dashboard

**A 22-year (2004–2025) SQL-based analysis of asset quality across India's banking system**

---

## Why this project

Non-performing assets are one of the clearest signals of how healthy — or fragile — a banking system really is. This project takes 22 years of RBI's raw, messy bank-level NPA disclosures and turns them into a clean dataset and a set of credit-risk metrics that a real risk or banking-analytics team would actually track: where asset quality is deteriorating, where it's concentrated, and which banks deserve a closer look. It's meant to demonstrate SQL-first data cleaning and applied credit-risk analysis end to end, not just a chart.

---

## Tech stack

- **SQLite** — data storage and all analysis queries (window functions, CTEs, statistical aggregates)
- **SQL** — data cleaning (forward/backward-fill, type casting, deduplication) and analysis (trend, dispersion, concentration, volatility metrics)
- **CSV** — raw and cleaned data interchange format

---

## Data source

Raw data is sourced from the Reserve Bank of India's public disclosures on bank-wise Gross NPAs and Gross Advances, available via RBI's **Database on Indian Economy (DBIE)** portal: [https://dbie.rbi.org.in](https://dbie.rbi.org.in)

---

## Repository structure

```
banking-npa-risk-dashboard/
├── Data/
│   ├── raw_npa.csv              # Raw RBI export — messy, multi-year, un-normalized
│   └── cleaned_npas.csv         # Cleaned output — one row per bank per year
├── scripts/
│   ├── rbi_npa_etl_pipeline.sql       # Cleaning script
│   └── credit_risk_analytics_engine.sql  # All 7 credit-risk metrics
└── README.md
```

---

## How to reproduce this

1. **Load the raw data.** Import `Data/raw_npa.csv` into a SQLite database as a table named `raw_npa`.
2. **Run the cleaning script.** Execute `scripts/rbi_npa_etl_pipeline.sql` — this builds the `clean_npa` table by:
   - Forward-filling the `year` column (RBI's export only lists the year once per block, then leaves it blank for subsequent rows)
   - Back-filling each bank's segment (`PUBLIC SECTOR BANKS` / `PRIVATE SECTOR BANKS` / `FOREIGN BANKS` / `SMALL FINANCE BANKS`) from the segment subtotal row that follows it
   - Removing subtotal, aggregate, and footnote rows (e.g. `ALL SCHEDULED COMMERCIAL BANKS`, `Source:`)
   - Converting `-` (not reported) to `NULL` rather than `0`, so averages and totals aren't distorted
3. **Run the analysis.** Execute `scripts/credit_risk_analytics_engine.sql` against `clean_npa`. Each query is self-contained and independently runnable — see comments in the file for what each one measures.
4. **(Optional) Use the pre-cleaned export.** `Data/cleaned_npas.csv` is a static export of the cleaned table if you want to load it straight into Excel/Power BI/Tableau without re-running the SQL.

---

## What the analysis covers

- **Trend metrics** — year-over-year change in NPA ratios at bank and segment level; asset-weighted vs. simple-average comparison to isolate where risk is really concentrated; loan-growth-vs-NPA-growth divergence per bank
- **Segment comparison** — dispersion (median, spread) across the four bank segments; concentration of system-wide NPAs among the top 5 banks
- **Volatility & anomaly detection** — coefficient of variation to flag erratic reporters; year-over-year z-scores to flag statistically unusual single-year jumps

---

## 1. Asset quality trends

**Public Sector Banks had a rough decade, then recovered — but not evenly.**

PSU banks' asset-weighted NPA ratio rose from 2.35% in 2008 to a peak of 13.75% in 2018, then steadily came back down to 2.61% by 2025. That "steady recovery" framing only really applies from 2018 onward, though — the 2008–2018 stretch was a genuine deterioration, not a blip.

One thing that surprised me: I initially assumed the biggest PSU banks (SBI, PNB) would be dragging the sector average up, since they're the ones everyone talks about. The data says the opposite. Comparing the simple average NPA ratio across PSU banks to the *asset-weighted* average (which gives more weight to banks with bigger loan books) shows a consistently **negative** skew in most years — averaging -0.72 points across the full 22-year history, and as much as -2.86 points in 2017. That means the largest PSU banks have generally run *below* the peer average, and the actual stress has been concentrated in smaller, mid-tier PSU banks (think Central Bank of India, UCO Bank, Punjab and Sind Bank), not the systemically important ones. That's a more interesting finding than "big banks are risky," and it's the opposite of what I'd have guessed going in.

Private and Foreign banks show the same negative-skew pattern, more strongly — Foreign banks in particular (average skew -4.66) have their risk concentrated in a handful of small, low-volume institutions, not the well-known names like HDFC or ICICI.

**Where loan growth is outpacing responsible underwriting.** Comparing each bank's total NPA growth to its total advances growth over its full reporting history flags a few banks where bad loans grew dramatically faster than the loan book itself — Bandhan Bank, Kotak Mahindra, and Andhra Bank stand out here. Some of this is a low-base effect (a small bank's NPAs can jump percentage-wise off a tiny starting number), so I'm treating this as a starting point for deeper investigation rather than a verdict.

---

## 2. Comparing segments

| Segment | Median NPA ratio (trend) | Spread across banks | What it suggests |
|---|---|---|---|
| **Public Sector Banks** | High, but falling steadily since 2018 | Wide historically, now compressing sharply (14.7 → 2.2 points) | The sector is converging — weaker PSU banks are catching up to stronger ones, likely reflecting consolidation and cleanup |
| **Private Sector Banks** | Low and stable | Moderate, also compressing | A few weaker underwriters skew the tail, but the segment is broadly consistent |
| **Small Finance Banks** | Volatile | Spiked as high as 44 points in 2023 before dropping to 7 in 2025 | Small, young institutions exposed to localized credit shocks — one bad year at one bank moves the whole segment |
| **Foreign Banks** | Low overall | By far the widest — up to ~100 points | Mostly clean corporate lending books, but a small number of institutions post extreme, isolated ratios |

**Where the risk sits, concretely.** In 2025, the top 5 banks by absolute gross NPAs — SBI, PNB, Union Bank of India, HDFC Bank, and Canara Bank — together account for **51.7%** of all reported system-wide NPAs. That concentration has actually eased somewhat since a 2012 peak of 59.2%, dipped to a low of ~44% around 2019–2020, and has crept back up over the last few years. It's worth noting this is mostly a function of loan book size, not necessarily worse underwriting — SBI alone holds 17.8% of system NPAs in 2025, but it also holds a proportionally large share of total lending.

---

## 3. Volatility and flagging outliers

Looking at which banks have the most erratic NPA history (coefficient of variation across years) turns up a pattern: the most volatile banks are almost entirely small foreign banks with thin, sporadic loan books in India — Bank of America N.A., BNP Paribas, Mizuho Bank. Their NPA ratios swing wildly year to year, but on a small enough base that it's more "noisy" than "risky" in a systemic sense.

Running a year-over-year z-score check (flagging any bank whose NPA ratio jump is a statistical outlier relative to the whole system's typical year-over-year movement) surfaces a handful of genuine one-off events — for example, Royal Bank of Scotland N.V. jumping to a 99.2% NPA ratio in 2017. Its advances book collapsed from ~₹3,539 crore in 2016 to ~₹185 crore in 2017 while it still had ~₹184 crore in bad loans on the books — a bank winding down its India operations rather than a live credit crisis, so this list is more useful as a "worth explaining" flag than a risk ranking on its own.
