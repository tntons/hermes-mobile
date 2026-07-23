# Next steps

1. Commit the Phase 0/1 migration on `codex/jarvis-migration` after reviewing
   the diff and checking Docker configuration with `docker compose config`.
2. Run the bridge against a real upstream Hermes runtime and verify the
   `jarvis` profile response end to end.
3. Configure a real named Cloudflare Tunnel and verify the iPhone over HTTPS.
4. Add the secretary workflow layer for Gmail, Calendar, tasks, reminders, and
   scheduled jobs without changing the upstream agent core.
5. Design and test the one-time Keychain migration before changing the bundle
   identifier.
