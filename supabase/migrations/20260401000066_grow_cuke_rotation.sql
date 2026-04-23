-- Canonical cuke seeding rotation. 12 rows, one per rotation slot.
-- Replaces the hardcoded SIM_ORDER array in dash/plant-map/index.html and
-- removes the need for the forward-seeding builder to hold the rotation in
-- memory.
--
-- HK pair (Hamakua + Kohala) rotates together as ONE slot (site_id='hk').
-- The plant-map UI distinguishes Hamakua vs Kohala via org_site_cuke_gh_block.name.
--
-- Exactly one row must have is_anchor=true; anchor_week_start defines the
-- calendar date when that slot is in its seeding week. All other slots are
-- derived from this anchor + slot_num offset.

create table if not exists public.grow_cuke_rotation (
  id                 uuid primary key default gen_random_uuid(),
  org_id             text not null,
  farm_id            text not null,
  slot_num           integer not null check (slot_num between 1 and 12),
  site_id            text not null references public.org_site(id),
  is_anchor          boolean not null default false,
  anchor_week_start  date,
  notes              text,
  created_at         timestamptz not null default now(),
  created_by         text,
  updated_at         timestamptz not null default now(),
  updated_by         text,
  is_deleted         boolean not null default false,
  unique (org_id, farm_id, slot_num),
  check ((is_anchor = true and anchor_week_start is not null) or
         (is_anchor = false and anchor_week_start is null))
);

-- Only one anchor per org/farm.
create unique index if not exists grow_cuke_rotation_one_anchor
  on public.grow_cuke_rotation (org_id, farm_id)
  where is_anchor = true;

comment on table public.grow_cuke_rotation is
  'Cuke seeding rotation slots. 12 rows, one per 12-week cycle position. Anchor row carries the calendar date for its seeding week; all other slots are derived.';
