select jsonb_build_object(
  'rule_version', comparison ->> 'rule_version',
  'training_concussion_2025-26', (
    select (item ->> 'time_loss_injuries')::integer
    from jsonb_array_elements(comparison -> 'diagnoses') setting
    cross join lateral jsonb_array_elements(setting -> 'current') item
    where setting ->> 'setting' = 'training'
      and item ->> 'diagnosis' = 'Concussion'
  )
) as league_comparison_verification
from reporting.latest_league_season_comparison_v5;
