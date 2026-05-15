-- pack_session_product_hour: per-product per-hour cases-packed cell.
-- One row per (hour-row, product-run). Composes the bottom-of-page hour grid.

CREATE TABLE IF NOT EXISTS pack_session_product_hour (
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                          TEXT NOT NULL REFERENCES org(id),
    farm_id                         TEXT NOT NULL,
    pack_productivity_hour_id       UUID NOT NULL REFERENCES pack_productivity_hour(id) ON DELETE CASCADE,
    pack_session_product_run_id     UUID NOT NULL REFERENCES pack_session_product_run(id) ON DELETE CASCADE,
    cases_packed                    INTEGER NOT NULL DEFAULT 0,

    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                      BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT pack_session_product_hour_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id),
    CONSTRAINT uq_pack_session_product_hour UNIQUE (pack_productivity_hour_id, pack_session_product_run_id)
);

COMMENT ON TABLE pack_session_product_hour IS 'Per-product per-hour cases-packed delta. cases_packed is the count for THIS hour, not cumulative.';

CREATE INDEX idx_pack_session_product_hour_hour ON pack_session_product_hour (pack_productivity_hour_id);
CREATE INDEX idx_pack_session_product_hour_run  ON pack_session_product_hour (pack_session_product_run_id);
