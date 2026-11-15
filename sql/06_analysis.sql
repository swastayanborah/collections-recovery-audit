-- =====================================================================
-- 06_analysis.sql
-- Drivers, mix-vs-rate, counterfactual, and channel economics.
-- Simple, explainable methods only.
-- =====================================================================

-- ---------- Driver table: recovery rate by segment, by month ----------
-- recovery rate = collected from segment / outstanding of segment (full book)
CREATE OR REPLACE TABLE a_segment_monthly AS
WITH book AS (
    SELECT 'loan_type' AS dim, loan_type AS segment, SUM(outstanding_amount) AS os FROM g_accounts GROUP BY 2
    UNION ALL SELECT 'dpd_bucket', dpd_bucket, SUM(outstanding_amount) FROM g_accounts GROUP BY 2
    UNION ALL SELECT 'risk_segment', risk_segment, SUM(outstanding_amount) FROM g_accounts GROUP BY 2
    UNION ALL SELECT 'state', state, SUM(outstanding_amount) FROM g_accounts GROUP BY 2
),
paid AS (
    SELECT month, 'loan_type' AS dim, loan_type AS segment, SUM(amount) AS amt FROM g_payments GROUP BY 1, 3
    UNION ALL SELECT month, 'dpd_bucket', dpd_bucket, SUM(amount) FROM g_payments GROUP BY 1, 3
    UNION ALL SELECT month, 'risk_segment', risk_segment, SUM(amount) FROM g_payments GROUP BY 1, 3
    UNION ALL SELECT month, 'state', state, SUM(amount) FROM g_payments GROUP BY 1, 3
)
SELECT p.month, p.dim, p.segment, p.amt / mc.days_in_month AS collected_per_day,
       p.amt / b.os AS recovery_rate
FROM paid p
JOIN book b USING (dim, segment)
JOIN g_month_calendar mc USING (month)
WHERE mc.days_with_data = mc.days_in_month;

-- First half (Jan-Mar) vs second half (May-Jul), per day so month length cannot fool us
CREATE OR REPLACE TABLE a_segment_change AS
SELECT dim, segment,
       AVG(collected_per_day) FILTER (WHERE month <  DATE '2026-04-01') AS per_day_jan_mar,
       AVG(collected_per_day) FILTER (WHERE month >= DATE '2026-05-01') AS per_day_may_jul,
       100 * (AVG(collected_per_day) FILTER (WHERE month >= DATE '2026-05-01')
            / AVG(collected_per_day) FILTER (WHERE month <  DATE '2026-04-01') - 1) AS change_pct
FROM a_segment_monthly GROUP BY 1, 2 ORDER BY dim, change_pct;

-- ---------- Mix vs rate (Feb -> Mar), by DPD bucket ----------
-- rate effect = how much each bucket's own per-day collection changed
-- mix effect  = how much came from buckets changing their share of the book (book is fixed here -> ~0)
CREATE OR REPLACE TABLE a_mix_vs_rate AS
WITH f AS (SELECT segment, collected_per_day AS feb FROM a_segment_monthly WHERE dim = 'dpd_bucket' AND month = DATE '2026-02-01'),
     m AS (SELECT segment, collected_per_day AS mar FROM a_segment_monthly WHERE dim = 'dpd_bucket' AND month = DATE '2026-03-01')
SELECT segment, feb, mar, mar - feb AS change_per_day,
       100 * (mar / feb - 1) AS change_pct
FROM f JOIN m USING (segment) ORDER BY segment;

-- ---------- Operational drivers ----------
-- Contact rate by IST hour (calling time)
CREATE OR REPLACE TABLE a_hour AS
SELECT hour_ist, COUNT(*) AS calls,
       AVG(CASE WHEN call_status = 'ANSWERED' THEN 1.0 ELSE 0 END) AS answer_rate
FROM g_calls WHERE direction = 'OUTBOUND' GROUP BY 1 ORDER BY 1;

