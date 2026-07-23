# Current state

The JARVIS Phase 0/1 migration and Phase 2 secretary approval slice are
implemented on `main`.
The original Hermes implementation is preserved on `legacy/hermes-baseline`.

## Verified

- Backend: 32 tests pass, Ruff lint passes, Ruff format check passes.
- Python bytecode compilation passes.
- JARVIS Swift packages resolve.
- JARVIS asset catalog compiles.
- JARVIS simulator build passes with signing disabled.
- `JARVISTests/JARVISApprovalTests` passes both approval transport tests.

## Known limitations

- Physical-device builds require a local Apple development team.
- APNs remains optional and deferred.
- Secretary policy is strict and one-action only: external side effects require
  explicit approval, with durable approval records and mobile decision routes.
- Task/reminder behavior has an in-memory test contract only; no production task
  persistence or scheduler exists yet.
- A real Hermes runtime and named Cloudflare Tunnel still require deployment
  credentials for end-to-end phone smoke testing.
- Compose seeds the upstream profile configuration from
  `backend/deployment/jarvis-profile/config.yaml` into a new Hermes home. An
  existing operator-managed profile is preserved and can be refreshed manually.

## Compatibility

The bundle identifier, Keychain namespace, APNs topic, upstream environment
variables, and WebUI API names remain unchanged for this migration.
