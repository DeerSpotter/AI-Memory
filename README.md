# ContextPort

**Take your context with you.**

ContextPort is an iOS app for carrying conversation context between ChatGPT, Claude, Gemini, Grok, and DeepSeek. Each provider and login profile keeps its own isolated WebView session while all providers can use the same device local Memory vault.

```text
ChatGPT / Claude / Gemini / Grok / DeepSeek
        ↓
Save Context
        ↓
ContextPort Memory
        ↓
Share Context with another provider or the current conversation
        ↓
Continue with the same history
```

The AI can change. Your context does not have to.

## Latest release: ContextPort 2.10.4 (Build 83)

ContextPort 2.10.4 improves ChatGPT Work sessions and long conversations.

- Restores reliable vertical scrolling in long ChatGPT chats.
- Prevents the entire page from dragging like one large image.
- Locks horizontal movement to stop sideways drift and flickering.
- Adds a recovery prompt when a ChatGPT Work session remains stuck while loading.
- Reloads the current session without clearing login cookies or ContextPort Memory.
- Removes the ChatGPT message windowing behavior that conflicted with the current ChatGPT layout.
- Makes long ChatGPT conversations feel noticeably snappier and more responsive.

## What ContextPort does

ContextPort keeps a simple AI and Memory workflow:

- Select an AI provider and login profile.
- Continue using the provider inside its isolated WebView session.
- Save a verified conversation as Markdown and PDF.
- Create a new Memory or add the conversation as a revision to an existing Memory.
- Share one or more Memories with a new AI conversation or the conversation already open.
- Attach prepared context files or paste compiled Markdown directly into the provider composer.

## Supported AI providers

- ChatGPT
- Claude
- Gemini
- Grok
- DeepSeek

Each provider supports separate Current User, Guest, and saved login profiles. Provider sessions, cookies, browser state, and authentication flows remain isolated from one another.

## Memory and revision history

A Memory is a long lived context record. Each additional saved conversation can become a new revision without overwriting previous history.

```text
Memory
├── Revision 1
├── Revision 2
├── Revision 3
└── Revision N
```

Memory capabilities include:

- Save as a new Memory with a custom name.
- Use the detected provider chat title as the default name.
- Add a revision to the Memory that launched the current conversation.
- Choose any existing Memory as the revision destination.
- Preserve every revision as separate Markdown and PDF files.
- View revision history, metadata, PDF, and Markdown.
- Export one revision, selected Memories, or the complete Memory vault.
- Import ContextPort Memory ZIP archives and merge by stable Memory and revision identifiers.
- Skip exact duplicate revisions while preserving divergent revision histories.
- Keep Memory content device local.

## Share Context

A saved Memory can be shared in two ways:

### Start with another AI

Select ChatGPT, Claude, Gemini, Grok, or DeepSeek. ContextPort prepares the complete selected Memory and revision history, switches to the destination provider, and stages the context for the new conversation.

### Share with the current conversation

Select `Current Conversation` to remain in the provider and chat already open. ContextPort does not reset the conversation. It stages the selected Memory for `Paste Context` or `Attach Files` in place.

Large attachments are streamed into the WebView in bounded chunks rather than being converted into one large retained base64 payload. Unsupported provider file types are skipped instead of leaving the Attach Files action permanently active.

## Conversation capture integrity

ContextPort uses provider aware extraction rules rather than guessing message roles by position.

- ChatGPT captures the active conversation branch and excludes inactive alternate responses.
- Claude uses explicit standard chat user and assistant renderer evidence.
- Gemini and Grok require explicit provider role markers.
- DeepSeek uses verified virtual conversation row and assistant content boundaries.
- Cloudflare and security challenge content is rejected.
- A save requires positive evidence for at least one user turn and one assistant turn.
- Unsafe provider UI drift blocks Memory creation instead of storing corrupted page content.
- Provider drift alerts can direct the user to Developer Sources capture for diagnosis.

ChatGPT saved conversation recovery can use authenticated conversation transport to recover older turns that are no longer present in the rendered DOM. Claude and DeepSeek include provider specific formatting handling so paragraphs, headings, lists, tables, code, links, and emphasis remain readable in exported Markdown.

## Performance

ContextPort includes several bounded performance systems:

### Chat and Work session responsiveness

- ChatGPT Work session load watchdog and recovery prompt.
- Reliable vertical scrolling for current ChatGPT layouts.
- Horizontal movement lock to prevent flicker.
- Faster and snappier long ChatGPT conversation interaction.
- Latest Exchange Only mode for supported providers when the user wants only the newest user and assistant exchange visible.
- Optional ChatGPT Mobile Fallback experiment.

The older ChatGPT DOM message windowing path is disabled for current ChatGPT pages because it conflicted with the provider's present scroll architecture.

### Memory bundle performance

- Deterministic SHA-256 cache for compiled context bundles.
- Reuse of unchanged Markdown, PDF, and composer context.
- Streamed Markdown compilation in bounded chunks.
- Page at a time PDF compilation through Core Graphics.
- Background Memory preparation away from the main UI actor.
- Lazy PDF and Markdown revision previews.
- Bounded cache pruning by working set count and total size.

