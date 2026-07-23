# JARVIS design system

JARVIS uses a conversation-first visual language with quiet dark surfaces,
clear streaming states, and a restrained green assistant accent.

## Principles

- JARVIS is calm, useful, and operational.
- Conversation, tools, approvals, and streaming state are first-class.
- Keep the interface low-chrome and readable on a phone.
- Use green for JARVIS actions and healthy status, not for every icon.
- Show confirmation before external secretary actions in future phases.

## Tokens

| Token | Value |
|---|---|
| Background | `rgb(32, 32, 32)` |
| Surface | `rgb(46, 46, 46)` |
| Elevated surface | `rgb(60, 60, 60)` |
| JARVIS accent | `rgb(107, 209, 153)` |
| Primary text | White at 94% |
| Secondary text | White at 64% |
| Tertiary text | White at 42% |

The current Swift implementation is in `ios/JARVIS/JarvisApp.swift` as
`JarvisTheme`. The app icon uses the same graphite and green palette.
