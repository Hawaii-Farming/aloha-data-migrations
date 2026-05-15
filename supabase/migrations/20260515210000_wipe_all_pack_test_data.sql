-- Full wipe of pack test data on aloha-dev + diagnostic probe surfacing
-- the audit_user value that crud-action.server.ts writes to created_by
-- for jean.ricaume@gmail.com.
--
-- audit_user resolves to hr_employee.company_email (falling back to
-- hr_employee.id). Probe RAISES the values via NOTICE so the migration
-- output shows what's actually being stored.
--
-- Wipe is unfiltered (every pack_session + children on dev) because the
-- previous targeted cleanup keyed on the wrong identifier. All ops are
-- soft deletes — recoverable by flipping is_deleted back to false.

DO $$
DECLARE
    v_audit_users TEXT[];
    v_session_n   INT;
BEGIN
    -- ── Probe: surface audit_user for the requesting user ───────
    SELECT ARRAY_AGG(DISTINCT COALESCE(he.company_email, he.id))
      INTO v_audit_users
      FROM hr_employee he
      JOIN auth.users u ON u.id = he.user_id
     WHERE u.email = 'jean.ricaume@gmail.com';

    RAISE NOTICE 'audit_user candidates for jean.ricaume@gmail.com: %',
      v_audit_users;

    SELECT COUNT(*) INTO v_session_n
      FROM pack_session
     WHERE created_by = ANY(COALESCE(v_audit_users, ARRAY[]::TEXT[]));
    RAISE NOTICE 'pack_session rows matching that audit_user (informational): %',
      v_session_n;

    -- ── Wipe: every active pack_session + children on this DB ───
    UPDATE pack_session_leftover
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_session_product_hour
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_productivity_hour_fail
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_productivity_hour
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_session_product_run
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_session
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_lot_item
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    UPDATE pack_lot
       SET is_deleted = true, updated_at = NOW()
     WHERE is_deleted = false;

    RAISE NOTICE 'Pack data wipe complete.';
END $$;
