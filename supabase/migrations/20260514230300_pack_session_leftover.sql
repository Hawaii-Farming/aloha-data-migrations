-- pack_session_leftover: end-of-session leftover pounds by variety (Bal box).
-- One row per (session, variety). Captured when last product run is stopped.

CREATE TABLE IF NOT EXISTS pack_session_leftover (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL,
    pack_session_id     UUID NOT NULL REFERENCES pack_session(id) ON DELETE CASCADE,
    pack_variety_id     TEXT NOT NULL,
    leftover_pounds     NUMERIC NOT NULL DEFAULT 0,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT pack_session_leftover_farm_fkey    FOREIGN KEY (org_id, farm_id)         REFERENCES org_farm(org_id, id),
    CONSTRAINT pack_session_leftover_variety_fkey FOREIGN KEY (org_id, pack_variety_id) REFERENCES pack_variety(org_id, id),
    CONSTRAINT uq_pack_session_leftover UNIQUE (pack_session_id, pack_variety_id)
);

COMMENT ON TABLE pack_session_leftover IS 'End-of-session leftover weight by variety (Bal box). One row per (session, variety).';

CREATE INDEX idx_pack_session_leftover_session ON pack_session_leftover (pack_session_id);
