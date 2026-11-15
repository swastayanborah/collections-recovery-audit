-- =====================================================================
-- 02_clean.sql
-- Deduplicate, resolve identities, standardise codes.
-- Every removed row goes into a rejected_* table with a reason,
-- so the cleaning can be audited (Raw -> Rejected -> Golden).
-- =====================================================================

-- ---------- Payments ----------
-- Same payment_id appearing more than once = ingestion retry. Keep the first.
CREATE OR REPLACE TABLE cln_payments_ranked AS
SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at) AS rn
FROM stg_payments;

CREATE OR REPLACE TABLE rejected_payments AS
SELECT * EXCLUDE (rn), 'duplicate payment_id (ingestion retry)' AS reason
FROM cln_payments_ranked WHERE rn > 1;

CREATE OR REPLACE TABLE cln_payments AS
SELECT * EXCLUDE (rn),
       -- the same payment_reference is reused across different accounts/amounts:
       -- we keep these rows (they are different payments) but flag them
       COUNT(*) OVER (PARTITION BY payment_reference) > 1
           AND payment_reference IS NOT NULL AS flag_ref_collision,
       payment_reference IS NULL AS flag_missing_ref
FROM cln_payments_ranked WHERE rn = 1;

-- ---------- Calls ----------
CREATE OR REPLACE TABLE cln_calls_ranked AS
SELECT *, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at) AS rn FROM stg_calls;

CREATE OR REPLACE TABLE rejected_calls AS
SELECT * EXCLUDE (rn), 'duplicate call_id' AS reason FROM cln_calls_ranked WHERE rn > 1;

CREATE OR REPLACE TABLE cln_calls AS
SELECT * EXCLUDE (rn) FROM cln_calls_ranked WHERE rn = 1;

-- ---------- WhatsApp ----------
CREATE OR REPLACE TABLE cln_whatsapp_ranked AS
SELECT *, ROW_NUMBER() OVER (PARTITION BY whatsapp_event_id ORDER BY event_at) AS rn
FROM stg_whatsapp_events;

CREATE OR REPLACE TABLE rejected_whatsapp AS
SELECT * EXCLUDE (rn), 'duplicate whatsapp_event_id' AS reason FROM cln_whatsapp_ranked WHERE rn > 1;

CREATE OR REPLACE TABLE cln_whatsapp AS
SELECT * EXCLUDE (rn) FROM cln_whatsapp_ranked WHERE rn = 1;

-- ---------- Borrowers ----------
-- 30,600 rows but ~11k real borrowers: the table keeps old versions.
-- Keep the most recently updated version of each borrower.
CREATE OR REPLACE TABLE cln_borrowers_ranked AS
SELECT *, ROW_NUMBER() OVER (PARTITION BY borrower_id ORDER BY updated_at DESC) AS rn
FROM stg_borrowers;

CREATE OR REPLACE TABLE rejected_borrowers AS
SELECT * EXCLUDE (rn), 'older version of same borrower_id' AS reason
FROM cln_borrowers_ranked WHERE rn > 1;

CREATE OR REPLACE TABLE cln_borrowers AS
SELECT * EXCLUDE (rn) FROM cln_borrowers_ranked WHERE rn = 1;

-- ---------- Agents (entity resolution) ----------
-- 30,000 rows, 1,000 agent_ids, 1,099 employee_codes.
-- One agent_id carries up to ~48 employee codes and one code maps to many agent_ids,
-- so employee_code is NOT a usable key. Decision: agent_id is the canonical key
-- (every event table uses it). Keep the latest version for attributes,
-- and the EARLIEST joined_at as the true tenure start.
CREATE OR REPLACE TABLE cln_agents AS
SELECT agent_id,
       arg_max(team, updated_at)        AS team,
       arg_max(status, updated_at)      AS status,
       arg_max(vendor_id, updated_at)   AS vendor_id,
       MIN(joined_at)                   AS first_joined_at,
       COUNT(*)                         AS n_versions,
       COUNT(DISTINCT employee_code)    AS n_employee_codes
FROM stg_agents
GROUP BY agent_id;

-- employee codes shared by more than one agent_id (identity conflicts)
CREATE OR REPLACE TABLE dq_agent_code_conflicts AS
SELECT employee_code, COUNT(DISTINCT agent_id) AS n_agent_ids
FROM stg_agents GROUP BY employee_code HAVING COUNT(DISTINCT agent_id) > 1;

-- ---------- Dispositions ----------
-- 'PTP' and 'PROMISE_TO_PAY' are the same outcome under different code versions.
CREATE OR REPLACE TABLE cln_call_dispositions AS
SELECT *,
       CASE disposition_code WHEN 'PROMISE_TO_PAY' THEN 'PTP' ELSE disposition_code END AS disposition_std,
       -- Right-party contact = we actually spoke to the borrower
       disposition_code NOT IN ('NO_CONTACT', 'WRONG_NUMBER') AS is_rpc
FROM stg_call_dispositions;

-- ---------- Account status history ----------
-- recorded_at earlier than event_at is impossible -> conflicting timestamps.
-- We trust event_at (business time) and flag the conflict.
CREATE OR REPLACE TABLE cln_account_status_history AS
SELECT *, recorded_at < event_at AS flag_recorded_before_event
FROM stg_account_status_history;

-- ---------- Accounts ----------
CREATE OR REPLACE TABLE cln_accounts AS
SELECT *,
       borrower_id IS NULL AS flag_missing_borrower,
       CASE WHEN dpd = 0 THEN '0'
            WHEN dpd <= 30 THEN '1-30'
            WHEN dpd <= 60 THEN '31-60'
            WHEN dpd <= 90 THEN '61-90'
            ELSE '90+' END AS dpd_bucket
FROM stg_accounts;

-- ---------- Tables with no problems found: pass through ----------
CREATE OR REPLACE TABLE cln_call_attempts   AS SELECT * FROM stg_call_attempts;
CREATE OR REPLACE TABLE cln_sms             AS SELECT * FROM stg_sms_events;
CREATE OR REPLACE TABLE cln_field_visits    AS SELECT * FROM stg_field_visits;
CREATE OR REPLACE TABLE cln_promises_to_pay AS SELECT * FROM stg_promises_to_pay;
CREATE OR REPLACE TABLE cln_agent_sessions  AS
SELECT *, date_diff('minute', login_at_ist, logout_at_ist) / 60.0 AS session_hours
FROM stg_agent_sessions;