-- Contact rate by telephony vendor
CREATE OR REPLACE TABLE a_vendor AS
SELECT c.vendor_id, v.vendor_name, v.status AS vendor_status, COUNT(*) AS calls,
       AVG(CASE WHEN c.call_status = 'ANSWERED' THEN 1.0 ELSE 0 END) AS answer_rate,
       AVG(CASE WHEN c.call_status = 'FAILED'   THEN 1.0 ELSE 0 END) AS fail_rate
FROM g_calls c LEFT JOIN stg_vendor_telephony v USING (vendor_id)
WHERE c.direction = 'OUTBOUND' GROUP BY 1, 2, 3 ORDER BY answer_rate DESC;

-- Attempt frequency: does calling an account more often in a month make it pay?
CREATE OR REPLACE TABLE a_attempts AS
WITH calls_per AS (
    SELECT month, account_id, COUNT(*) AS n_calls FROM g_calls
    WHERE month < DATE '2026-08-01' GROUP BY 1, 2
),
paid AS (SELECT DISTINCT month, account_id FROM g_payments)
SELECT CASE WHEN n_calls >= 5 THEN '5+' ELSE CAST(n_calls AS VARCHAR) END AS calls_in_month,
       COUNT(*) AS account_months,
       AVG(CASE WHEN p.account_id IS NOT NULL THEN 1.0 ELSE 0 END) AS pay_rate
FROM calls_per c LEFT JOIN paid p USING (month, account_id)
GROUP BY 1 ORDER BY 1;

-- Agent tenure: PTPs taken and kept, by how long the agent had been with us
CREATE OR REPLACE TABLE a_tenure AS
SELECT CASE WHEN date_diff('month', a.first_joined_at, p.event_at) < 6  THEN '0-6 months'
            WHEN date_diff('month', a.first_joined_at, p.event_at) < 12 THEN '6-12 months'
            WHEN date_diff('month', a.first_joined_at, p.event_at) < 24 THEN '1-2 years'
            ELSE '2+ years' END AS tenure,
       COUNT(*) AS ptps,
       AVG(CASE WHEN p.status = 'KEPT' THEN 1.0 ELSE 0 END) AS kept_rate
FROM cln_promises_to_pay p JOIN cln_agents a USING (agent_id)
GROUP BY 1 ORDER BY 1;

-- Agent spread: is performance concentrated in a few agents?
CREATE OR REPLACE TABLE a_agent_spread AS
WITH per_agent AS (
    SELECT agent_id, COUNT(*) AS ptps, AVG(CASE WHEN status = 'KEPT' THEN 1.0 ELSE 0 END) AS kept_rate
    FROM cln_promises_to_pay GROUP BY 1
)
SELECT quantile_cont(kept_rate, 0.10) AS p10, quantile_cont(kept_rate, 0.50) AS p50,
       quantile_cont(kept_rate, 0.90) AS p90, AVG(ptps) AS avg_ptps_per_agent
FROM per_agent;

