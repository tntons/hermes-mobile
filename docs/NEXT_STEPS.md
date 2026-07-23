# Next steps

1. Run the Compose stack against the real Hermes runtime and verify the
   non-destructive `jarvis-profile-init` seed plus the `jarvis`
   profile/personality response end to end.
2. Configure a real named Cloudflare Tunnel and verify the iPhone over HTTPS.
3. Validate the exact Hermes `/api/approval/respond` payload against the real
   runtime and perform a phone approval smoke test over HTTPS.
4. Add Gmail and Google Calendar adapters behind the Phase 2 policy and
   approval interfaces; keep credentials outside the repository.
5. Design durable task/reminder storage and scheduled jobs without changing the
   upstream agent core.
6. Design and test the one-time Keychain migration before changing the bundle
   identifier.
