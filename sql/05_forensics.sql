-- =====================================================================
-- 05_forensics.sql
-- The seven "suspects" (A-G) from the brief. Each check ends in a number.
-- =====================================================================

-- ---------- Raw -> Rejected -> Golden waterfall ----------
CREATE OR REPLACE TABLE dq_waterfall AS
SELECT 'payments' AS tbl,
       (SELECT COUNT(*) FROM stg_payments) AS raw_rows,
       (SELECT COUNT(*) FROM rejected_payments) AS rejected_duplicates,
       (SELECT COUNT(*) FROM cln_payments WHERE payment_status <> 'SUCCESS') AS excluded_not_success,
       (SELECT COUNT(*) FROM g_payments) AS golden_rows,
       (SELECT SUM(amount) FROM stg_payments) AS raw_amount,
       (SELECT SUM(amount) FROM g_payments) AS golden_amount
UNION ALL SELECT 'calls', (SELECT COUNT(*) FROM stg_calls), (SELECT COUNT(*) FROM rejected_calls), 0,
       (SELECT COUNT(*) FROM g_calls), NULL, NULL
UNION ALL SELECT 'whatsapp_events', (SELECT COUNT(*) FROM stg_whatsapp_events), (SELECT COUNT(*) FROM rejected_whatsapp), 0,
       (SELECT COUNT(*) FROM cln_whatsapp), NULL, NULL
UNION ALL SELECT 'borrowers', (SELECT COUNT(*) FROM stg_borrowers), (SELECT COUNT(*) FROM rejected_borrowers), 0,
       (SELECT COUNT(*) FROM cln_borrowers), NULL, NULL
UNION ALL SELECT 'agents', (SELECT COUNT(*) FROM stg_agents), (SELECT COUNT(*) FROM stg_agents) - (SELECT COUNT(*) FROM cln_agents), 0,
       (SELECT COUNT(*) FROM cln_agents), NULL, NULL;

-- ---------- A. Duplicate payments ----------
CREATE OR REPLACE TABLE f_a_duplicates AS
SELECT COUNT(*) AS duplicate_rows,
       SUM(amount) AS duplicate_amount,
       SUM(amount) FILTER (WHERE payment_status = 'SUCCESS') AS duplicate_success_amount,
       (SELECT COUNT(*) FROM cln_payments WHERE flag_ref_collision) AS rows_sharing_a_reference,
       (SELECT SUM(amount) FROM stg_payments WHERE payment_status IN ('FAILED','PENDING','REVERSED')) AS non_success_amount
FROM rejected_payments;

-- ---------- B. Attribution ----------
-- How many payments get credited to a channel under different rules?
CREATE OR REPLACE TABLE f_b_attribution AS
SELECT 'last touch, any time'  AS rule, AVG(CASE WHEN last_channel IS NOT NULL THEN 1.0 ELSE 0 END) AS share_credited FROM g_payments
UNION ALL SELECT 'last touch within 30 days', AVG(CASE WHEN days_since_touch <= 30 THEN 1.0 ELSE 0 END) FROM g_payments
UNION ALL SELECT 'last touch within 7 days',  AVG(CASE WHEN days_since_touch <= 7  THEN 1.0 ELSE 0 END) FROM g_payments
UNION ALL SELECT 'last touch within 1 day',   AVG(CASE WHEN days_since_touch <= 1  THEN 1.0 ELSE 0 END) FROM g_payments;

-- Payments credited to a campaign that had already ENDED when the payment came in
CREATE OR REPLACE TABLE f_b_campaign_after_end AS
SELECT COUNT(*) AS credited_to_campaign,
       COUNT(*) FILTER (WHERE p.paid_at > c.end_at) AS campaign_already_ended,
       SUM(p.amount) FILTER (WHERE p.paid_at > c.end_at) AS amount_after_end
FROM g_payments p JOIN stg_campaigns c ON c.campaign_id = p.last_campaign_id;

-- ---------- C. Timezones ----------
CREATE OR REPLACE TABLE f_c_timezone AS
SELECT source_tz,
       COUNT(*) AS calls,
       AVG(CASE WHEN hour(event_at_raw) <> hour_ist THEN 1.0 ELSE 0 END) AS share_hour_changes,
       AVG(CASE WHEN CAST(event_at_raw AS DATE) <> CAST(event_at_ist AS DATE) THEN 1.0 ELSE 0 END) AS share_day_changes,
       AVG(CASE WHEN date_trunc('month', event_at_raw) <> month THEN 1.0 ELSE 0 END) AS share_month_changes,
       -- calls outside 8am-7pm IST (borrower contact-hour rules)
       AVG(CASE WHEN hour(event_at_raw) NOT BETWEEN 8 AND 18 THEN 1.0 ELSE 0 END) AS outside_hours_raw,
       AVG(CASE WHEN hour_ist NOT BETWEEN 8 AND 18 THEN 1.0 ELSE 0 END) AS outside_hours_ist
FROM g_calls GROUP BY source_tz;

-- ---------- D. Vendor / disposition code mapping ----------
CREATE OR REPLACE TABLE f_d_codes AS
SELECT disposition_version,
       COUNT(*) AS rows_,
       COUNT(*) FILTER (WHERE disposition_code = 'PTP') AS coded_ptp,
       COUNT(*) FILTER (WHERE disposition_code = 'PROMISE_TO_PAY') AS coded_promise_to_pay,
       MIN(event_at) AS first_seen, MAX(event_at) AS last_seen
FROM cln_call_dispositions GROUP BY 1 ORDER BY 1;