-- ---------- Channel economics: does a touch lift payment? ----------
-- For each channel: share of touched accounts that pay within 7 days of the touch,
-- compared with the BASELINE chance that any account pays in a random 7-day window.
-- uplift = touched pay-rate - baseline. Cost per touch comes from assumption_unit_costs.
CREATE OR REPLACE TABLE a_channel_uplift AS
WITH touches AS (
    SELECT DISTINCT channel, account_id, CAST(touch_at AS DATE) AS d FROM g_touches
    WHERE touch_at < TIMESTAMP '2026-08-01'
),
hit AS (
    SELECT t.channel, t.account_id, t.d,
           MAX(CASE WHEN p.paid_at > t.d AND p.paid_at <= t.d + INTERVAL 7 DAY THEN 1 ELSE 0 END) AS paid_7d,
           SUM(CASE WHEN p.paid_at > t.d AND p.paid_at <= t.d + INTERVAL 7 DAY THEN p.amount ELSE 0 END) AS amt_7d
    FROM touches t LEFT JOIN g_payments p ON p.account_id = t.account_id
    GROUP BY 1, 2, 3
),
baseline AS (   -- any account, any 7-day window: payments per account per 7 days
    SELECT COUNT(DISTINCT payment_id) * 1.0 / (SELECT COUNT(*) FROM g_accounts) / (212 / 7.0) AS pay_rate_7d,
           SUM(amount) / (SELECT COUNT(*) FROM g_accounts) / (212 / 7.0) AS amt_7d
    FROM g_payments WHERE paid_at < TIMESTAMP '2026-08-01'
)
SELECT h.channel, COUNT(*) AS touches,
       AVG(h.paid_7d) AS pay_rate_7d,
       b.pay_rate_7d AS baseline_pay_rate_7d,
       AVG(h.paid_7d) - b.pay_rate_7d AS uplift_pts,
       AVG(h.amt_7d) - b.amt_7d AS incremental_rs_per_touch
FROM hit h CROSS JOIN baseline b
GROUP BY h.channel, b.pay_rate_7d, b.amt_7d ORDER BY uplift_pts DESC;

-- ---------- Counterfactual: the mid-year targeting change ----------
-- Assumption (brief): targeting strategy changed mid-year. We date it to 1 Apr 2026
-- and treat accounts targeted by v3-strategy campaigns from April as TREATED.
-- Control = accounts never targeted by a v3 campaign.
-- Difference-in-differences on rupees collected per account per day.
CREATE OR REPLACE TABLE a_did_groups AS
SELECT a.account_id,
       CASE WHEN a.account_id IN (
                SELECT t.account_id FROM stg_daily_targeting t JOIN stg_campaigns c USING (campaign_id)
                WHERE c.strategy_version = 'v3' AND t.target_date >= DATE '2026-04-01')
            THEN 'treated' ELSE 'control' END AS grp
FROM g_accounts a
WHERE a.account_id NOT IN (     -- drop accounts hit by v3 BEFORE April (contaminated)
    SELECT t.account_id FROM stg_daily_targeting t JOIN stg_campaigns c USING (campaign_id)
    WHERE c.strategy_version = 'v3' AND t.target_date < DATE '2026-04-01');

CREATE OR REPLACE TABLE a_did AS
WITH pay AS (
    SELECT g.grp,
           CASE WHEN p.paid_at < TIMESTAMP '2026-04-01' THEN 'pre' ELSE 'post' END AS period,
           SUM(p.amount) AS amt
    FROM g_payments p JOIN a_did_groups g USING (account_id)
    WHERE p.paid_at < TIMESTAMP '2026-08-01'
    GROUP BY 1, 2
),
n AS (SELECT grp, COUNT(*) AS accounts FROM a_did_groups GROUP BY 1)
SELECT grp, accounts,
       MAX(amt) FILTER (WHERE period = 'pre')  / accounts / 90  AS pre_rs_per_acct_day,   -- Jan-Mar = 90 days
       MAX(amt) FILTER (WHERE period = 'post') / accounts / 122 AS post_rs_per_acct_day   -- Apr-Jul = 122 days
FROM pay JOIN n USING (grp) GROUP BY grp, accounts;

-- Monthly series for the parallel-trends check (the picture that makes or breaks DiD)
CREATE OR REPLACE TABLE a_did_monthly AS
WITH n AS (SELECT grp, COUNT(*) AS accounts FROM a_did_groups GROUP BY 1)
SELECT p.month, g.grp, SUM(p.amount) / n.accounts / mc.days_in_month AS rs_per_acct_day
FROM g_payments p
JOIN a_did_groups g USING (account_id)
JOIN n USING (grp)
JOIN g_month_calendar mc USING (month)
WHERE mc.days_with_data = mc.days_in_month
GROUP BY 1, 2, n.accounts, mc.days_in_month ORDER BY 1, 2;
