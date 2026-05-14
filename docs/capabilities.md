# Capability Limits

The macOS v1 implementation is deterministic and public-API-only. It does not fake unsupported behavior.

## Implemented Native Paths

- `AXUIElement`: UI traversal, focused element value setting, focused action execution, menu traversal/click where apps expose AX.
- `ScreenCaptureKit`: display/window image capture and direct duration video capture.
- `CGEvent`: click, type, key, hotkey, scroll, drag, move.
- `NSWorkspace` / `NSRunningApplication`: app listing, launch, focus, switch, quit, hide, unhide, relaunch, open URL/file.
- `NSPasteboard`: clipboard get/set/clear.
- Quartz Window Services: window inventory and canonical `windowId` metadata.

## Structured Capability Errors

These are known honest limits in v1:

- `capability_unavailable.space_list`: stable public APIs do not enumerate Spaces.
- `capability_unavailable.space_move`: stable public APIs do not move arbitrary third-party windows to a Space.
- `capability_unavailable.dock_pinned_items_public_api`: stable public APIs do not enumerate Dock pinned items.
- `capability_unavailable.dock_mutation_public_api`: v1 does not change global Dock preferences through private APIs or scripts.
- `capability_unavailable.dock_click_public_api`: arbitrary Dock item clicks are not a stable public API operation.
- `capability_unavailable.overlay_requires_app_runtime`: a persistent overlay requires an app runtime; direct CLI does not fake it.
- `capability_unavailable.bridge_bundle`: the Swift package does not include a signed Bridge app target yet.
- `capability_unavailable.video_background_session`: background video sessions require a daemon/Bridge stream owner; direct mode supports `--duration`.
- `capability_unavailable.file_dialog_specialization`: direct v1 exposes generic AX dialog actions, not a full stable file-dialog model.

## Permission Errors

- `permission_denied.accessibility`
- `permission_denied.screen_recording`
- `permission_denied.input_monitoring`

These are operational states, not internal failures. Grant the relevant macOS permission and retry.

## No AI Runtime

The repository intentionally contains no:

- OpenAI, Anthropic, Gemini, or local-LLM provider code
- agent runtime
- prompt runner
- natural-language task runner
- image-understanding or vision-language feature
- shell execution tool
- remote public listener

Optional OCR is represented in config and defaults off. It is not implemented as a model-provider path.
