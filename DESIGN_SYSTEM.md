# Hermes design system

Hermes uses a conversation-first visual language inspired by the calm, low-chrome layout of modern AI chat clients. It is intentionally not a brand copy: Hermes keeps its green accent and treats conversations, tools, and streaming state as first-class product information.

## Principles

- Conversation is the primary surface. Avoid decorative cards around ordinary assistant text.
- Use one neutral canvas and a small number of elevation steps. Borders are subtle separators, not containers everywhere.
- Keep the primary action close to the keyboard: the composer is a floating control, not a full-width toolbar.
- Use green for Hermes actions and status, not for every icon or label.
- Prefer semantic hierarchy over large headings: screen title, row title, body, metadata.

## Tokens

| Token | Value / intent |
| --- | --- |
| Canvas | `#202020` dark neutral |
| Surface | `#2E2E2E` control and secondary surface |
| Elevated surface | `#3C3C3C` menus, expanded tool content |
| Primary text | white at 94% |
| Secondary text | white at 64% |
| Tertiary text | white at 42% |
| Accent | Hermes green `rgb(107, 209, 153)` |
| Spacing | 4 / 8 / 12 / 16 / 20 / 24 / 32pt |
| Radius | 8pt small, 14pt controls, 18pt cards, capsule pills |

## Screen patterns

- **Chats:** compact inline title, quiet list rows, simple leading icon, model and message count as metadata, no oversized filled icon tiles.
- **Conversation:** assistant responses sit directly on the canvas; user messages use a restrained trailing bubble; reasoning and tools use lightweight disclosure rows.
- **Composer:** rounded surface with a clear text field and high-contrast send/stop affordance.
- **Settings / onboarding:** native grouped controls, short sections, one primary action per screen.
