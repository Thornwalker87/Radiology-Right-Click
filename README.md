# RadAssist v2.5

A lightweight radiology assistant tool with right-click calculators and smart text parsing. Available as both a Windows desktop app (AutoHotkey) and a modern web interface.

## Choose Your Interface

| Feature | Desktop (AHK) | Web Interface |
|---------|---------------|---------------|
| **Best for** | PowerScribe integration, clipboard workflow | Standalone use, any device |
| **Theme** | Dark "Clinical Noir" with amber accents | Dark theme with animations |
| **Live Preview** | Yes - results update as you type | Yes - instant calculations |
| **Platform** | Windows only (requires AHK v2) | Any browser, any OS |
| **Insert to Report** | Direct clipboard insertion | Copy to clipboard |

## Web Interface

Open `index.html` in any browser for a modern, responsive calculator suite featuring:

- **Quick Parse** - Auto-detect and parse measurement text instantly
- **Dark theme** with premium medical aesthetic
- **All 8 calculators** with real-time results and clinical interpretations
- **Copy to clipboard** - One-click result copying
- **Mobile responsive** - Works on tablets and phones

### Calculators

| Calculator | Description |
|------------|-------------|
| Ellipsoid Volume | Organ/mass volume from 3D dimensions |
| RV/LV Ratio | Right heart strain evaluation for PE |
| NASCET Stenosis | Carotid stenosis with severity grading |
| Adrenal Washout | Absolute/relative washout for adenoma characterization |
| Fleischner 2017 | Lung nodule follow-up recommendations |
| ICH Volume | ABC/2 hemorrhage volume estimation |
| Vessel Stenosis | General diameter-based stenosis |
| Follow-up Date | Calculate imaging follow-up dates |

## Desktop App (Windows)

**Which file?** `RadAssist.ahk` needs **AutoHotkey v2** (Shift+Right-click tools, all smart parsers, Quick Call built in).
`Radiology Right Click v1.22.ahk` (and `-local`) run on **AutoHotkey v1.1** (plain right-click menu, Quick Call built in).
Both are single files that run from OneDrive or a USB stick.

**Feature parity:** the v1.22 scripts include the same Smart Parse engine as RadAssist (ported to
AutoHotkey v1 in `SmartParse_v1.ahk` and embedded): right-click > **Smart Parse (Auto-detect)** /
**Smart Parse as...** (volume with prostate grading, ICH, RV/LV, NASCET/stenosis, adrenal, Fleischner,
follow-up date, TI-RADS, O-RADS) and **Bone Age** (enable in Preferences). The v1 port produces the
same output as RadAssist on the whole test-phrase set. Preferences now use a two-column layout.

### What's New in v2.5

- **AutoHotkey v2 conversion** - Full rewrite to AHK v2 syntax for modern compatibility
- **Dark theme UI** - "Clinical Noir" aesthetic with amber accents across all dialogs
- **Live preview** - See calculation results update in real-time as you type
- **Color-coded severity** - RV/LV ratio displays green/yellow/red based on clinical thresholds
- **Web interface** - New browser-based calculator suite for cross-platform use

### What's New in v2.4

- **ICH Volume (ABC/2)**: Smart parse + GUI for intracerebral hemorrhage volume
- **Follow-up Date Calculator**: Smart parse + GUI for calculating follow-up dates
- **Tool Visibility**: Show/hide any of the 8 tools via Settings
- **Bug Fixes**: RV/LV parser, NASCET mixed units, Stenosis text deletion, Fleischner IMPRESSION detection

## Quick Start

### Web Interface
1. Open `index.html` in your browser
2. Use Quick Parse or select a specific calculator
3. Copy results to clipboard

