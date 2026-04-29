-- audit_pre_check
-- ===============
-- Aggregated audit/sanity checks across the schema. View per check_id
-- with row counts + targets, surfaced for the operations dashboard.

CREATE OR REPLACE VIEW audit_pre_check AS
WITH
check_1_open_overdue_ca AS (
  SELECT
    1 AS check_id,
    'Open / overdue corrective actions' AS title,
    'ops_corrective_action_taken' AS source,
    COUNT(*)::int AS row_count,
    'Should be 0 if all CAs past due_date are resolved' AS target
  FROM ops_corrective_action_taken
  WHERE COALESCE(is_deleted, false) = false
    AND is_resolved = false
    AND due_date IS NOT NULL
    AND due_date < CURRENT_DATE
),
check_2_failed_emp_no_retest AS (
  SELECT
    2 AS check_id,
    'EMP/lab failures with no follow-up within 7 days' AS title,
    'fsafe_result' AS source,
    COUNT(*)::int AS row_count,
    'Should be 0' AS target
  FROM fsafe_result fr
  WHERE COALESCE(fr.is_deleted, false) = false
    AND fr.initial_retest_vector = 'initial'
    AND fr.result_pass = false
    AND fr.sampled_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM fsafe_result fr2
      WHERE COALESCE(fr2.is_deleted, false) = false
        AND fr2.fsafe_result_id_original = fr.id
        AND fr2.sampled_at IS NOT NULL
        AND fr2.sampled_at <= fr.sampled_at + INTERVAL '7 days'
    )
),
check_7_training_currency AS (
  SELECT
    7 AS check_id,
    'Active employees with no training signed in last 12 months' AS title,
    'hr_employee + ops_training_attendee' AS source,
    COUNT(*)::int AS row_count,
    'Investigate — definition of "mandatory" training pending dev clarification' AS target
  FROM hr_employee e
  WHERE COALESCE(e.is_deleted, false) = false
    AND e.end_date IS NULL
    AND e.start_date IS NOT NULL
    AND e.start_date <= CURRENT_DATE - INTERVAL '30 days'
    AND NOT EXISTS (
      SELECT 1 FROM ops_training_attendee ta
      WHERE COALESCE(ta.is_deleted, false) = false
        AND ta.hr_employee_id = e.id
        AND ta.signed_at >= NOW() - INTERVAL '12 months'
    )
),
check_8_orphan_fulfillments AS (
  SELECT
    8 AS check_id,
    'Sales fulfillments with no pack_lot link (traceability orphans)' AS title,
    'sales_po_fulfillment' AS source,
    COUNT(*)::int AS row_count,
    'Should be 0' AS target
  FROM sales_po_fulfillment f
  WHERE COALESCE(f.is_deleted, false) = false
    AND f.pack_lot_id IS NULL
)
SELECT * FROM check_1_open_overdue_ca
UNION ALL SELECT * FROM check_2_failed_emp_no_retest
UNION ALL SELECT * FROM check_7_training_currency
UNION ALL SELECT * FROM check_8_orphan_fulfillments
ORDER BY check_id;

COMMENT ON VIEW audit_pre_check IS 'PrimusGFS v3.2 audit-readiness counters. Checks 3,4,5,6,9,10 pending schema clarifications (see FS/schema_questions_for_dev.md).';

