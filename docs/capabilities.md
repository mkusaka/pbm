# Capability Limits

The macOS v1 implementation is deterministic and public-API-only. It does not fake unsupported behavior.

## Implemented Native Paths

- `AXUIElement`: UI traversal, focused element value setting, focused action execution, menu traversal/click where apps expose AX.
- `ScreenCaptureKit`: display/window image capture and direct duration video capture.
- `CGEvent`: click, type, key, hotkey, scroll, drag, move.
- `NSWorkspace` / `NSRunningApplication`: app listing, launch, focus, switch, quit, hide, unhide, relaunch, open URL/file.
- `NSPasteboard`: clipboard get/set/clear.
- Quartz Window Services: window inventory and canonical `windowId` metadata.

## Deterministic Hardening Ported From Peekaboo Review

- AX snapshots use bounded traversal with max depth, max element count, per-node child caps, visited-element tracking, deadline checks, and bulk attribute reads where `AXUIElementCopyMultipleAttributeValues` is available.
- AX children include public alternate child attributes such as visible children, web area children, navigation children, layout/group contents, rows, columns, tabs, `AXWindows`, and the focused element.
- Target resolution prefers explicit IDs and exact matches before fuzzy matches, and returns structured `target_ambiguous`, `target_not_found`, `stale_snapshot`, or `invalid_argument.conflicting_target` errors.
- Screen Recording status combines CoreGraphics preflight with a ScreenCaptureKit shareable-content probe for CLI reliability.
- Window inventory records renderability metadata and default window selection scores usable layer-0 visible windows above utility entries.
- Input move/drag paths are deterministic linear paths; no randomized humanization or agent planning is used.
- Clipboard operations support typed NSPasteboard data, Base64 export, file import/export, and size guards.
- Capture output paths expand directory-like paths, add required extensions, and report scale/coordinate metadata.

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
