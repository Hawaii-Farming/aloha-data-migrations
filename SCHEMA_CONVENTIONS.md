# Schema Conventions

These rules apply to every schema change in this project. All contributors must follow them.

---

## 1. Modules

One table defines all modules, their prefixes, file numbering, and doc numbering:

| Prefix    | Module          | Migration range | Doc # |
|-----------|-----------------|-----------------|-------|
| `sys_`    | System          | 001–004 | 01 |
| `org_`    | Org             | 007–014 | 02 |
| `grow_`   | Grow            | 005–006, 015–016, 048–059, 100–107 | 06 |
| `hr_`     | Human Resources | 017–025 | 04 |
| `invnt_`  | Inventory       | 026–033 | 03 |
| `sales_`  | Sales           | 035, 108–113, 115, 117, 136–140 | 08 |
| `ops_`    | Operations      | 034, 036–047, 135 | 05 |
| `pack_`   | Pack            | 114, 116, 118–125 | 07 |
| `maint_`  | Maintenance     | 126–128 | 09 |
| `fsafe_`  | Food Safety     | 129–134 | 10 |
| `fin_`    | Finance         | 20260417000010– | 11 |

Migration ranges are interleaved in some areas due to cross-module FK dependencies (e.g. sales_product at 035 precedes ops tables, pack_lot at 114 precedes sales_po_fulfillment at 117).

---

## 2. Standard Fields

Every table includes these fields. They are omitted from `.md` column tables for brevity and do not receive `COMMENT ON COLUMN` descriptions.

```sql
created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
created_by  TEXT
updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_by  TEXT
is_deleted  BOOLEAN     NOT NULL DEFAULT false
```

- `is_deleted` — soft delete flag. No records are physically deleted. Queries filter on `WHERE is_deleted = false`.
- `created_by` / `updated_by` — Supabase Auth email (TEXT, no FK). These are audit fields, not workflow fields.
- `ON DELETE CASCADE` is never used. All FK constraints use the default `RESTRICT` behavior.

### Workflow fields

Workflow fields capture a named person performing a step in a record's lifecycle. They are distinct from audit fields:

| Type | Column examples | Datatype | FK? | Purpose |
|------|-----------------|----------|-----|---------|
| Workflow | `verified_by`, `reviewed_by`, `requested_by`, `sampled_by`, `ordered_by`, `approved_by`, `qb_uploaded_by`, `assigned_to`, `fixer_id`, `reported_by` | TEXT | FK → `hr_employee(id)` | Identifies a specific employee in a business process |
| Audit | `created_by`, `updated_by` | TEXT | No FK | Logs the Supabase Auth email of who made the change |

Workflow field rules:
- Timestamp always precedes person: `verified_at` before `verified_by`
- Ordered by lifecycle stage: `requested_at/by` → `reviewed_at/by` → `approved_at/by` → `ordered_at/by` → `verified_at/by`
- Use `_at` (TIMESTAMPTZ) when exact time matters; use `_on` (DATE) when only the date matters (e.g. `sampled_on`, `delivered_to_lab_on`)
- Workflow fields sit between business fields and CRUD fields in column order
- They are additional — they do not replace `created_at`/`created_by`

The **only** `auth.users` FK in the project is `hr_employee.user_id UUID REFERENCES auth.users(id)`.

---

## 3. Column Ordering

```
id
org_id
farm_id              (if applicable)
site_id              (if applicable)
... business fields ...
... workflow fields (e.g. requested_at, requested_by, verified_at, verified_by) ...
created_at
created_by
updated_at
updated_by
is_deleted
```

CRUD fields always close the column list in this exact order. Workflow fields sit between business fields and CRUD fields.

**UOM before measurement** — When a UOM column and its associated measurement columns appear together, the UOM column always comes first (e.g. `weight_uom` before `pack_net_weight`, `seeding_uom` before `number_of_units`, `application_uom` before `application_quantity`).

**display_order** — Always placed as the last business field, right before CRUD fields.

---

## 4. Table Design

### Primary keys

- **TEXT PK** — lookup and reference tables where the ID is human-readable and derived from the name field (e.g. `org`, `org_farm`, `org_site`, `hr_employee`, `ops_task`)
- **UUID PK** (`gen_random_uuid()`) — transactional tables where records are created at runtime (e.g. `ops_task_tracker`, `invnt_po`, `maint_request`)

### Data types

