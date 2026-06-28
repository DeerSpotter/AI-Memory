# Phase 2A: Supabase Memory UI

## Goal

Make the iOS app talk to the deployed Supabase memory backend.

Phase 2A adds a source controlled SwiftUI app with:

- trusted ChatGPT WebView tab
- Supabase Auth screen
- Keychain backed session storage
- Memory Test screen
- project create/list flow
- memory save/search flow
- unsigned IPA build from repository source

## What this proves

This phase proves that the app can authenticate to Supabase, call the JWT protected `memory` Edge Function, and write/search durable project memory.

## What this does not do yet

- It does not replace ChatGPT with an OpenAI API based chat shell.
- It does not let ChatGPT web automatically read Supabase memory.
- It does not inject JavaScript into `chatgpt.com`.
- It does not include any Supabase secret or service role key.

## App structure

```text
ChatGPTWebView/
  App/
  Auth/
  Memory/
  Web/
  Resources/

AppMemory/
  MemoryModels.swift
  SupabaseMemoryClient.swift
```

## Runtime flow

```text
User opens Memory tab
  -> signs in with Supabase Auth
  -> token is stored in iOS Keychain
  -> app calls /functions/v1/memory with Authorization: Bearer <user JWT>
  -> Supabase RLS scopes rows to owner_id
```

## Build artifact

The Phase 2A build workflow uploads:

`ChatGPT-WebView-phase2-ios16-unsigned-ipa`

## Security notes

The app includes only the Supabase project URL and publishable key. Supabase publishable keys are public client keys. They do not replace user authentication and do not bypass Row Level Security.

The user access token is stored in the iOS Keychain.
