# Contributing

Thanks for helping improve QuickText! Bug reports, ideas and pull requests are all welcome.

## Getting started

You need macOS 14 or later and Xcode 16 (or just the Command Line Tools). No account or API key is needed to build or test.

```bash
swift test
```

```bash
swift run
```

`swift run` starts the app from the build folder; `scripts/build-app.sh --install` builds a real `.app` and installs it.

## Pull requests

- Keep each pull request focused on one change, and describe what it fixes or adds.
- Add or update tests for behavior you change. The tests must not need the network or a real provider: use `FakeCLI`, `StubServer` and `FakeBackend` from `Tests/QuickTextTests/Support`.
- Match the surrounding code: small types, clear names, and comments that explain *why* rather than *what*.
- The project must keep building with only the Command Line Tools installed, so avoid Swift macros that ship only with Xcode (such as SwiftUI's `@State` and `#Preview`).
- Make sure `swift test` passes and the build has no warnings.

## Adding a provider

1. Add a case to `Provider` in `Sources/QuickText/LLM/Provider.swift`, with its default model and effort levels.
2. Implement `LLMBackend` for it in `Sources/QuickText/LLM/Backends/`.
3. Return it from `ProviderBackend.backend(for:)`, and add any fields it needs to `SettingsView`.

## Reporting bugs

Open an issue with your macOS version, the provider you use, what you did, and what happened. Error messages from the result card help a lot. Please don't paste API keys or private text.
