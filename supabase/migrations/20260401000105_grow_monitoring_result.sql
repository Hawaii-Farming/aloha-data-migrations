CREATE TABLE IF NOT EXISTS grow_monitoring_result (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_name                     TEXT NOT NULL REFERENCES org_farm(name),
    site_id                     TEXT NOT NULL REFERENCES org_site(id),
    ops_task_tracker_id         UUID NOT NULL REFERENCES ops_task_tracker(id),
    grow_monitoring_metric_id    TEXT NOT NULL REFERENCES grow_monitoring_metric(id),
    monitoring_station          TEXT,
    reading                     NUMERIC,
    reading_boolean             BOOLEAN,
    reading_enum                TEXT,
    is_out_of_range             BOOLEAN NOT NULL DEFAULT false,
    corrective_action           TEXT,
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_monitoring_result UNIQUE (ops_task_tracker_id, grow_monitoring_metric_id, monitoring_station)
);

COMMENT ON TABLE grow_monitoring_result IS 'Individual measurement recorded during a monitoring event. One row per point per station. Calculated points store the computed result for historical record.';

COMMENT ON COLUMN grow_monitoring_result.reading_enum IS 'Selected from grow_monitoring_metric.enum_options when response_type is enum';
COMMENT ON COLUMN grow_monitoring_result.is_out_of_range IS 'Auto-set by comparing reading against grow_monitoring_metric min/max values or enum_pass_options';
COMMENT ON COLUMN grow_monitoring_result.corrective_action IS 'Pre-filled from grow_monitoring_metric.corrective_actions when is_out_of_range is true; editable';
COMMENT ON COLUMN grow_monitoring_result.reading IS 'Auto-calculated from grow_monitoring_metric.formula when point_type is calculated';

CREATE INDEX idx_grow_monitoring_result_tracker ON grow_monitoring_result (ops_task_tracker_id);
CREATE INDEX idx_grow_monitoring_result_site ON grow_monitoring_result (site_id);
CREATE INDEX idx_grow_monitoring_result_point ON grow_monitoring_result (grow_monitoring_metric_id);