## Developer Mode

Developer Mode provides two separate capture workflows.

### Static Sources

The Static workflow inventories and reconciles loaded provider source material.

- Browser observed scripts, stylesheets, modules, workers, and source-like resources.
- Combined inline JavaScript export instead of exposing internal chunk reads.
- Bounded second-pass bundler dependency reconciliation.
- One additional strict nested dependency pass.
- Webpack and Rspack runtime asset resolution.
- Explicit indexed text, metadata only binary, and load error states.
- SourceMap candidate discovery, validation, and embedded original source recovery.
- Separate Step 4A discovery, Step 4B validation, and Step 4C original source decoding.
- Preservation of successes and failures in the final saved evidence set.
- Deterministic source fingerprints so an unchanged capture refreshes the existing Memory attachment instead of creating duplicates.

### Live Interceptor

The Live workflow captures bounded WebView traffic only after the user starts it.

It records retained evidence for:

- `fetch`
- `XMLHttpRequest`
- WebSocket
- EventSource
- `navigator.sendBeacon`
- Performance resource completion
- Current document navigation

The Live Interceptor uses bounded queues, preview limits, and retained history limits. Cookies, authorization headers, and complete headers are not collected. Every retained event can be saved to Memory as an individual JSON file with a manifest, capture summary, and readable archive description.

While a Live capture archive is being packaged, the Memory tab shows a red save progress notice and prevents conflicting Memory operations until the write completes.

## Feature summary

- Five native AI providers.
- Provider scoped Current User, Guest, and saved login profiles.
- Independent WebView sessions and persistent browser recovery.
- Shared device local Memory.
- Custom Memory naming.
- Full Memory revision history.
- Markdown and PDF conversation export.
- Context sharing to a new provider or the current conversation.
- Large file attachment streaming.
- Provider aware fail closed conversation validation.
- Provider UI drift detection.
- DeepSeek Save Context with block aware Markdown formatting.
- ChatGPT active branch and older message recovery.
- Memory ZIP export, selected export, revision export, and import.
- Cached and streamed Memory bundle compilation.
- Static Developer Sources capture.
- SourceMap recovery and original source extraction.
- Bounded Live Interceptor capture.
- Visible Memory save progress for large Live archives.
- Dark mode, mic input, refresh, and stop controls.
- TrollStore, manual, and Xcode installation support.

## Multi AI session model

```text
Shared device local Memory
  -> Provider
      -> Profile
          -> WebView Session
```

Provider identity and account identity are separate. Session and browser recovery storage is namespaced as:

```text
<provider>::<profile>
```

Examples:

```text
chatgpt::primary
claude::primary
gemini::guest
grok::<saved-profile>
deepseek::primary
```

This prevents sessions from colliding on shared profile IDs such as `primary` and `guest`.

See `docs/MULTI_AI_ARCHITECTURE.md` for architecture and migration details.

## Release IPA build provenance

The IPA files attached to this repository's GitHub Releases come from successful GitHub Actions workflow builds.

**GitHub Actions is the build origin. GitHub Releases is the distribution location.**

The primary source controlled workflow is:

- `.github/workflows/build-source-ios16-ipa.yml`
- Workflow name: `Build ContextPort Source iOS 16 IPA`

The workflow:

1. Checks out the repository source.
2. Reports the Xcode version used by the GitHub hosted macOS runner.
3. Installs XcodeGen when required.
4. Generates `ChatGPTWebView.xcodeproj` from `project.yml`.
5. Archives ContextPort in Release configuration for a generic iOS device.
6. Builds with code signing disabled.
7. Packages the archived app as `ContextPort-source-ios16-unsigned.ipa`.
8. Uploads the IPA as a GitHub Actions artifact.

```text
Source merged into main
  -> GitHub Actions workflow runs
  -> ContextPort IPA build completes
  -> unsigned IPA is uploaded as an artifact
  -> workflow produced IPA is attached to the GitHub Release
  -> users download ContextPort from Releases
```

The repository also contains the `Build ContextPort Unsigned IPA` workflow. Release assets should remain traceable to a successful Actions build rather than a separate untracked local build.

The workflows intentionally disable code signing. Release IPA files require a compatible signing or sideloading method.

## Update checks

ContextPort can check the public GitHub `releases/latest` endpoint and compare the published version with the version embedded in the installed IPA.

Update checks are best effort and never block startup. `Check for updates on start` can be disabled in Settings.

## Source controlled app

The current source layout retains the established internal paths:

- `ChatGPTWebView/`
- `AppMemory/`
- `project.yml`

Those names remain for build and upgrade compatibility. The installed product name is ContextPort.

## Support development

ContextPort is actively developed and maintained as an open source project.

[https://buymeacoffee.com/spotterdeer](https://buymeacoffee.com/spotterdeer)

Support helps fund provider compatibility testing, iOS maintenance, Memory workflows, source diagnostics, and continued development.

## Build requirements

- Xcode 14+
- iOS 16+
- Swift 5.0+

## Installation

1. Open the project in Xcode.
2. Choose a device or simulator.
3. Run the app.

Unsigned release IPA files require a compatible signing or sideloading method.

## License

MIT
