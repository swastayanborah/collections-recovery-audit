-- =====================================================================
-- 04_metrics.sql
-- One monthly table with BOTH the "reported-style" number and our number,
-- so every difference is visible side by side.
-- =====================================================================

-- ---------- Unit cost assumptions (no cost data was provided) ----------
-- These are ASSUMPTIONS, stated openly. Change them here and everything reruns.
CREATE OR REPLACE TABLE assumption_unit_costs AS
SELECT * FROM (VALUES
    ('VOICE_CALL',   8.0,  'per dialled call (telephony + share of agent time)'),
    ('WHATSAPP_MSG', 0.9,  'per WhatsApp business message'),
    ('SMS_MSG',      0.2,  'per SMS'),
    ('FIELD_VISIT',  350.0,'per field visit (travel + agent time)')
) t(item, cost_inr, note);

-- ---------- Monthly metrics ----------
CREATE OR REPLACE TABLE m_monthly AS
WITH
reported AS (   -- how the business most likely computed recovery: raw table, SUCCESS rows, no dedup
    SELECT date_trunc('month', event_at) AS month, SUM(amount) AS reported_collected
    FROM stg_payments WHERE payment_status = 'SUCCESS' GROUP BY 1
),
gross AS (      -- even worse: every payment row regardless of status
    SELECT date_trunc('month', event_at) AS month, SUM(amount) AS gross_all_rows
    FROM stg_payments GROUP BY 1
),
truth AS (
    SELECT month, SUM(amount) AS true_collected,
           COUNT(DISTINCT account_id) AS paying_accounts,
           COUNT(*) AS n_payments
    FROM g_payments GROUP BY 1
),
calls AS (
    SELECT month,
           COUNT(*) FILTER (WHERE direction = 'OUTBOUND') AS outbound_calls,
           COUNT(*) FILTER (WHERE direction = 'OUTBOUND' AND call_status = 'ANSWERED') AS outbound_answered
    FROM g_calls GROUP BY 1
),
dispo AS (
    SELECT date_trunc('month', event_at) AS month,
           COUNT(*) AS dispositions,
           COUNT(*) FILTER (WHERE is_rpc) AS rpc,
           COUNT(*) FILTER (WHERE disposition_std = 'PTP') AS ptp_dispo_std,
           COUNT(*) FILTER (WHERE disposition_code = 'PTP') AS ptp_dispo_one_code_only
    FROM cln_call_dispositions GROUP BY 1
),
ptp AS (        -- promises judged by the month they were DUE
    SELECT date_trunc('month', promised_date) AS month,
           COUNT(*) AS ptp_due,
           COUNT(*) FILTER (WHERE status = 'KEPT') AS kept,
           COUNT(*) FILTER (WHERE status = 'BROKEN') AS broken,
           COUNT(*) FILTER (WHERE status = 'CANCELLED') AS cancelled
    FROM cln_promises_to_pay GROUP BY 1
),
hours AS (
    SELECT date_trunc('month', login_at_ist) AS month, SUM(session_hours) AS agent_hours
    FROM cln_agent_sessions GROUP BY 1
),
cost AS (
    SELECT month, SUM(c) AS est_cost FROM (
        SELECT g.month, COUNT(*) * (SELECT cost_inr FROM assumption_unit_costs WHERE item = 'VOICE_CALL') AS c
        FROM g_calls g WHERE direction = 'OUTBOUND' GROUP BY 1
        UNION ALL
        SELECT date_trunc('month', event_at), COUNT(*) * (SELECT cost_inr FROM assumption_unit_costs WHERE item = 'WHATSAPP_MSG')
        FROM cln_whatsapp WHERE event_type = 'SENT' GROUP BY 1
        UNION ALL
        SELECT date_trunc('month', event_at), COUNT(*) * (SELECT cost_inr FROM assumption_unit_costs WHERE item = 'SMS_MSG')
        FROM cln_sms WHERE event_type = 'SENT' GROUP BY 1
        UNION ALL
        SELECT date_trunc('month', event_at), COUNT(*) * (SELECT cost_inr FROM assumption_unit_costs WHERE item = 'FIELD_VISIT')
        FROM cln_field_visits GROUP BY 1
    ) GROUP BY month
),
book AS (       -- the denominator: the WHOLE allocated book, not just accounts we worked
    SELECT SUM(outstanding_amount) AS book_outstanding, COUNT(*) AS book_accounts FROM g_accounts
)
SELECT t.month,
       mc.days_in_month,
       mc.days_with_data,
       mc.days_with_data = mc.days_in_month                   AS is_complete_month,
       g.gross_all_rows,
       r.reported_collected,
       t.true_collected,
       t.true_collected / mc.days_with_data                   AS true_collected_per_day,
       t.true_collected / b.book_outstanding                  AS recovery_rate_month,
       t.true_collected / b.book_accounts                     AS recovery_per_account,
       t.paying_accounts, t.n_payments,
       c.outbound_calls, c.outbound_answered,
       c.outbound_answered * 1.0 / c.outbound_calls           AS contact_rate,
       d.rpc * 1.0 / d.dispositions                           AS rpc_rate,
       d.ptp_dispo_std * 1.0 / d.rpc                          AS ptp_rate_per_rpc,
       d.ptp_dispo_one_code_only * 1.0 / d.rpc                AS ptp_rate_if_one_code_missed,
       p.kept * 1.0 / NULLIF(p.kept + p.broken, 0)            AS ptp_kept_rate_naive,
       p.kept * 1.0 / NULLIF(p.ptp_due, 0)                    AS ptp_kept_rate_true,
       h.agent_hours,
       t.true_collected / h.agent_hours                       AS recovery_per_agent_hour,
       co.est_cost,
       co.est_cost / t.true_collected                         AS cost_per_rupee
