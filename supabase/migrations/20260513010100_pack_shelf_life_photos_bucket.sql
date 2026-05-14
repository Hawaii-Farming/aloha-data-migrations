-- Storage bucket for Shelf Life photos
-- ======================================
-- Public bucket so photo_url can be served directly. Writes are gated
-- by RLS using the first path segment (= org_id) — every upload must
-- be prefixed `<org_id>/<pack_shelf_life_id>/...` so cross-org access
-- is blocked at the Storage layer.

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'shelf-life-photos',
  'shelf-life-photos',
  true,
  10485760,                                       -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
ON CONFLICT (id) DO UPDATE
   SET public             = EXCLUDED.public,
       file_size_limit    = EXCLUDED.file_size_limit,
       allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Drop existing policies in case re-run
DROP POLICY IF EXISTS "shelf_life_photos_read"   ON storage.objects;
DROP POLICY IF EXISTS "shelf_life_photos_insert" ON storage.objects;
DROP POLICY IF EXISTS "shelf_life_photos_update" ON storage.objects;
DROP POLICY IF EXISTS "shelf_life_photos_delete" ON storage.objects;

CREATE POLICY "shelf_life_photos_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'shelf-life-photos'
    AND (storage.foldername(name))[1] IN (SELECT public.get_user_org_ids())
  );

CREATE POLICY "shelf_life_photos_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'shelf-life-photos'
    AND (storage.foldername(name))[1] IN (SELECT public.get_user_org_ids())
  );

CREATE POLICY "shelf_life_photos_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'shelf-life-photos'
    AND (storage.foldername(name))[1] IN (SELECT public.get_user_org_ids())
  )
  WITH CHECK (
    bucket_id = 'shelf-life-photos'
    AND (storage.foldername(name))[1] IN (SELECT public.get_user_org_ids())
  );

CREATE POLICY "shelf_life_photos_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'shelf-life-photos'
    AND (storage.foldername(name))[1] IN (SELECT public.get_user_org_ids())
  );

COMMIT;
