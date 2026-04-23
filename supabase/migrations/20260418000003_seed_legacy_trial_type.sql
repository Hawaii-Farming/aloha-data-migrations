-- Re-seed the 'legacy_trial' grow_trial_type row that retired migration 024
-- used to create every night via `ensure_trial_type()`. Cuke seeding trial
-- blocks (13 historical rows in grow_C_seeding) link to this via
-- grow_cuke_seed_batch.grow_trial_type_id, so migration 025 can tell
-- which harvests are trials.
--
-- With 024 retired and grow_trial_type now excluded from
-- _clear_transactional.py, this row is static reference data that needs
-- to exist once and survive.

insert into public.grow_trial_type (id, org_id, farm_id, name, description, created_by, updated_by)
values (
  'legacy_trial',
  'hawaii_farming',
  'cuke',
  'Legacy Trial',
  'Generic trial type used to flag historical trial seedings migrated from the legacy grow_C_seeding sheet',
  'data@hawaiifarming.com',
  'data@hawaiifarming.com'
)
on conflict (id) do nothing;
