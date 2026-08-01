# Golden Vehicles

## Purpose

Launch hardening requires data-quality sign-off against a deliberately difficult golden vehicle set. These vehicles are chosen to break naive assumptions: each one exercises a resolver state, a data edge, or a unit boundary that a comfortable "popular sedan" sample would never hit. The golden set is a standing fixture for catalog release gates, resolver tests, forecast tests, and UI-state review — a catalog release or resolver change that regresses a golden vehicle fails its gate.

## Selection criteria

Populate the set so that every one of these categories has at least one vehicle:

- **Battery-electric vehicles** — must resolve `not_applicable` and show "engine oil service not applicable"; the app must never invent an oil plan for them.
- **Oil-life-monitor / condition-based maintenance vehicles** — the sourced OLM rule must surface the prominent monitor instruction, label any app date as an estimate, and defer to the vehicle indicator on disagreement.
- **Severe-service variants** — vehicles whose normal and severe schedules differ, proving the operating-condition selection and the severe-service questionnaire path.
- **Unknown-configuration fallbacks** — selections where the exact engine/configuration qualifier cannot be proven, forcing the `partial` resolver state and the confirm/manual-enter path instead of a guess.
- **Unit-conversion edge cases** — vehicles/records that stress the integer-base-unit mileage rule and miles/kilometres switching without precision loss.

Where source conflicts are found during M03, add at least one vehicle that exercises the `conflict` state (sources disagree; no automatic product recommendation; both facts retained for review), and one honest `unsupported` selection.

## Golden vehicle set

To be populated in M03 (catalog build and data-quality work, DOS-M03-010) and M07 (data-quality sign-off). Every row must cite a source register entry; no invented vehicles or facts.

| Vehicle | Why difficult | Expected resolver state | Source |
| --- | --- | --- | --- |
| _pending M03/M07_ | | | |
