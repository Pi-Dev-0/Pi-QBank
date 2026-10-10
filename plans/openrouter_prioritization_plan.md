# Pi-QBank: OpenRouter Prioritization & UI Changes Plan

## Context
Project: Pi-QBank (Flutter). AI functionality lives in:
- [`lib/pages/ai_hub_page.dart`](lib/pages/ai_hub_page.dart) — AI Hub with top tabs: **Pi AI** (built-in), Gemini (web), ChatGPT (web). Accessed via bottom nav "AI" tab (index 4).
- [`lib/pages/ai_page.dart`](lib/pages/ai_page.dart) — built-in AI chat (`AIPage`). Currently defaults `_provider = 'google'` but already supports non-Google providers (OpenAI/OpenRouter format).
- [`lib/pages/ai_model_settings_page.dart`](lib/pages/ai_model_settings_page.dart) — AI settings; provider dropdown order: 1) Google Gemini, 2) OpenRouter, 3) OpenAI Compatible.
- [`lib/config/app_config.dart`](lib/config/app_config.dart) — OpenRouter constants already defined (`openRouterApiKey`, `openRouterBaseUrl`, `openRouterModelId`).
- App drawer → "AI Preferences" → `/ai_settings` (AIModelSettingsPage).

Current OpenRouter support: fully functional in the built-in chat (any non-google provider uses OpenAI-compatible format; `provider == 'openrouter'` adds HTTP-Referer/X-Title headers). **It is NOT prioritized** — it's the 2nd option in settings and not the default.

## Request 1 — "In the ai chat add open router, and prioritize it first" ✅ Clear

**Changes:**
1. [`ai_model_settings_page.dart`](lib/pages/ai_model_settings_page.dart:501) — Reorder the provider dropdown so OpenRouter is FIRST:
   - items: OpenRouter, Google Gemini, OpenAI Compatible
2. Set OpenRouter as the default provider:
   - Initial `_provider` value → `'openrouter'`
   - Dropdown `value` defaults to OpenRouter when no saved preference exists
   - In `onChanged`, OpenRouter selection resets text/image/audio/video models to `AppConfig.openRouterModelId` (already done for google; needs OpenRouter defaults)
3. [`ai_page.dart`](lib/pages/ai_page.dart:54) — default `_provider = 'openrouter'` and default API key fallback order: saved key → OpenRouter key (`AppConfig.openRouterApiKey`) → Gemina key.
4. Verify model fallback list for OpenRouter doesn't shadow its own model (`google/gemini-2.0-flash-001`).

## Request 2 — "the txt ai chat and notif icon from top" ❓ Needs clarification

Interpretations under consideration:
- **(A)** Add an "OpenRouter" tab to the AI Hub top tab bar (already prioritized), plus add a notification icon to the AI page/Hub app bar.
- **(B)** The built-in "text AI chat" (Pi AI tab) and a notification icon should be made visible/accessible "from the top" — e.g., a notification badge/icon in the AI Hub page header.
- **(C)** Move/add the AI chat entry and notification icon to the top of the app drawer (near the DrawerHeader).

**Pending decisions from user:**
1. Should the built-in chat's default provider become OpenRouter (part of #1)?
2. Where exactly should the "notif icon" go — AI page app bar, AI Hub app bar, or elsewhere?
3. What does "txt ai chat from top" refer to — the Pi AI tab, or something else?
4. Should an explicit "OpenRouter" tab be added to the AI Hub top tabs alongside Pi AI / Gemini / ChatGPT?

## Diagram — AI Settings & Chat Data Flow

```mermaid
flowchart LR
    A[App Drawer → AI Preferences] --> B[/ai_settings: AIModelSettingsPage]
    B --> C{Provider dropdown}
    C -->|OpenRouter 1st| D[save: global_ai_provider='openrouter']
    C -->|Google| E[save: global_ai_provider='google']
    B -->|bottom nav AI tab | F[AiHubPage: tabs Pi AI / Gemini / ChatGPT]
    F --> G[AIPage: built-in chat]
    G --> D
    G -->|request| H{provider}
    H -->|google| I[Gemini API]
    H -->|openrouter| J[OpenRouter API]
    H -->|openai| K[OpenAI-compatible API]
```

## Next step
Await user clarification on Request 2 before implementation. Once confirmed, the code mode will:
1. Reorder + default OpenRouter in `ai_model_settings_page.dart`
2. Default to OpenRouter in `ai_page.dart`
3. Implement the clarified "txt ai chat + notif icon" placement
4. Run `flutter analyze` / hot restart to verify