-- ---------- E. Agent identity ----------
CREATE OR REPLACE TABLE f_e_agents AS
SELECT (SELECT COUNT(*) FROM stg_agents) AS agent_rows,
       (SELECT COUNT(DISTINCT agent_id) FROM stg_agents) AS distinct_agent_ids,
       (SELECT COUNT(DISTINCT employee_code) FROM stg_agents) AS distinct_employee_codes,
       (SELECT COUNT(*) FROM dq_agent_code_conflicts) AS codes_shared_by_many_ids,
       (SELECT AVG(n_employee_codes) FROM cln_agents) AS avg_codes_per_agent,
       (SELECT COUNT(DISTINCT agent_id) FROM stg_agent_sessions) AS agents_with_sessions,
       (SELECT AVG(CASE WHEN session_hours <= 0 OR session_hours > 16 THEN 1.0 ELSE 0 END) FROM cln_agent_sessions) AS share_bad_sessions;

-- ---------- F. Portfolio mix ----------
-- Share of collected money by segment, per month. If the mix moved, rates can move without anyone working better.
CREATE OR REPLACE TABLE f_f_mix AS
SELECT month, 'loan_type' AS dim, loan_type AS segment, SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY month) AS share
FROM g_payments WHERE month < DATE '2026-08-01' GROUP BY 1, 3
UNION ALL
SELECT month, 'dpd_bucket', dpd_bucket, SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY month)
FROM g_payments WHERE month < DATE '2026-08-01' GROUP BY 1, 3
UNION ALL
SELECT month, 'risk_segment', risk_segment, SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY month)
FROM g_payments WHERE month < DATE '2026-08-01' GROUP BY 1, 3;

CREATE OR REPLACE TABLE f_f_mix_drift AS
SELECT dim, segment, MIN(share) AS min_share, MAX(share) AS max_share, MAX(share) - MIN(share) AS drift
FROM f_f_mix GROUP BY 1, 2 ORDER BY drift DESC;

-- ---------- G. Denominator manipulation ----------
-- "Recovery rate" computed only on accounts we CALLED that month (the worked book)
-- vs on the whole allocated book. If the worked book shrinks, the rate rises for free.
CREATE OR REPLACE TABLE f_g_denominator AS
WITH worked AS (
    SELECT DISTINCT month, account_id FROM g_calls
),
worked_book AS (
    SELECT w.month, COUNT(*) AS worked_accounts, SUM(a.outstanding_amount) AS worked_outstanding
    FROM worked w JOIN g_accounts a USING (account_id) GROUP BY 1
),
paid_by_worked AS (
    SELECT p.month, SUM(p.amount) AS collected_from_worked
    FROM g_payments p JOIN worked w ON w.account_id = p.account_id AND w.month = p.month
    GROUP BY 1
)
SELECT m.month, wb.worked_accounts,
       (SELECT COUNT(*) FROM g_accounts) AS book_accounts,
       pw.collected_from_worked / wb.worked_outstanding AS rate_on_worked_book,
       m.true_collected / (SELECT SUM(outstanding_amount) FROM g_accounts) AS rate_on_full_book,
       -- accounts in a terminal status (written off / closed) are often silently dropped
       (SELECT COUNT(*) FROM g_accounts WHERE current_status IN ('WRITEOFF','CLOSED')) AS terminal_accounts
FROM m_monthly m
JOIN worked_book wb USING (month)
JOIN paid_by_worked pw USING (month)
ORDER BY m.month;

-- ---------- One-line summary per suspect (feeds the report + dashboard) ----------
CREATE OR REPLACE TABLE f_summary AS
SELECT 'A' AS code, 'Duplicate payments' AS suspect,
       'FACT' AS evidence,
       printf('%d duplicate rows (Rs %.2f Cr); Rs %.1f Cr of FAILED/PENDING/REVERSED rows sit in the same table',
              duplicate_rows, duplicate_amount / 1e7, non_success_amount / 1e7) AS finding
FROM f_a_duplicates
UNION ALL
SELECT 'B', 'Attribution errors', 'FACT',
       printf('Last-touch credits %.0f%% of payments to a channel; only %.0f%% had a touch in the 7 days before paying',
              100 * MAX(share_credited) FILTER (WHERE rule = 'last touch, any time'),
              100 * MAX(share_credited) FILTER (WHERE rule = 'last touch within 7 days'))
FROM f_b_attribution
UNION ALL
SELECT 'C', 'Timezone problems', 'FACT',
       printf('%.0f%% of calls are stored in UTC or Dubai time; converting to IST moves %.0f%% of all calls to a different hour',
              100 * SUM(calls) FILTER (WHERE source_tz <> 'Asia/Kolkata') / SUM(calls),
              100 * SUM(calls * share_hour_changes) / SUM(calls))
FROM f_c_timezone
UNION ALL
SELECT 'D', 'Disposition code changes', 'FACT',
       printf('3 code versions run side by side all year; PTP is logged as both PTP and PROMISE_TO_PAY, so counting one code halves PTPs')
UNION ALL
SELECT 'E', 'Agent identity', 'FACT',
       printf('%d agent rows -> %d real agents; %d employee codes, %d of them shared across agents',
              agent_rows, distinct_agent_ids, distinct_employee_codes, codes_shared_by_many_ids)
FROM f_e_agents
UNION ALL
SELECT 'F', 'Portfolio mix change', 'STRONG',
       printf('Largest monthly swing in any segment share of collections: %.1f pts -> no meaningful mix shift', 100 * MAX(drift))
FROM f_f_mix_drift
UNION ALL
SELECT 'G', 'Denominator manipulation', 'STRONG',
       printf('Rate on worked accounts only is %.1fx the rate on the full book', AVG(rate_on_worked_book / rate_on_full_book))
FROM f_g_denominator;
