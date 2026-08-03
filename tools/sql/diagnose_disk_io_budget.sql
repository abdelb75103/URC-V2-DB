with database_stats as (
  select stats_reset, temp_files, temp_bytes,
    blks_read, blks_hit,
    round(100 * blks_hit::numeric / nullif(blks_hit + blks_read, 0), 4)
      as database_cache_hit_percent
  from pg_stat_database
  where datname = current_database()
), relation_cache as (
  select round(100 * sum(heap_blks_hit)::numeric /
    nullif(sum(heap_blks_hit + heap_blks_read), 0), 4)
      as table_cache_hit_percent,
    round(100 * sum(idx_blks_hit)::numeric /
    nullif(sum(idx_blks_hit + idx_blks_read), 0), 4)
      as index_cache_hit_percent
  from pg_statio_user_tables
), largest_relations as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'relation', relation,
    'total_bytes', total_bytes
  ) order by total_bytes desc), '[]'::jsonb) as rows
  from (
    select schemaname || '.' || relname as relation,
      pg_total_relation_size(relid) as total_bytes
    from pg_catalog.pg_statio_user_tables
    order by pg_total_relation_size(relid) desc
    limit 10
  ) ranked
), dashboard_statements as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'queryid', queryid,
    'calls', calls,
    'total_exec_time_ms', round(total_exec_time::numeric, 3),
    'shared_blks_read', shared_blks_read,
    'shared_blks_hit', shared_blks_hit,
    'temp_blks_read', temp_blks_read,
    'temp_blks_written', temp_blks_written
  ) order by calls desc), '[]'::jsonb) as rows
  from pg_stat_statements
  where query ilike '%latest_team_dashboard_v5%'
     or query ilike '%latest_league_dashboard_v5%'
)
select jsonb_build_object(
  'captured_at', clock_timestamp(),
  'database_bytes', pg_database_size(current_database()),
  'stats_reset', database_stats.stats_reset,
  'temp_files', database_stats.temp_files,
  'temp_bytes', database_stats.temp_bytes,
  'database_cache_hit_percent', database_stats.database_cache_hit_percent,
  'table_cache_hit_percent', relation_cache.table_cache_hit_percent,
  'index_cache_hit_percent', relation_cache.index_cache_hit_percent,
  'blocks_read', database_stats.blks_read,
  'blocks_hit', database_stats.blks_hit,
  'largest_relations', largest_relations.rows,
  'dashboard_statements', dashboard_statements.rows
) as disk_io_diagnostic
from database_stats
cross join relation_cache
cross join largest_relations
cross join dashboard_statements;
