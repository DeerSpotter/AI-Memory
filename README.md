# ChatGPT WebView for iOS 16

A lightweight iOS WebView wrapper for ChatGPT’s web app. Built with Swift and WKWebView, optimized for fast performance and speech-to-text microphone support on iOS 16.

## Current trust position

This fork is being converted into a trusted, source controlled build path. The upstream release IPA should not be treated as trusted unless that exact IPA is separately inspected.

## Release IPA build provenance

The IPA files attached to this repository's GitHub Releases come from successful GitHub Actions workflow builds.

**GitHub Actions is the build origin. GitHub Releases is the distribution location.**

The Release page does not compile the app. The project release process takes the unsigned IPA produced by the repository workflow in Actions and attaches that workflow output to the corresponding GitHub Release.

The primary source controlled IPA workflow is:

- `.github/workflows/build-source-ios16-ipa.yml`
- Workflow name: `Build Source iOS 16 IPA`

That workflow:

1. Checks out the repository source.
2. Shows the Xcode version used by the GitHub hosted macOS runner.
3. Installs XcodeGen when required.
4. Generates `ChatGPTWebView.xcodeproj` from `project.yml`.
5. Archives the app in Release configuration for a generic iOS device.
6. Builds with code signing disabled.
7. Packages the archived `.app` inside a `Payload` folder as an unsigned `.ipa`.
8. Uploads the IPA as a GitHub Actions workflow artifact.

The repository also contains the `Build Unsigned IPA` workflow. That workflow independently detects an available Xcode project or workspace and shared scheme, archives the app without signing, packages the result as an unsigned IPA, and uploads its own Actions artifact.

The expected release path is:

```text
Source merged into main
  -> GitHub Actions workflow runs
  -> IPA build completes successfully
  -> unsigned IPA is uploaded as a workflow artifact
  -> that workflow produced IPA is attached to the GitHub Release
  -> users download the IPA from Releases
```

This means release IPA assets are expected to be traceable back to a successful build in the repository's Actions history rather than a separate local developer build.

The workflows intentionally set code signing to disabled. Release IPA files produced by these workflows are unsigned and require a compatible install, signing, or sideloading method.

GitHub Actions artifacts are configured with a 14 day retention period. Publishing the workflow produced IPA as a GitHub Release asset provides the longer lived download location for a released version.

## Current app direction

The app is now focused on two tabs:

- `ChatGPT`
- `Memory`

The `Save Context` button in the ChatGPT tab extracts the current ChatGPT conversation from the rendered page, creates both Markdown and PDF, and stores both inside the app Memory vault under the chat title.

The Memory tab is intentionally simple. It shows saved chat names only. Tap a name to open the saved chat memory, view the PDF, view the Markdown, or start a new chat from that saved memory. Swipe left on a saved chat name to delete it.

## Features

- Persistent ChatGPT WebView login
- Safari 16+ User-Agent spoofing
- Mic input support
- Dark mode support
- ChatGPT stop and refresh controls
- Save Context button near the ChatGPT controls
- Full rendered-chat extraction into Markdown
- PDF rendering from the exported Markdown
- App Memory tab with saved chat names
- Saved chat detail screen with PDF and Markdown
- Swipe left deletion for saved chats
- TrollStore compatibility
- Manual or Xcode install

## Memory behavior

```text
ChatGPT tab
  -> Save Context
  -> extract visible conversation DOM
  -> write PDF and Markdown into app Memory
  -> Memory tab shows the saved chat title
  -> tap title to open PDF and Markdown
  -> Start New Chat opens ChatGPT for continuation
```

The app does not require Supabase for this flow. Supabase and database experiments may remain in the repository for reference, but they are not part of the active two-tab user experience.

## Source controlled app

The app source lives under:

- `ChatGPTWebView/`
- `AppMemory/`
- `project.yml`

The source controlled build workflow generates the Xcode project from `project.yml`, archives the app without code signing, packages the app as an unsigned IPA, and uploads the result as a GitHub Actions artifact.

For published versions, the IPA attached to the GitHub Release is taken from the successful Actions workflow output for that release source revision.

## Build Requirements

- Xcode 14+
- Target iOS 15-16
- Swift 5.0+

## Installation

1. Open this project in Xcode
2. Choose your device or simulator
3. Hit “Run” to build

## License

MIT
