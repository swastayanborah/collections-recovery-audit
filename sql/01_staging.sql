-- =====================================================================
-- 01_staging.sql
-- Load raw CSVs as-is, fix types, and convert every timestamp to IST.
-- Rule: staging never drops a row. It only adds clean columns.
-- =====================================================================

-- Helper: shift a local timestamp to IST based on its timezone label.
--   UTC        -> +5:30
--   Asia/Dubai -> +1:30 (Dubai is UTC+4, IST is UTC+5:30)
--   Asia/Kolkata or missing -> no change (assumed already IST)
CREATE OR REPLACE MACRO to_ist(ts, tz) AS
    CASE tz
        WHEN 'UTC'        THEN ts + INTERVAL 330 MINUTE
        WHEN 'Asia/Dubai' THEN ts + INTERVAL 90 MINUTE
        ELSE ts
    END;

CREATE OR REPLACE TABLE stg_payments AS
SELECT *, event_at AS event_at_ist            -- no tz column: assumed IST (payment gateway)
FROM read_csv_auto('collections_30k_dataset/payments.csv');

CREATE OR REPLACE TABLE stg_calls AS
SELECT *, to_ist(event_at, timezone) AS event_at_ist
FROM read_csv_auto('collections_30k_dataset/calls.csv');

CREATE OR REPLACE TABLE stg_call_attempts AS
SELECT * FROM read_csv_auto('collections_30k_dataset/call_attempts.csv');

CREATE OR REPLACE TABLE stg_call_dispositions AS
SELECT * FROM read_csv_auto('collections_30k_dataset/call_dispositions.csv');

CREATE OR REPLACE TABLE stg_accounts AS
SELECT *, to_ist(opened_at, timezone) AS opened_at_ist
FROM read_csv_auto('collections_30k_dataset/accounts.csv');

CREATE OR REPLACE TABLE stg_borrowers AS
SELECT * REPLACE (CAST(CAST(phone AS BIGINT) AS VARCHAR) AS phone)   -- '9037419103.0' -> '9037419103'
FROM read_csv_auto('collections_30k_dataset/borrowers.csv');

CREATE OR REPLACE TABLE stg_agents AS
SELECT * FROM read_csv_auto('collections_30k_dataset/agents.csv');

CREATE OR REPLACE TABLE stg_agent_sessions AS
SELECT *, to_ist(login_at, timezone)  AS login_at_ist,
          to_ist(logout_at, timezone) AS logout_at_ist
FROM read_csv_auto('collections_30k_dataset/agent_sessions.csv');

CREATE OR REPLACE TABLE stg_campaigns        AS SELECT * FROM read_csv_auto('collections_30k_dataset/campaigns.csv');
CREATE OR REPLACE TABLE stg_daily_targeting  AS SELECT * FROM read_csv_auto('collections_30k_dataset/daily_targeting.csv');
CREATE OR REPLACE TABLE stg_whatsapp_events  AS SELECT * FROM read_csv_auto('collections_30k_dataset/whatsapp_events.csv');
CREATE OR REPLACE TABLE stg_sms_events       AS SELECT * FROM read_csv_auto('collections_30k_dataset/sms_events.csv');
CREATE OR REPLACE TABLE stg_field_visits     AS SELECT * FROM read_csv_auto('collections_30k_dataset/field_visits.csv');
CREATE OR REPLACE TABLE stg_promises_to_pay  AS SELECT * FROM read_csv_auto('collections_30k_dataset/promises_to_pay.csv');
CREATE OR REPLACE TABLE stg_vendor_telephony AS SELECT * FROM read_csv_auto('collections_30k_dataset/vendor_telephony.csv');
CREATE OR REPLACE TABLE stg_complaints       AS SELECT * FROM read_csv_auto('collections_30k_dataset/complaints.csv');
CREATE OR REPLACE TABLE stg_account_status_history AS
SELECT * FROM read_csv_auto('collections_30k_dataset/account_status_history.csv');
