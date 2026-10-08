# Dice interface guide

Dice is a compact image surface, with native blur, quiet typography and small controls. The image takes priority; settings and batch management appear only when requested. The default window is 620 × 460 points and can resize down to 520 × 420.

## Typography

Use the macOS system font (SF Pro) for interface text, and the system monospaced font (SF Mono) for dimensions, tag values and page numbers. The SwiftUI definitions in `Sources/Dice/Style.swift` are the source of truth.

| Role | Size / weight | Use |
|---|---|---|
| Title | 16 pt semibold | Larger section titles when needed |
| Heading | 14 pt semibold | Settings headings |
| Body | 13 pt regular | Main instructions and general text |
| Label | 12 pt medium | Section names, filenames and tag names |
| Caption | 11 pt regular | Groups, supporting text and summaries |
| Data | 11 pt monospaced | Dimensions and metadata values |
| Control | 14 pt medium | Toolbar symbols |
| Page | 12 pt medium monospaced | Current page / batch count |

Avoid one-off font sizes in new UI. Text follows system light/dark appearance and accessibility contrast. Font hierarchy conveys importance without adding uppercase labels or decorative headings.

## Colour and material

- Primary and secondary system text colours carry content and supporting details.
- Accent orange is approximately `#F5591A`; reserve it for Start/Apply and selected-state emphasis.
- The window uses native HUD material with behind-window blur.
- Toolbar and pager use ultra-thin material, a capsule shape and a subtle 0.5 pt edge.
- Errors use the system red; disabled controls use native disabled appearance.

## Layout and interaction

Use a 4-point spacing grid: 4, 8, 12, 16, 20, 24. Shared edge inset is 16 pt. Toolbar symbol targets are 30 × 30 pt; root corners are 14 pt. Keep the top-left traffic-light area clear. Native close is available; minimize and fullscreen are disabled.

The top-right toolbar carries Add, Metadata, Settings, Save and Start. The bottom-right pager stays present in image, metadata and batch views. Its middle number opens the searchable batch list. Metadata and the batch list replace the image inside the same window, with a Back control; they never open another dashboard.

Use restrained transitions and honour Reduce Motion. Avoid idle animation. Search is local and matches filename/path, image properties, tag names/values and recognised text. Removing a batch entry never deletes the original file.
