-- pack_session_product_run: one product timeline within a session.
-- Multiple runs per session, one per (product, harvest_date).
-- Same product with two harvest dates → two runs → two pack_lots.
-- pack_lot_id is auto-populated by trigger (see 20260514230800).

CREATE TABLE IF NOT EXISTS pack_session_product_run (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL,
    pack_session_id     UUID NOT NULL REFERENCES pack_session(id) ON DELETE CASCADE,
    sales_product_id    TEXT NOT NULL REFERENCES sales_product(id),
    pack_lot_id         UUID REFERENCES pack_lot(id),
    harvest_date        DATE NOT NULL,

    started_at          TIMESTAMPTZ NOT NULL,
    stopped_at          TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT pack_session_product_run_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id),
    CONSTRAINT uq_pack_session_product_run UNIQUE (pack_session_id, sales_product_id, harvest_date)
);

COMMENT ON TABLE pack_session_product_run IS 'Product timeline within a pack session. One row per (session, product, harvest_date). Per-hour cases are written to pack_session_product_hour. pack_lot_id is auto-set by trigger.';

CREATE INDEX idx_pack_session_product_run_session ON pack_session_product_run (pack_session_id);
CREATE INDEX idx_pack_session_product_run_lot     ON pack_session_product_run (pack_lot_id);
CREATE INDEX idx_pack_session_product_run_product ON pack_session_product_run (sales_product_id);
