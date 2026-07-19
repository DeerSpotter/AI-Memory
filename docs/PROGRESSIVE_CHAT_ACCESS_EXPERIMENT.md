# Progressive Chat Access Experiment

## Purpose

A long ChatGPT Work conversation can display useful content before the entire page, composer, connectors, and remaining application state finish initializing. ContextPort should prioritize immediate human access to the content that already exists instead of treating complete page readiness as a prerequisite for reading and scrolling.

This experiment separates two different controls that were previously easy to confuse:

1. **Access buckets** control how long ContextPort continues attempting to recover a usable vertical scroll container while ChatGPT is still loading and replacing its document structure.
2. **Render buckets** control how many already loaded conversation messages remain visible in the DOM. Each render bucket represents five visible messages.

Neither setting directly changes the private RAM ceiling that iOS assigns to a WebKit content process.

## Phase 1: Access First

When a ChatGPT WebView attaches to the screen, ContextPort immediately enables native touch and vertical scrolling. It does not wait for navigation completion, the composer, Work controls, connector initialization, or a recognized conversation-turn marker.

The recovery code searches for the best visible scrollable container and applies vertical scrolling behavior while preserving the current page and login state.

The default six access buckets reproduce the successful ContextPort 2.10.4 build 83 schedule:

| Bucket | Recovery time |
|---:|---:|
| 1 | 0.25 seconds |
| 2 | 0.75 seconds |
| 3 | 2 seconds |
| 4 | 5 seconds |
| 5 | 10 seconds |
| 6 | 16 seconds |

Additional experimental buckets extend recovery through 24, 32, 45, 60, 90, and 120 seconds. A newer settings change invalidates older scheduled attempts so multiple configurations do not continue competing.

## Render buckets

Long-chat optimization already hides older rendered message elements without deleting the conversation or removing those messages from Save Context. The experiment presents the visible-message limit as buckets:

- 1 render bucket = 5 visible messages
- 5 render buckets = 25 visible messages
- 10 render buckets = 50 visible messages
- 20 render buckets = 100 visible messages

Progressive access no longer destroys the long-chat performance manager. Access buckets and render buckets can therefore be tested independently.

## Device controls

The branch adds an iOS Settings bundle. On the test device, open:

**Settings → ContextPort**

The available controls are:

- Enable Access First
- Access Buckets: 1 through 12
- Optimize Long Chats
- Visible Render Buckets: 1 through 20

Change one value at a time, fully close ContextPort, reopen the same Work chat, and record the results.

## Recommended measurements

For each configuration record:

- time when conversation text first becomes visible
- time when the first user scroll succeeds
- time when the newest message becomes visible
- time when the active assistant response becomes visible
- time when the composer becomes interactive
- whether the page refreshes, becomes blank, or the WebContent process terminates
- total time before the chat becomes fully usable

The most important metric is **time to first usable chat access**, not only time to complete page loading.

## Save Context observation

Physical testing has shown that pressing Save Context while the assistant is processing can briefly cause the newest message to materialize and become visible. This suggests that the authenticated conversation extraction path or the DOM activity it triggers changes what ChatGPT has materialized near the active branch.

This PR does not claim that Save Context adds RAM. The behavior should be measured separately because it may reveal a reliable way to request or preserve the active conversation branch without waiting for full UI hydration.

## Parallel child WebViews

Creating hidden child `WKWebView` instances is not included in Phase 1.

WebKit may assign separate WebContent processes to multiple web views until an implementation-defined process limit is reached, but the app cannot require a specific process count or memory allocation. Multiple `WKProcessPool` instances no longer force separate processes. A child WebView would also duplicate ChatGPT JavaScript, layout, network traffic, and memory. Its DOM cannot be donated to the visible WebView.

A future parallel-loader experiment would require instrumentation and strict limits. It should begin with one optional child, prove that a distinct WebContent process is actually used, measure total memory and termination frequency, and demonstrate a transferable result before more children are considered.

## Acceptance criteria

Phase 1 is successful when:

1. Visible chat content can be scrolled while ChatGPT still reports loading.
2. The user can select access and render bucket counts without rebuilding the app.
3. Access recovery does not destroy or override render-window settings.
4. Horizontal page movement remains locked.
5. The default six access buckets preserve the known build 83 behavior.
6. Device tests produce enough evidence to identify the best configuration and distinguish UI refreshes from WebContent process termination.