- All text fields use **`TEXT`** — no `VARCHAR(n)`. Frontend handles length validation.
- Status and type fields use **`TEXT` with a `CHECK` constraint** — never PostgreSQL `ENUM` types. CHECK constraints can be added or removed in a single transactional migration; ENUM types cannot.

### Multi-tenancy

Every org-scoped table must have:

```sql
org_id TEXT NOT NULL REFERENCES org(id)
```

This column is used for Row Level Security (RLS) filtering.

**farm_id inheritance** — if a parent/header table has `farm_id`, all its child tables must also include `farm_id` with the same nullability. The child's `farm_id` is inherited from the parent at insert time. This ensures every table in a parent-child hierarchy can be independently filtered by farm without joining back to the parent.

---

## 5. Foreign Keys

### Naming

FK columns are named `{referenced_table}_id`:

```
ops_task_id       → ops_task(id)
invnt_vendor_id   → invnt_vendor(id)
sales_customer_id → sales_customer(id)
```

Exceptions:

- **Scoping columns** — `farm_id`, `site_id`, and `equipment_id` keep their short names even though the tables are `org_farm`, `org_site`, and `org_equipment`
- **Workflow fields** — role-based names referencing `hr_employee(id)` (see Section 2)
- **Self-referencing FKs** — use a semantic suffix so the domain prefix is preserved (e.g. `fsafe_result_id_original` in `fsafe_result`, not `original_fsafe_result_id`)
- **Multiple FKs to the same table** — use a semantic suffix (e.g. `site_id_parent` in `org_site`). When a table has only one `site_id`, use `site_id` with a COMMENT ON COLUMN to document which category filter applies
- **Cross-module FKs** — retain the referenced table's prefix (e.g. `ops_corrective_action_taken.fsafe_result_id`)

### Named constraints (required when 2+ FKs point to the same target)

When a table has **two or more foreign keys pointing to the same target table** (including self-references), the FK constraints must be **explicitly named** so PostgREST can disambiguate them in embedded resource selects.

The inline `column TYPE REFERENCES table(id)` shorthand auto-generates names like `tablename_columnname_fkey`. Those work for SQL but PostgREST cannot pick between two of them when you write `requester:hr_employee!fk_xxx(...)`.

**Pattern:** declare the column as a bare type, then add a `CONSTRAINT fk_<table>_<purpose>` clause at the end of the table.

```sql
CREATE TABLE IF NOT EXISTS hr_time_off_request (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          TEXT NOT NULL REFERENCES org(id),

  -- Multiple FKs to hr_employee — declare bare, name explicitly below
  hr_employee_id  TEXT NOT NULL,
  requested_by    TEXT NOT NULL,
  reviewed_by     TEXT,

  -- ... other columns ...

  -- Named FKs so PostgREST can disambiguate when embedding hr_employee
  CONSTRAINT fk_hr_time_off_request_employee
    FOREIGN KEY (hr_employee_id) REFERENCES hr_employee(id),
  CONSTRAINT fk_hr_time_off_request_requested_by
    FOREIGN KEY (requested_by) REFERENCES hr_employee(id),
  CONSTRAINT fk_hr_time_off_request_reviewed_by
    FOREIGN KEY (reviewed_by) REFERENCES hr_employee(id)
);
```

**Naming convention:** `fk_<source_table>_<purpose>`. The purpose is usually the column name minus `_id`, or a meaningful suffix like `employee`, `requested_by`, `team_lead`, `compensation_manager`.

**Single FK to target:** the inline `REFERENCES` shorthand is fine — PostgREST has no ambiguity to resolve.

**Self-referential FKs:** always name them, even when there's only one. PostgREST treats parent and child lookups against the same table as separate operations and needs an explicit constraint name.

**Frontend usage** — once named, configs can embed via:
```ts
select: '*, requester:hr_employee!fk_hr_time_off_request_requested_by(preferred_name)'
```

**Retrofitting an existing hosted table** — write a one-shot patch migration that uses `ALTER TABLE ... DROP CONSTRAINT ... ADD CONSTRAINT ...` wrapped in `pg_constraint` existence checks (idempotent). After applying to hosted, fold the named constraints into the original `CREATE TABLE` migration and mark the patch as reverted in remote history (`supabase migration repair --status reverted <ts>`), then delete the patch file.

---

## 6. Photos & JSONB

Photos are stored as JSONB arrays of URLs when they are simple attachments with no per-photo metadata:

