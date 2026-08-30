with values_by_dimension as (
  select 'body_location'::text as dimension,
    body_location_label as label,
    count(*)::bigint as row_count
  from analysis.urc_2025_26_injury_successor_rows_v1
  group by body_location_label
  union all
  select 'injury_type'::text,
    injury_type_label,
    count(*)::bigint
  from analysis.urc_2025_26_injury_successor_rows_v1
  group by injury_type_label
), mapped as (
  select source.dimension, source.label, source.row_count,
    controlled.code,
    controlled.label as controlled_label
  from values_by_dimension source
  left join lateral (
    select code, label
    from curated.code_lists
    where list_name = source.dimension
      and active
      and (
        lower(code) = lower(source.label)
        or lower(label) = lower(source.label)
      )
    order by code
    limit 1
  ) controlled on true
)
select jsonb_build_object(
  'source_rows', (
    select count(*)
    from analysis.urc_2025_26_injury_successor_rows_v1
  ),
  'dimensions', (
    select jsonb_object_agg(dimension, result order by dimension)
    from (
      select dimension, jsonb_build_object(
        'distinct_labels', count(*),
        'mapped_labels', count(*) filter (where code is not null),
        'mapped_rows', coalesce(sum(row_count) filter (where code is not null), 0),
        'unmapped_rows', coalesce(sum(row_count) filter (where code is null), 0),
        'unmapped', coalesce(jsonb_agg(jsonb_build_object(
          'label', label,
          'rows', row_count
        ) order by row_count desc, label) filter (where code is null), '[]'::jsonb)
      ) as result
      from mapped
      group by dimension
    ) grouped
  )
);

with values_by_dimension as (
  select 'body_location'::text as dimension, body_location_label as label
  from analysis.urc_2025_26_injury_successor_rows_v1
  group by body_location_label
  union all
  select 'injury_type'::text, injury_type_label
  from analysis.urc_2025_26_injury_successor_rows_v1
  group by injury_type_label
), mapped as (
  select source.dimension, source.label,
    coalesce(controlled.code, 'unknown') as corrected_code
  from values_by_dimension source
  left join lateral (
    select code
    from curated.code_lists
    where list_name = source.dimension
      and active
      and (
        lower(code) = lower(source.label)
        or lower(label) = lower(source.label)
      )
    order by code
    limit 1
  ) controlled on true
)
select coalesce(jsonb_agg(jsonb_build_object(
  'dimension', dimension,
  'corrected_code', corrected_code,
  'labels', labels
) order by dimension, corrected_code), '[]'::jsonb) as mapping_collisions
from (
  select dimension, corrected_code, jsonb_agg(label order by label) as labels
  from mapped
  group by dimension, corrected_code
  having count(*) > 1
) collisions;