FROM truth t
JOIN g_month_calendar mc USING (month)
LEFT JOIN reported r USING (month)
LEFT JOIN gross g USING (month)
LEFT JOIN calls c USING (month)
LEFT JOIN dispo d USING (month)
LEFT JOIN ptp p USING (month)
LEFT JOIN hours h USING (month)
LEFT JOIN cost co USING (month)
CROSS JOIN book b
ORDER BY t.month;

-- ---------- Month-on-month: reported vs true ----------
CREATE OR REPLACE TABLE m_mom AS
SELECT month, is_complete_month,
       100 * (reported_collected / LAG(reported_collected) OVER w - 1)         AS reported_mom_pct,
       100 * (true_collected / LAG(true_collected) OVER w - 1)                 AS true_total_mom_pct,
       100 * (true_collected_per_day / LAG(true_collected_per_day) OVER w - 1) AS true_per_day_mom_pct
FROM m_monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;

-- ---------- The claim audit: walk from +11% to the truth (Feb -> Mar 2026) ----------
-- Each step removes ONE error, in order. The steps add up to the gap.
CREATE OR REPLACE TABLE m_claim_audit AS
WITH f AS (SELECT * FROM m_monthly WHERE month = DATE '2026-02-01'),
     m AS (SELECT * FROM m_monthly WHERE month = DATE '2026-03-01'),
     steps AS (
        SELECT 1 AS step, 'Reported (raw SUCCESS rows, Feb -> Mar)' AS label,
               100 * (m.reported_collected / f.reported_collected - 1) AS value_pct FROM f, m
        UNION ALL
        SELECT 2, 'After removing duplicate payment rows',
               100 * (m.true_collected / f.true_collected - 1) FROM f, m
        UNION ALL
        SELECT 3, 'After adjusting for days in month (28 vs 31)',
               100 * (m.true_collected_per_day / f.true_collected_per_day - 1) FROM f, m
     )
SELECT step, label, value_pct,
       value_pct - LAG(value_pct) OVER (ORDER BY step) AS change_from_previous
FROM steps ORDER BY step;
