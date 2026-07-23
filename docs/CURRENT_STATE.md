# Current state

The JARVIS Phase 0/1 migration is implemented on `codex/jarvis-migration`.
The original Hermes implementation is preserved on `legacy/hermes-baseline`.

## Verified

- Backend: 9 tests pass, Ruff lint passes, Ruff format check passes.
- Python bytecode compilation passes.
- JARVIS Swift packages resolve.
- JARVIS asset catalog compiles.
- JARVIS simulator build passes with signing disabled.

## Known limitations

- Physical-device builds require a local Apple development team.
- The existing iOS scheme has no unit-test target.
- APNs remains optional and deferred.
- The upstream profile configuration must be present in the deployed Hermes
  runtime for the `jarvis` profile persona to take effect.

## Compatibility

The bundle identifier, Keychain namespace, APNs topic, upstream environment
variables, and WebUI API names remain unchanged for this migration.
