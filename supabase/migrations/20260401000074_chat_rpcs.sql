CREATE OR REPLACE FUNCTION public.chat_schema()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(t ORDER BY t->>'table'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'table', c.relname,
      'kind', CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'view' ELSE 'table' END,
      'columns', (
        SELECT jsonb_agg(jsonb_build_object('name', a.attname, 'type', format_type(a.atttypid, a.atttypmod)) ORDER BY a.attnum)
        FROM pg_attribute a
        WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      )
    ) AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r','v','m')
      AND c.relname NOT LIKE 'hr\_%'
      AND c.relname NOT LIKE 'app\_hr\_%'
  ) sub;
$$;

CREATE OR REPLACE FUNCTION public.chat_query(q text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  result jsonb;
  q_low  text := lower(q);
  q_trim text := regexp_replace(q, ';\s*$', '');
BEGIN
  IF q_low !~ '^\s*(select|with)\s' THEN
    RAISE EXCEPTION 'Only SELECT/WITH queries are allowed';
  END IF;
  IF q_low ~ '\y(insert|update|delete|drop|alter|create|truncate|grant|revoke|comment|copy|vacuum|analyze|reindex|cluster|listen|notify|do|call|set|reset|begin|commit|rollback|savepoint|lock)\y' THEN
    RAISE EXCEPTION 'Write/DDL keywords are not permitted';
  END IF;
  IF q_low ~ '\y(hr_|app_hr_)' THEN
    RAISE EXCEPTION 'Restricted tables (hr_*) are not accessible';
  END IF;
  IF regexp_replace(q_trim, ';\s*$', '') ~ ';\s*\S' THEN
    RAISE EXCEPTION 'Multiple statements are not allowed';
  END IF;

  PERFORM set_config('statement_timeout', '20000', true);
  PERFORM set_config('transaction_read_only', 'on', true);

  EXECUTE format('SELECT COALESCE(jsonb_agg(row_to_json(t)), ''[]''::jsonb) FROM (%s) t', q_trim) INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_schema() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_query(text) TO anon, authenticated;
