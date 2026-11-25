# PocketAI (JJS)

PocketAI is a personal iOS 17+ SwiftUI app for local GGUF text models. It uses the community `SwiftLlama` SPM wrapper over llama.cpp and the wrapper's Apple XCFramework, which includes Metal support on supported devices.

## Build

Generate the app icon and Xcode project, resolve SPM, and build an unsigned device app:

```sh
swift Scripts/generate_app_icon.swift
xcodegen generate --spec project.yml --project PocketAI.xcodeproj
xcodebuild -resolvePackageDependencies -project PocketAI.xcodeproj -scheme PocketAI
xcodebuild -project PocketAI.xcodeproj -scheme PocketAI -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Codemagic runs the same steps and packages `artifacts/PocketAI-unsigned.ipa`. An unsigned IPA is a build artifact, not an app that iOS installs without a signing step. A sideloading tool must sign it for the target device; installation method and free-account limits depend on device/iOS version and the sideloading tool.

## MVP included

- Local GGUF import into `Documents/Models` and download catalog with progress and storage check.
- Single-model llama.cpp inference with Metal enabled by default, streaming output, stop support and a conservative memory preflight.
- SwiftData conversation/message persistence, configurable system prompt, temperature, Top-P and context/GPU settings.
- Native Markdown formatting for prose and fenced code blocks with a copy control.
- Local TXT/PDF document import and simple lexical retrieval for document-grounded prompts.
- Navy JJS icon: black star, white JJS lettering.

## Known limitations

- The pinned public SwiftLlama API uses llama.cpp default model parameters (`use_mmap` is enabled in the pinned implementation) but does not expose every native load/sampling parameter. Mirostat, Min-P, arbitrary GPU layer count and guaranteed mmap forcing need wrapper/API work.
- The current `SwiftLlama` public service does not provide the app-level mmproj/Vision loading pipeline or LoRA adapter attachment required for vision and LoRA features; those remain out of this MVP.
- Downloads run while the app is active. Background URLSession transfer/relaunch restoration is not configured.
- Tokens-per-second in the UI is estimated from UTF-8 output length; exact token metrics require the wrapper to expose generation token counts.
- This repository was updated through GitHub file APIs, not built on a macOS/Xcode runner in this session. The Codemagic workflow remains the required compile validation.
