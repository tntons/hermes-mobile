# Decisions

## JARVIS owns the product layer

Branding, mobile UI, bridge metadata, permissions, and future secretary
workflows belong to JARVIS. Hermes Agent source is not forked or rewritten.

## Preserve upstream identifiers

`WEBUI_*`, `HERMES_WEBUI_PASSWORD`, `MOBILE_TOKEN`, `HERMES_HOME`,
`hermes_session`, and `/api/*` names remain because the upstream runtime
depends on them.

## Persona uses the upstream profile mechanism

The bridge selects the `jarvis` profile and personality when no explicit
values are provided. It persists the personality through the upstream
`/api/personality/set` route. The actual system instructions live in the
tracked `backend/deployment/jarvis-profile/config.yaml` template, not in user
messages and not in a fork of the Hermes Agent source.

## Bundle and Keychain migration is deferred

The app remains `com.hermes.mobile` during development. A later release step
will migrate Keychain values before changing the bundle identifier.

## Native message list remains in use

The iOS app uses its native `LazyVStack` message list. ExyteChat is not part of
the dependency graph.