### Desktop App (Windows)
1. **Install AutoHotkey v2** from [autohotkey.com](https://www.autohotkey.com/)
2. **Download** `RadAssist.ahk` to any folder (Quick Call is built in; extract the ZIP first)
3. **Double-click** to run - look for the green "H" icon in your system tray
4. **Use it**: In PowerScribe or Notepad, highlight text with measurements, then **Shift + Right-click**

## How to Use (Desktop)

### Smart Parsing (Fastest Method)
1. Highlight the dictated sentence(s) (e.g., "The prostate gland measures 4.5 x 3.2 x 4.1 cm.")
2. **Shift + Right-click** → **Smart Parse (Auto-detect)** (or **Smart Parse as...** to force a calculator)
3. Review the parsed values and the text to be inserted → Click "Insert"

Auto-detect recognizes normal dictation, for example:

| Dictation | Calculation |
|-----------|-------------|
| The prostate gland measures 4.5 x 3.2 x 4.1 cm. | Prostate volume + grade (<30 normal, 30-49 mild, 50-79 moderate, 80+ severe prostatomegaly; prostate only) |
| Right ovarian cyst measuring 32 x 24 x 28 mm. | Ellipsoid volume |
| Intraparenchymal hemorrhage measuring 4.2 x 2.8 x 3.5 cm. | ICH volume (ABC/2), no severity wording |
| The right ventricle measures 4.2 cm and the left ventricle measures 3.8 cm. | RV/LV ratio (normal <0.9, borderline 0.9-0.99, elevated >=1.0 - never "severe") |
| The proximal ICA residual lumen measures 1.2 mm and the normal distal cervical ICA measures 4.5 mm. | NASCET |
| The SMA has a focal narrowing measuring 2 mm with a normal distal caliber of 6 mm. | Vessel stenosis % |
| 45 HU on noncontrast, 85 HU on portal venous phase, and 50 HU on 15-minute delayed phase. | Adrenal washout |
| 7 mm solid noncalcified pulmonary nodule in the right upper lobe. | Fleischner 2017 (repeat mentions in the impression are not double-counted) |
| Recommend follow-up ultrasound in 6 months. | Follow-up due date |
| Right lobe: solid, hypoechoic, 1.5 cm nodule with macrocalcifications. | ACR TI-RADS points, TR level and FNA / follow-up per nodule (whole report OK; nodules repeated in the IMPRESSION are skipped; inserted after the IMPRESSION) |
| 5.8 cm right ovarian hemorrhagic cyst with reticular echoes, 32-year-old. | O-RADS US category + SRU follow-up (simple, hemorrhagic, endometrioma, dermoid; pre/postmenopausal - both given if unknown; solid/papillary/flow features are refused) |

**Bone Age (Greulich & Pyle):** turn on in Settings (off by default). Shift+Right-click > Bone Age
(or Smart Parse on text containing "bone age"). Type the bone age in any style (13 years 6 months, 13y6m,
13.5, 13 1/2, 13 6/12, 13:6, 162 months); chronological age and sex are filled from the highlighted text
or **Read report** (DOB + exam date, "Age: 12 years 3 months", "12-year-old girl", "8 yo M"). Inserts the
standard paragraph with the G&P standard deviation for age/sex and whether the bone age is within 2 SD.

**Liver LI-RADS (CT/MRI v2018), v1.22 only:** turn on in Preferences > Smart Parse (off by default).
Right-click > Liver LI-RADS (CT/MRI), or Smart Parse on text mentioning LI-RADS / APHE / arterial phase
hyperenhancement. A window pre-filled from the highlighted text (size, nonrim APHE, nonperipheral washout,
enhancing capsule, threshold growth, tumor in vein, LR-M features) shows the category and management live;
ancillary features can upgrade (max LR-4) or downgrade by one. Check every box, then Insert.

**Dark theme:** Settings > Appearance > Dark theme.

**Inserting:** the confirmation dialog stays in front of PowerScribe/Sectra, does not block
Shift+Right-click, and Insert pastes back into the window you Shift+Right-clicked in. Fleischner
blocks go at the end of the report (after the IMPRESSION) unless that setting is turned off.

**Target apps:** PowerScribe 360, any program whose name contains "PowerScribe" (ready for the planned
move to **PowerScribe One** - if PowerScribe One runs inside a web browser, its window will need to be
added to `TargetApps`), and Notepad for testing.

**Units:** each number keeps its own unit, so cm and mm can be mixed freely ("4.5 cm x 32 mm x 41 mm",
"distal ICA 0.5 cm, stenosis 3 mm"). Numbers without units are guessed (large values = mm) and flagged
as low confidence; the default can be set in Settings.

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| `` ` `` (backtick) | Pause/Resume script |
| `Ctrl+Shift+H` | Copy Sectra history |
| `Shift+Right-click` | Open RadAssist menu |
| `Ctrl+Alt+P` | Show / hide the Quick Call panel |
| `Ctrl+Alt+D` | Dial the highlighted phone number |
| `Ctrl+Alt+L` | Paste a critical-result call statement for the last call |

### Quick Call Panel
A floating, always-on-top call panel (Google Voice), built into `RadAssist.ahk` (`QuickCall.ahk` is the same code as a standalone script).
- Stays **in front of Sectra and PowerScribe**: it is a tool window that re-raises itself
  (without stealing focus) whenever another app's window covers it
- **Resizable**: drag any edge; buttons stretch to fit. The **[-] / [+]** button - or a **double-click on the title bar** - collapses the
  panel to a small "Quick Call" rectangle and expands it again (size and state are remembered)
- Click a name to call: big buttons for the main numbers, **+ Techs** for per-site tech numbers (number keys are left alone for window/level presets)
- **Dial #...**, **Log call** (critical-result statement), **Edit #s** (phone book in `QuickCall_PhoneBook.txt`)
- `Esc` or the X hides it; bring it back with `Ctrl+Alt+P`, the Shift+Right-click menu, or the tray menu
- Turn it on/off in **Settings → Quick Call → Enable Quick Call panel**

### Quick Call in Radiology Right Click v1.22 (AutoHotkey v1)
The Quick Call panel, rewritten for AutoHotkey v1.1 (needs v1.1.25+; a portable `AutoHotkey.exe`
run from OneDrive works), is **built into** `Radiology Right Click v1.22.ahk` and
`Radiology Right Click v1.22-local.ahk`, so each script is a single self-contained file.
(`QuickCall_v1.ahk` is the same code as a standalone script, if you want to run it on its own.)
- Extract the ZIP first (don't run the script from inside the ZIP), then copy the v1.22 script to your OneDrive folder
- Turn it on/off in **Right-click → Preferences → Quick Call → Show panel (Ctrl+Alt+P)**
  (on by default in v1.22; off by default in v1.22-local because it opens Google Voice links)
- **Place calls from** (Preferences, or right-click any panel button):
  - *This computer (Google Voice)*: call audio on the PC (dictaphone / headset). Quick Call presses
    Google Voice's "Call" prompt for you.
  - *My cell phone (Google Voice)*: Google Voice rings your cell first; answer it and the call connects.
    Use this where the network blocks browser call audio (e.g. some VPNs). Needs **Always use my phone
    to place calls** turned on in Google Voice > Settings > Calls; Quick Call offers to open that page
    when you switch (and reminds you to turn it off when you switch back).
  - *Microsoft Teams*: opens Teams with the number ready. Needs outside calling in Teams (a dial pad on
    the Calls tab).
- Phone book and panel position are saved next to the script (`QuickCall_PhoneBook.txt`,
  `QuickCall_Settings.ini`); the phone book is written via a temp file so a OneDrive sync lock can't wipe it
- Don't run RadAssist with Quick Call enabled at the same time; both use Ctrl+Alt+P/D/L

## Settings (Desktop)

Right-click the tray icon → **Settings** to customize:
- Default calculator for Quick Parse
- Show/hide citations
- RV/LV output format (Inline vs Macro)
- Default measurement units (cm/mm)
- Tool visibility (show/hide individual calculators)
- Quick Call panel on/off

## Troubleshooting

- **Script not responding?** Press backtick (`) - it might be paused
- **Menu not appearing?** Make sure you're in PowerScribe or Notepad
- **Settings not saving?** Check if the folder is read-only (OneDrive sync issue)

## Requirements

### Web Interface
- Any modern browser (Chrome, Firefox, Safari, Edge)

### Desktop App
- Windows 10/11
- AutoHotkey v2.0+
- PowerScribe 360 or Notepad
