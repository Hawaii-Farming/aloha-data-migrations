-- One-off cleanup: soft-delete every pack-* row created by
-- jean.ricaume@gmail.com on aloha-dev so the new event-marker bucket
-- logic can be tested from scratch.
--
-- All operations are soft deletes (is_deleted = true) — recoverable by
-- flipping the flag back to false if needed. Run order is leaf-first so
-- audit trails stay sensible even if a step partial-fails.

DO $$
DECLARE
    v_audit_user TEXT := 'jean.ricaume@gmail.com';
    v_now        TIMESTAMPTZ := NOW();
BEGIN
    -- ── Pack session subtree ─────────────────────────────────────
    UPDATE pack_session_leftover
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE pack_session_id IN (
               SELECT id FROM pack_session WHERE created_by = v_audit_user
           );

    UPDATE pack_session_product_hour
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE pack_productivity_hour_id IN (
               SELECT ph.id
                 FROM pack_productivity_hour ph
                 JOIN pack_session ps ON ps.id = ph.pack_session_id
                WHERE ps.created_by = v_audit_user
           );

    UPDATE pack_productivity_hour_fail
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE pack_productivity_hour_id IN (
               SELECT ph.id
                 FROM pack_productivity_hour ph
                 JOIN pack_session ps ON ps.id = ph.pack_session_id
                WHERE ps.created_by = v_audit_user
           );

    UPDATE pack_productivity_hour
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE pack_session_id IN (
               SELECT id FROM pack_session WHERE created_by = v_audit_user
           );

    UPDATE pack_session_product_run
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE pack_session_id IN (
               SELECT id FROM pack_session WHERE created_by = v_audit_user
           );

    UPDATE pack_session
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE created_by = v_audit_user;

    -- ── Pack lot subtree ─────────────────────────────────────────
    UPDATE pack_lot_item
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE pack_lot_id IN (
               SELECT id FROM pack_lot WHERE created_by = v_audit_user
           );

    UPDATE pack_lot
       SET is_deleted = true, updated_by = v_audit_user, updated_at = v_now
     WHERE created_by = v_audit_user;
END $$;
