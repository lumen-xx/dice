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
| Metadata name | 12 pt regular | Flat metadata rows |
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
- Drag-over illuminates the entire window edge with a soft mint, cyan and violet aurora. Motion runs only during an accepted drag hover and stops with Reduce Motion enabled.

## Layout and interaction

Use a 4-point spacing grid: 4, 8, 12, 16, 20, 24. Shared edge inset is 16 pt. Toolbar symbol targets are 30 × 30 pt; root corners are 14 pt. The top-left close button matches the capsule material and dimensions of the top-right toolbar. There is no native title bar or traffic-light strip; the image surface and drag glow cover the entire window. Minimize and fullscreen are disabled.

The top-right toolbar carries Add, Metadata, Settings and Start. Start saves copies automatically. The bottom-right pager stays present in image, metadata and batch views. Its middle number opens the searchable batch list. Metadata and the batch list replace the image inside the same window, with a Back control; they never open another dashboard.

Use restrained transitions and honour Reduce Motion. Avoid idle animation. Search is local and matches filename/path, image properties, tag names/values and recognised text. Removing a batch entry never deletes the original file.

Launching from Finder or Applications reveals the drop surface. Only an explicit Choose images or Add action opens the file picker; opening image files imports them directly.

The metadata view uses an unboxed navigation header and flat name/value rows. Show each group name once as a quiet section label. Search has a single subtle background; the group filter stays neutral. Select a row to reveal its full, selectable value in place. Avoid table chrome and alternating filled rows.

Search begins 12 points below the navigation header. The shared footer aligns image counts or resolution/format/size on the left with paging on the right. Metadata rows have a trailing copy-value button with a 30-point target.

Settings is a view inside the same window, opened with the sliders or Command-comma. Its Back action returns to the image. Window edges use directional resize cursors, with diagonal corners. Paging reuses bounded decoded previews; metadata comes from the session cache.

App Settings share the editor surface and use Export defaults, Image settings and Updates sections. Folder and format defaults each have an explicit enable switch; update checks are opt-in. Scroll settings inside the window, keeping Back and the close control visible.

App settings (Command-comma) contain only export defaults and updates inside the window. The sliders opens Image settings in an anchored popover for current conversion, resize, compression, metadata and replace-original choices. It has no action buttons; the toolbar Start is the single step that processes and saves.
