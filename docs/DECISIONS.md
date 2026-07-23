# Decisions

## JARVIS owns the product layer

Branding, mobile UI, bridge metadata, permissions, and future secretary
workflows belong to JARVIS. Hermes Agent source is not forked or rewritten.

## Preserve upstream identifiers

`WEBUI_*`, `HERMES_WEBUI_PASSWORD`, `MOBILE_TOKEN`, `HERMES_HOME`,
`hermes_session`, and `/api/*` names remain because the upstream runtime
depends on them.

## Persona uses the upstream profile mechanism

The bridge selects the `jarvis` profile when no explicit profile is provided.
It does not inject text into user messages or invent a new system-message
format.

## Bundle and Keychain migration is deferred

The app remains `com.hermes.mobile` during development. A later release step
will migrate Keychain values before changing the bundle identifier.

## Native message list remains in use

The iOS app uses its native `LazyVStack` message list. ExyteChat is not part of
the dependency graph.
