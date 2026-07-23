# JARVIS upstream profile

The bridge defaults new mobile sessions to the upstream profile `jarvis` and
the upstream personality `jarvis`. Install the tracked configuration into the
Hermes home used by `jarvis-agent` before deploying the stack:

```bash
mkdir -p "$HERMES_HOME/profiles/jarvis"
cp backend/deployment/jarvis-profile/config.yaml \
  "$HERMES_HOME/profiles/jarvis/config.yaml"
```

If `HERMES_HOME` is not set, use the directory mounted as `/.hermes` in
`backend/docker-compose.yml`. Keep provider credentials, memory settings, and
tool configuration in that operator-managed runtime directory; this template
contains only the JARVIS persona.

The mobile bridge applies the personality through the upstream
`/api/personality/set` endpoint when creating a session and before starting a
turn. This keeps the iOS app independent of upstream personality-management
details while preserving explicit profile/personality overrides for operators.
