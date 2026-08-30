with cohort as (
  select master.team_key, master.row_values, master.final_classification,
    master.time_loss_days, master.clinical_duration_days
  from lineage.injury_master_rows_v3 master
  join lineage.injury_inclusion_rows_v3 inclusion
    on inclusion.version_id = master.version_id
   and inclusion.source_row = master.source_row
  where master.version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
    and inclusion.dashboard_eligible
), fields(field_name) as (values
  ('Occasion category'::text),
  ('Match Type'::text),
  ('Body Part'::text),
  ('Injury Tissue Type/s'::text),
  ('Is Contact'::text),
  ('Specific Diagnosis'::text),
  ('Diagnosis'::text)
), inventories as (
  select fields.field_name,
    coalesce(nullif(trim(cohort.row_values ->> fields.field_name), ''), '<blank>') as value,
    count(*) as row_count
  from cohort
  cross join fields
  group by fields.field_name,
    coalesce(nullif(trim(cohort.row_values ->> fields.field_name), ''), '<blank>')
)
select jsonb_build_object(
  'team_counts', (
    select jsonb_object_agg(team_key, row_count order by team_key)
    from (
      select team_key, count(*) as row_count from cohort group by team_key
    ) counts
  ),
  'classification_counts', (
    select jsonb_object_agg(final_classification, row_count order by final_classification)
    from (
      select final_classification, count(*) as row_count
      from cohort group by final_classification
    ) counts
  ),
  'known_duration_time_loss', (
    select count(*) from cohort
    where final_classification = 'Time Loss' and time_loss_days is not null
  ),
  'days_lost', (
    select coalesce(sum(time_loss_days), 0) from cohort
    where final_classification = 'Time Loss'
  ),
  'date_formats', (
    select jsonb_object_agg(format_name, row_count order by format_name)
    from (
      select case
        when coalesce(trim(row_values ->> 'Date Injured'), '') = '' then 'blank'
        when trim(row_values ->> 'Date Injured') ~ '^\d{2}/\d{2}/\d{4}$' then 'dd/mm/yyyy'
        when trim(row_values ->> 'Date Injured') ~ '^\d{4}-\d{2}-\d{2}$' then 'yyyy-mm-dd'
        else 'other'
      end as format_name, count(*) as row_count
      from cohort group by 1
    ) formats
  ),
  'inventories', (
    select jsonb_object_agg(field_name, values order by field_name)
    from (
      select field_name,
        jsonb_agg(jsonb_build_object('value', value, 'rows', row_count)
          order by row_count desc, value) as values
      from inventories
      group by field_name
    ) grouped
  )
);
