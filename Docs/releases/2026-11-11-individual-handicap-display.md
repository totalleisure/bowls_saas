# Individual competition handicap display — 11 November 2026

Handicap competitions using `team_difference` display each player's individual value next to the name, in saved playing order, plus the entry's combined handicap. The Entries and Draw tabs, competition match/result screens, booking player section and all competition draw PDF layouts share these labels. Known matchups show calculated starting scores on draw and match cards. Unresolved opponents do not get invented starting scores. Missing individual values are labelled `not set`; signed and zero values remain visible.

The repository reads existing individual handicap/member-name columns only for this rule mode. Stored entry names, member names, draw positions and score calculations are unchanged. Ordinary competitions keep their existing labels. This amendment does not change scorecard snapshot data or previously saved offline scorecards.

Validation: 36 focused Flutter tests pass, covering individual signed values, missing values, preserved partner order, PDF labels, legacy display, Admin editing, booking, player result submission and existing print workflows. Shared Dart sources compared before promotion: identical apart from documented environment-specific files. No SQL changes, no database deployment, no publication or emails. No store package uploaded.
