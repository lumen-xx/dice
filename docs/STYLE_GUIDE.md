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

Avoid one-off font sizes in new UI. Text follows system light/dark appearance and accessibility contrast. Font hierarchy conveys importance without decorative headings; the one uppercase style is the glass micro label (below).

## Colour and material

Dice's colour is **Aurora**, the light that runs around the window when a file is dragged over it. It's one palette for the whole app: the drop glow, the Start button, progress, the app icon and the menu bar drop target all use the same four colours. There is no other brand colour.

| Token | Hex (sRGB) | Role |
|---|---|---|
| Mint | `#34E5B8` | Start of the loop; brightest moments |
| Cyan | `#2BC4F2` | Loop and gradients |
| Indigo | `#5E6BFF` light · `#8C96FF` dark | **The accent**: Start, switches, checkboxes, sliders, selection, menu icons |
| Violet | `#A65CFF` | End of the loop |

The values live in `Sources/Dice/Style.swift` (`DiceStyle`), with SwiftUI and AppKit versions; `scripts/icon.swift` repeats them for the icon.

How to use them:

- **One solid accent.** Indigo is the only flat brand colour. The Start play glyph, toggles, sliders, pickers, the selected batch row (14% indigo) and the export menu's icons use it. Image settings is the exception: it is monochrome (see Image settings below). Dark appearance uses the lighter `#8C96FF`, so the accent stays readable on translucent popovers over dark or busy images. Pickers and pop-up menus show their value in the primary text colour, never the accent.
- **Gradients are for brand moments only**: the drop glow and progress ring (the closed loop mint → cyan → indigo → violet → mint), and the app icon. The empty-state die is monochrome (secondary label colour), so the empty window stays quiet until something is dragged over it. Never put a gradient on text, on secondary controls or across large backgrounds.
- **Start** is the plain play glyph in the toolbar, in indigo, with the standard 30 pt target. Disabled, it uses the native disabled appearance.
- **Motion.** The glow turns only while an accepted file hovers over the window. The progress ring moves only when an image finishes. Nothing is animated while idle, and Reduce Motion stops both.
- Primary and secondary system text colours carry content and supporting details. Errors use the system red; disabled controls use the native disabled appearance.
- The window uses native HUD material with behind-window blur. The toolbar and pager use ultra-thin material, a capsule shape and a subtle 0.5 pt edge.

## Layout and interaction

Use a 4-point spacing grid: 4, 8, 12, 16, 20, 24. Shared edge inset is 16 pt. Toolbar symbol targets are 30 × 30 pt; root corners are 14 pt. The top-left close button matches the capsule material and dimensions of the top-right toolbar. There is no native title bar or traffic-light strip; the image surface and drag glow cover the entire window. Minimize and fullscreen are disabled.

The top-right toolbar carries Add, Metadata, Settings and Start. Start saves copies automatically. The bottom-right pager stays present in image, metadata and batch views. Its middle number opens the searchable batch list. Metadata and the batch list replace the image inside the same window, with a Back control; they never open another dashboard.

With **Fit photos to the window** (App settings › General), an opaque photo fills the whole window edge to edge, behind the toolbar and pager. Edges that don't fit are hidden in the preview only, and the footer text gets the same capsule material as the pager. Images with any transparent pixels, and SVGs, PDFs and Illustrator files, keep the inset layout, so they're never cropped against the window material. The setting is off by default.

Use restrained transitions and honour Reduce Motion. Avoid idle animation. Search is local and matches filename/path, image properties, tag names/values and recognised text. Removing a batch entry never deletes the original file.

Launching from Finder or Applications reveals the drop surface. Only an explicit Choose images or Add action opens the file picker; opening image files imports them directly.

The metadata view uses an unboxed navigation header and flat name/value rows. Show each group name once as a quiet section label. Search has a single subtle background; the group filter stays neutral. Select a row to reveal its full, selectable value in place. Avoid table chrome and alternating filled rows.

Search begins 12 points below the navigation header. The shared footer aligns image counts or resolution/format/size on the left with paging on the right. Metadata rows have a trailing copy-value button with a 30-point target.

Settings is a view inside the same window, opened with the sliders or Command-comma. Its Back action returns to the image. Window edges use directional resize cursors, with diagonal corners. Paging reuses bounded decoded previews; metadata comes from the session cache.

App settings share the editor surface and use the same plain rows as Image settings, in six sections, each headed by a small tertiary title:

| Section | Rows |
|---|---|
| New images | Format, Quality, Size, Metadata, Replace originals |
| Saving | When finished, Save to, File name, Close Dice when finished |
| Conversion | Keep animations, Animations in other formats, JPEG background, Keep the original when it's smaller |
| Window | Fit photos to the window, Stay on top |
| System | Start at login, Menu bar, Drop target, Start right after a drop, Finder menu |
| Updates | Check automatically, Check now |

A setting that used to be a switch plus a picker is one menu: Format ("Same as original" means no default), Save to ("Beside originals" or the chosen folder, with Choose folder…), and Metadata (Keep, Remove, Always remove). Switches are the monochrome `MonoSwitch`. Update checks are opt-in. Settings scroll inside the window with no scroll bar, and Back and the close control stay visible.

The sliders button opens Image settings in an anchored popover for the current batch's conversion, resize, compression, metadata and replace-original choices. It has no action buttons: the toolbar's Start is the one step that processes and saves.

## Image settings

Image settings is a short, plain list on the native popover material, with no heading, boxes or capsules. The SwiftUI pieces live in `Sources/Dice/SettingsControls.swift`.

- **Rows.** Each row is 28 pt high, with the label on the left in 13 pt secondary text and the value on the right in 13 pt primary text. Rows are separated by space, with one divider before the switches. The rows are Format, Quality, Size, Rotate, Crop and Metadata, then Remove background and Replace originals.
- **Values open menus.** A value with a small up-down chevron opens the native menu with a checkmark. Options that modify a row live in its menu, under a divider, as checkmark items rather than extra rows:
  - Format: Metadata only, Lossless, Optimise PNG, Combine into one PDF, Convert to sRGB, Keep HDR.
  - Size: Allow enlarging, Resize only, Also save @2x and @1x, PDF resolution.
  
  Only options that apply to the batch appear. The row's value names the important ones ("WebP · Lossless", "Fill · @1–3x").
- **Monochrome.** The popover has no indigo. Switches and the slider use the primary colour. A flip that is on sits on a soft round primary fill. Indigo stays for Start and other brand moments.
- **Direct actions** (rotate, flip) are bare symbols. The angle shows beside them only when it isn't 0°.
- **Numbers** sit on a faint field, right-aligned, with the unit in secondary text.
- **Tips.** A row that needs explaining has a small tertiary ⓘ beside its label: Format, Quality or Target size, Size, Crop, Metadata, Remove background and Replace originals. Hovering over it (or clicking it) shows a short caption bubble drawn inside the panel, over the neighbouring rows: below the row, or above it for the bottom rows. A tip never opens a second popover, which could close the panel. Keep tips to about five lines, saying what the option does, what it works with, and any catch.

