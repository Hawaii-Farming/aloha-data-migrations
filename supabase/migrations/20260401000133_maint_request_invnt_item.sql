CREATE TABLE IF NOT EXISTS maint_request_invnt_item (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT        NOT NULL REFERENCES org(id),
    farm_name             TEXT        REFERENCES org_farm(name),
    maint_request_id    UUID        NOT NULL REFERENCES maint_request(id),
    invnt_item_name       TEXT        NOT NULL REFERENCES invnt_item(name),
    uom                 TEXT REFERENCES sys_uom(code),
    quantity_used       NUMERIC,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT uq_maint_request_invnt_item UNIQUE (maint_request_id, invnt_item_name)
);

COMMENT ON TABLE maint_request_invnt_item IS 'Inventory items consumed during a maintenance request. One row per item per request.';

CREATE INDEX idx_maint_request_invnt_item_request ON maint_request_invnt_item (maint_request_id);
CREATE INDEX idx_maint_request_invnt_item_item    ON maint_request_invnt_item (invnt_item_name);

