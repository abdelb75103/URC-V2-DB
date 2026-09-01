select jsonb_build_object(
  'team_key', team_key,
  'rule_version', comparison ->> 'rule_version',
  'has_training_diagnoses', exists (
    select 1
    from jsonb_array_elements(comparison -> 'diagnoses') setting
    where setting ->> 'setting' = 'training'
  )
) as team_comparison_verification
from reporting.latest_team_season_comparison_v5
where team_key = 'benetton';