```sql
photos JSONB NOT NULL DEFAULT '[]'
```

When photos require individual metadata (e.g. caption, observation date), use a **separate table** with one row per photo instead (e.g. `pack_shelf_life_photo`).

Never use numbered columns (`photo_01_url`, `photo_02_url`, etc.).

Use JSONB for flexible arrays (photos, enum option lists). Use proper FK columns for anything that is joined, filtered, or used in calculations.

---

## 7. Schema Change Process

Every schema change requires these steps in this order:

1. **Ensure access** to this conventions doc, schema module `.md` files, and a Supabase connection
2. **Update conventions** — if the change introduces a new pattern or modifies an existing rule
3. **Update the module `.md`** — the `.md` is the source of truth for table design
4. **Update the SQL migration** — built from the `.md`
5. **Update `README.md`**

### File naming

All file types use the same `YYYYMMDDHHMMSS` timestamp format for consistent ordering:

**Migration files:**
```
supabase/migrations/YYYYMMDDHHMMSS_tablename.sql
```

**Schema doc files:**
```
docs/schemas/YYYYMMDDHHMMSS_module.md
```

**Process doc files:**
```
docs/processes/YYYYMMDDHHMMSS_workflow_name.md
```

**Migration scripts and process scripts** live in the separate [`aloha-data-migrations`](../aloha-data-migrations) repo. They follow their own conventions documented in `MIGRATION_CONVENTIONS.md` over there. When schema changes here require updates to data import scripts, coordinate the changes across both repos.

The timestamp provides ordering and uniqueness. Each file type shares the same timestamp prefix for related items (e.g. `20260408000001_sys.md`, `20260408000001_sys_uom.sql`).

---

## 8. Documentation

### SQL ↔ MD sync rule

Column descriptions in `.md` docs must **exactly match** the text in `COMMENT ON COLUMN` in the corresponding `.sql` file — word for word. When you update one, update the other in the same change.

### Which columns get descriptions

Add `COMMENT ON COLUMN` and `.md` descriptions for **all non-PK, non-audit fields whose purpose is not obvious from the column name alone**. The fields that do NOT get comments are:

- **PK**: `id`
- **CRUD audit**: `created_at`, `created_by`, `updated_at`, `updated_by`, `is_deleted`
- **Scoping**: `org_id`, `farm_id`
- **Self-descriptive columns**: fields where the name alone makes the purpose clear (e.g. `email`, `phone`, `address`, `name`, `description`, `notes`, `photos`, `caption`)

Everything else — business fields, workflow fields, FK references, status, dates, configuration fields, etc. — gets a comment. When in doubt, add the comment.

### Rich comments for source and calculation

Two types of information **must** be stored as `COMMENT ON COLUMN` in the schema (not in process docs or business rules):

1. **Column source / editability** — Where the data comes from and whether it's user-editable. This tells developers and AI how to populate the field.
   ```sql
   COMMENT ON COLUMN invnt_po.item_name IS 'Snapshot from invnt_item.name at order time; manually entered for non-inventory items';
   COMMENT ON COLUMN invnt_onhand.invnt_lot_id IS 'Sourced from invnt_lot at stock-in time';
   COMMENT ON COLUMN sales_product_price.farm_id IS 'Inherited from parent sales_product';
   ```

2. **Column calculation method** — How a computed or auto-populated value is derived.
   ```sql
   COMMENT ON COLUMN grow_harvest_weight.net_weight IS 'Auto-calculated: gross_weight - (grow_harvest_container.tare_weight × number_of_containers)';
   COMMENT ON COLUMN grow_monitoring_result.is_out_of_range IS 'Auto-set by comparing reading against grow_monitoring_metric min/max values';
   ```

These comments stay in the schema because they are read directly from PostgreSQL catalog when building frontend forms, APIs, and AI-assisted development.

### Schema doc format

Each `.md` doc must include:

1. A module title and one-paragraph description
2. A standard audit field note at the top referencing the fields in Section 2
3. A Mermaid ERD — relationships only, no entity attribute blocks. Unquoted, lowercase labels with underscores. Every referenced core entity must appear with its full ownership chain (if `org_farm` appears, include `org ||--o{ org_farm : operates`; if `org_site` appears, include `org_farm ||--o{ org_site : contains`)
4. A table overview section
5. A section per table with:
   - One-paragraph description
   - A column table: `| Column | Type | Constraints | Description |`
   - No bold section header rows inside the column table
