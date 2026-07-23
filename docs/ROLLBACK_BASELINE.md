# Rollback baseline

Phase 0 preserved the pre-JARVIS product at commit
`5be05e97ee6dc58bbdedfdff3ee35102028fe61a`.

That commit is pinned on both the local and remote branch
`legacy/hermes-baseline`. The migration work was developed on
`codex/jarvis-migration` and merged into `main`; `main` is now the JARVIS
branch.

## Preserved product surface

- iOS project: `ios/Hermes.xcodeproj`
- iOS source root: `ios/Hermes/`
- Bridge package: `backend/hermes_bridge/`
- Upstream-compatible WebUI routes: `/health` and `/api/*`
- Phone authentication: bearer token to the bridge
- Bridge-to-WebUI authentication: `hermes_session` cookie plus
  `X-Hermes-CSRF-Token`
- Bundle/Keychain compatibility identifier: `com.hermes.mobile`

The original Hermes iOS target was rebuilt from this branch with signing
disabled during the Phase 0 audit. The branch remains the recoverable rollback
point until the later API-server replacement passes its full migration suite.

## Safe inspection

```bash
git show legacy/hermes-baseline:ios/Hermes.xcodeproj/project.pbxproj
git diff legacy/hermes-baseline..main --stat
git log --oneline --decorate legacy/hermes-baseline..main
```

Do not delete or rewrite this branch as part of the JARVIS migration.
