## What changed

Describe the change.

## Why

Explain the user problem and why this approach is appropriate.

## Reproduction and verification

- Reproduction test name:
- Red evidence before the fix:
- Green evidence after the fix:
- Other checks run:

## Checklist

- [ ] I added a reproduction test for each bug fix and recorded red-to-green evidence, or this is not a bug fix.
- [ ] I regenerated fixtures with `zig build export-fixtures` and `app/scripts/sync-fixtures.sh --sync`, or this change does not affect fixtures.
- [ ] I did not edit generated fixtures by hand.
- [ ] I added no comments to code, scripts, or workflow YAML.
- [ ] I described whether user-facing wording changed; any changed wording comes from `core/src/strings.zig`.

## User-facing wording

State what changed, or write “No user-facing wording changes.”
