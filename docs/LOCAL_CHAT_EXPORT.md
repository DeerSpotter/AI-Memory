# Local ChatGPT Export

## Goal

Save the currently open ChatGPT conversation without asking the user to manually write, summarize, paste, or tag context.

The intended flow is:

```text
User opens a ChatGPT conversation
  -> taps Save Context in the ChatGPT tab overlay
  -> app extracts the rendered conversation from the WKWebView
  -> app saves Markdown and PDF locally
  -> app opens the iOS share sheet for the generated files
```

## Why this method

The implementation follows the browser exporter pattern used by ChatGPT conversation exporters:

```text
current ChatGPT page DOM
  -> JavaScript extraction engine
  -> Markdown conversation document
  -> printable PDF representation
```

That maps better to the iOS WebView app than the earlier manual Supabase memory entry flow because the user does not need to retype or summarize the active chat.

## Runtime behavior

The Save Context button is placed in the ChatGPT tab overlay, to the left of the Stop button.

When tapped, the app:

1. Runs a local JavaScript extractor through `WKWebView.evaluateJavaScript`.
2. Searches the active page for ChatGPT message containers, preferring `data-message-author-role` and conversation turn selectors.
3. Preserves sender labels as `You` and `ChatGPT`.
4. Converts common rendered content into Markdown friendly text:
   - code blocks
   - CodeMirror code lines
   - tables
   - links
   - basic image, video, audio, and canvas placeholders
5. Writes a Markdown file.
6. Renders the same Markdown into a local PDF file.
7. Opens the iOS share sheet with both generated files.

## Output location

Files are stored in the app container under:

```text
Documents/ChatGPT Context Exports/<conversation title>/
```

Each export uses the current timestamp and conversation title:

```text
yyyyMMdd_HHmmss_<conversation title>.md
yyyyMMdd_HHmmss_<conversation title>.pdf
```

## Privacy and security boundary

This feature is local first.

It does not:

- send the conversation to Supabase
- send the conversation to a third party service
- require a Supabase project
- require an OpenAI API key
- use ChatGPT session tokens directly
- call private ChatGPT backend APIs
- ask the user to type manual memory text

The extractor reads only what the loaded ChatGPT page exposes to the app's own `WKWebView` session.

## Known limits

This is a WebView DOM export. It can break if ChatGPT changes its page structure.

The export is expected to work best when the user has opened the target conversation and the conversation content is rendered in the page. If ChatGPT starts virtualizing older turns or unloading hidden content, a future pass should add a scroll and capture routine or move to an API owned chat tab where the app owns the full message history directly.

PDF output is generated from the Markdown export. The Markdown file should be treated as the source of truth for future context import because it is easier for another chat or local memory system to parse.

## Next pass

A future local memory pass should add an in app index screen for saved exports:

```text
Saved Contexts
  -> conversation title
  -> export timestamp
  -> Markdown file
  -> PDF file
  -> Start New Chat With This Context
```

That should stay local unless the user explicitly chooses to move a saved export into Supabase, cloud storage, or another memory backend.
