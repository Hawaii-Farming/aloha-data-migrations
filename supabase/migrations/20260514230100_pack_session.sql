-- pack_session: pack-day header. One row per (org, farm, pack_date).
-- Owns the hourly crew grid (via pack_productivity_hour) and the per-product timelines (via pack_session_product_run).

CREATE TABLE IF NOT EXISTS pack_session (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL,
    site_id             TEXT,

    pack_date           DATE NOT NULL,
    started_at          TIMESTAMPTZ,
    stopped_at          TIMESTAMPTZ,

    is_completed        BOOLEAN NOT NULL DEFAULT false,
    verified_at         TIMESTAMPTZ,
    verified_by         TEXT,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT pack_session_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id),
    CONSTRAINT uq_pack_session UNIQUE (org_id, farm_id, pack_date)
);

COMMENT ON TABLE pack_session IS 'Pack day header. One row per (org, farm, pack_date). started_at = first product run start; stopped_at = last product run stop. is_completed flips when user closes the session.';
COMMENT ON COLUMN pack_session.pack_date IS 'Editable; user can backdate to log prior days.';
COMMENT ON COLUMN pack_session.started_at IS 'Auto-set to first pack_session_product_run.started_at.';
COMMENT ON COLUMN pack_session.stopped_at IS 'Auto-set when last pack_session_product_run is stopped.';

CREATE INDEX idx_pack_session_org_id    ON pack_session (org_id);
CREATE INDEX idx_pack_session_farm_id   ON pack_session (farm_id);
CREATE INDEX idx_pack_session_pack_date ON pack_session (pack_date);
