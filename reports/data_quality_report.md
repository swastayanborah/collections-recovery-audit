# Data Quality Report

How to read this: every issue has the same four parts (**how I found it → what I did → what it changes in ₹ / %**) and an evidence stamp.
All numbers come from `sql/05_forensics.sql` and can be re-run with `python run_pipeline.py`.

## Raw → Rejected → Golden

| Table | Raw rows | Rejected | Excluded | Golden rows | Note |
|---|---:|---:|---:|---:|---|
| payments | 25,500 | 500 duplicate IDs | 7,466 not SUCCESS | 17,534 | ₹191.7 Cr raw → **₹131.6 Cr real** (−31%) |
| calls | 91,350 | 1,350 duplicate IDs | – | 90,000 | |
| whatsapp_events | 60,600 | 600 duplicate IDs | – | 60,000 | |
| borrowers | 30,600 | 19,585 older versions | – | 11,015 | kept latest `updated_at` |
| agents | 30,000 | 29,000 versions collapsed | – | 1,000 | key = `agent_id` |

## Issues

### 1. Non-recovered money sitting in the payments table · `FACT`
- **How found:** `payment_status` value counts.
- **What:** 3,744 FAILED, 2,592 PENDING and 1,284 REVERSED rows, worth ₹57.6 Cr.
- **Treatment:** only `SUCCESS` counts as recovered.
- **Impact:** any report summing the raw table overstates recovery by about **45%** (₹191.7 Cr vs ₹131.6 Cr).

### 2. Duplicate payment events · `FACT`
- **How found:** `payment_id` appearing more than once (486 of the 500 are exact copies).
- **Treatment:** keep the first event per `payment_id`.
- **Impact:** ₹3.8 Cr removed (₹2.6 Cr of it SUCCESS). The duplicates are spread evenly across months, so they **do not change the month-on-month trend** (Feb→Mar is 10.99% with them, 11.03% without).

### 3. Payment reference collisions · `FACT`
- **How found:** 3,745 `payment_reference` values used by more than one payment, on different accounts and amounts.
- **Treatment:** kept as separate payments and flagged (`flag_ref_collision`). 1.5% of payments have no reference at all (`flag_missing_ref`).
- **Impact:** none on totals, but reference can't be used as a dedup key, which a naive pipeline would do.

### 4. Mixed timezones · `FACT`
- **How found:** `timezone` column on calls, accounts and sessions holds UTC, Asia/Kolkata and Asia/Dubai.
- **Treatment:** convert everything to IST (UTC +5:30, Dubai +1:30). Payments have no timezone column, so I **assume IST**.
- **Impact:** 67% of calls change hour, 23% of UTC calls change day, <1% change month. Breaks "best time to call" analysis, but **not** the monthly trend.

### 5. Agent identity · `FACT`
- **How found:** 30,000 rows, 1,000 `agent_id`s, 1,099 `employee_code`s. Every employee code is shared by several agent IDs.
- **Treatment:** `agent_id` is the canonical key (all event tables use it). Attributes come from the latest version; tenure starts at the **earliest** `joined_at`.
- **Impact:** joining on `employee_code` would multiply agent-level numbers about 30x.

### 6. Disposition code versions · `FACT`
- **How found:** `disposition_version` = legacy / v1 / v2, all active Jan–Aug. `PTP` and `PROMISE_TO_PAY` both mean a promise.
- **Treatment:** mapped to one standard code (`disposition_std`).
- **Impact:** counting only `PTP` **halves the PTP rate** (29% → 14%).

### 7. Overwritten account status · `FACT`
- **How found:** `accounts.status` holds only today's state; 75% of collected money comes from accounts that are now CLOSED, PAID or WRITEOFF.
- **Treatment:** never filter history on current status. Use `account_status_history` for point-in-time status.
- **Impact:** an "active accounts only" report would drop **~75%** of past recovery.

### 8. Conflicting timestamps in status history · `FACT`
- **How found:** `recorded_at` earlier than `event_at` in 30,191 of 60,000 rows (impossible).
- **Treatment:** trust `event_at` (business time) and flag the row.
- **Impact:** low for this analysis; it matters for any "time to status change" metric.

### 9. Missing values · `FACT`
| Column | Missing | Treatment |
|---|---:|---|
| accounts.borrower_id | 1.5% | kept; geography = UNKNOWN |
| borrowers.phone / email | 2.0% / 2.9% | not used in analysis |
| calls.agent_id | 2.0% | kept; excluded from agent-level cuts only |
| call_attempts.vendor_id | 2.0% | kept |
| field_visits.scheduled_at | 1.0% | not used |

### 10. Data that is simply not there · `FACT`
- No **client** or **language** field: two of the brief's drivers can't be tested.
- No **cost** data: cost-per-₹ uses stated unit-cost assumptions (`assumption_unit_costs` in `04_metrics.sql`).
- Only **7 months** (1 Jan – 8 Aug 2026), not 12. August is partial and excluded from month comparisons.
- Inactive telephony vendors (9 of 15) still carry calls all period. A vendor master that disagrees with the event data.

## Assumptions (in one place)
1. Payments without a timezone are IST.
2. `SUCCESS` = money received; REVERSED rows are separate events and are not netted against earlier SUCCESS rows.
3. A borrower "touch" = answered call, read/replied/clicked WhatsApp, delivered/clicked SMS, or a field visit that met someone.
4. The allocated book is constant over the period (every account was opened before 2026).
