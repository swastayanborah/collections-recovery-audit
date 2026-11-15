-- =====================================================================
-- 03_golden.sql
-- The trusted analytical layer. Everything downstream reads ONLY g_* tables.
-- =====================================================================

-- ---------- g_accounts: one row per account with borrower attributes ----------
CREATE OR REPLACE TABLE g_accounts AS
SELECT a.account_id, a.borrower_id, a.loan_type, a.principal_amount, a.outstanding_amount,
       a.dpd, a.dpd_bucket, a.risk_segment, a.status AS current_status,
       a.opened_at_ist, a.flag_missing_borrower,
       COALESCE(b.state, 'UNKNOWN') AS state,
       COALESCE(b.city,  'UNKNOWN') AS city
FROM cln_accounts a
LEFT JOIN cln_borrowers b USING (borrower_id);

-- ---------- g_touches: every contact with a borrower, one table ----------
-- Only touches that actually reached the borrower count.
CREATE OR REPLACE TABLE g_touches AS
SELECT account_id, event_at_ist AS touch_at, 'VOICE' AS channel, campaign_id, agent_id
FROM cln_calls WHERE call_status = 'ANSWERED'
UNION ALL
SELECT account_id, event_at, 'WHATSAPP', NULL, NULL
FROM cln_whatsapp WHERE event_type IN ('READ', 'REPLIED', 'PAYMENT_CLICK')
UNION ALL
SELECT account_id, event_at, 'SMS', NULL, NULL
FROM cln_sms WHERE event_type IN ('DELIVERED', 'CLICKED')
UNION ALL
SELECT account_id, event_at, 'FIELD', NULL, agent_id
FROM cln_field_visits WHERE outcome NOT IN ('NOT_AVAILABLE', 'WRONG_ADDRESS');

-- ---------- g_payments: real money only ----------
-- Recovered = SUCCESS and de-duplicated. FAILED / PENDING / REVERSED are not money in the bank.
CREATE OR REPLACE TABLE g_payments_base AS
SELECT p.payment_id, p.account_id, p.event_at_ist AS paid_at, p.amount, p.payment_method,
       p.flag_ref_collision, p.flag_missing_ref,
       a.loan_type, a.dpd_bucket, a.risk_segment, a.state
FROM cln_payments p
LEFT JOIN g_accounts a USING (account_id)
WHERE p.payment_status = 'SUCCESS';

-- Payment attribution: last touch BEFORE the payment, and how old it was.
CREATE OR REPLACE TABLE g_payment_last_touch AS
SELECT p.payment_id,
       arg_max(t.channel, t.touch_at)     AS last_channel,
       arg_max(t.campaign_id, t.touch_at) AS last_campaign_id,
       date_diff('day', MAX(t.touch_at), p.paid_at) AS days_since_touch
FROM g_payments_base p
JOIN g_touches t
  ON t.account_id = p.account_id AND t.touch_at < p.paid_at
GROUP BY p.payment_id, p.paid_at;

CREATE OR REPLACE TABLE g_payments AS
SELECT p.*,
       lt.last_channel, lt.last_campaign_id, lt.days_since_touch,
       -- our rule: credit a channel only if it touched the borrower within 7 days
       CASE WHEN lt.days_since_touch <= 7 THEN lt.last_channel ELSE 'UNATTRIBUTED' END AS channel_7d,
       date_trunc('month', p.paid_at) AS month
FROM g_payments_base p
LEFT JOIN g_payment_last_touch lt USING (payment_id);

-- ---------- g_calls ----------
CREATE OR REPLACE TABLE g_calls AS
SELECT c.call_id, c.account_id, c.agent_id, c.campaign_id, c.vendor_id, c.direction,
       c.call_status, c.duration_sec, c.timezone AS source_tz,
       c.event_at AS event_at_raw, c.event_at_ist,
       hour(c.event_at_ist) AS hour_ist,
       date_trunc('month', c.event_at_ist) AS month
FROM cln_calls c;

-- ---------- g_month_calendar: the months we can fairly compare ----------
-- August 2026 only has 8 days of data -> excluded from month-on-month comparisons.
CREATE OR REPLACE TABLE g_month_calendar AS
SELECT month,
       date_diff('day', month, month + INTERVAL 1 MONTH) AS days_in_month,
       COUNT(DISTINCT CAST(paid_at AS DATE))             AS days_with_data
FROM g_payments GROUP BY month;
