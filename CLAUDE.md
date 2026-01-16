# CLAUDE.md - AI Assistant Guide for RadAssist

This document provides essential context for AI assistants working with the RadAssist codebase.

## Project Overview

**RadAssist** is a radiology workflow assistant tool that provides medical calculators and smart text parsing. It's available in two interfaces:

1. **Desktop App** (`RadAssist.ahk`) - Windows AutoHotkey v2 application for PowerScribe/Notepad integration
2. **Web Interface** (`index.html`) - Standalone browser-based calculator suite

### Key Features
- 8 medical calculators (Volume, RV/LV, NASCET, Adrenal Washout, Fleischner, ICH, Stenosis, Follow-up Date)
- Smart text parsing with confidence scoring
- Clipboard integration for radiology reporting
- Dark "Clinical Noir" theme with amber accents

## Repository Structure

```
Radiology-Right-Click/
├── RadAssist.ahk              # Main desktop app (AHK v2, ~3100 lines)
├── index.html                 # Web interface (single-file HTML/CSS/JS)
├── README.md                  # User documentation
├── readme.txt                 # Legacy readme
├── SectraToPS_History.ahk     # Standalone Sectra history copy utility (AHK v1)
├── Radiology Right Click v1.22*.ahk  # Legacy v1 versions (AHK v1)
└── todos/                     # Task tracking markdown files
    ├── 004-pending-*.md       # Pending refactoring tasks
    ├── 007-pending-*.md
    ├── 010-pending-*.md
    ├── 017-pending-*.md
    ├── 018-pending-*.md
    └── *-complete-*.md        # Completed tasks
```

## Technology Stack

### Desktop App (RadAssist.ahk)
- **AutoHotkey v2.0+** (NOT v1 - syntax differs significantly)
- Uses `#Requires AutoHotkey v2.0` directive
- GUI uses v2 `Gui()` class, not v1 `Gui, Add` commands
- Menu uses v2 `Menu()` class
- Functions use v2 syntax: `FunctionName(params) { }`
- Event handlers: `.OnEvent("Click", HandlerFunc)`

### Web Interface (index.html)
- Vanilla HTML/CSS/JavaScript (no frameworks)
- CSS custom properties for theming
- Mobile-responsive design
- Self-contained single file

## Code Architecture

### RadAssist.ahk Structure

The file is organized in logical sections (lines are approximate):

| Section | Lines | Description |
|---------|-------|-------------|
| Header & Config | 1-90 | Version info, globals, hotkeys |
| Menu Building | 98-245 | Dynamic context menu construction |
| Calculator GUIs | 247-960 | 8 calculator GUI functions |
| Smart Parsers | 1300-2400 | Text parsing with regex patterns |
| Utilities | 2400-2700 | Clipboard, insertion, helpers |
| Settings | 2700-3000 | Preferences GUI and INI handling |
| Initialization | 3000-3100 | Path setup, preferences loading |

### Key Design Patterns

1. **Confidence Scoring** - Smart parsers assign confidence (0-100%) to parsed values:
   ```autohotkey
   ; Pattern A (HIGH confidence 95): "organ measures X.X x X.X x X.X cm"
   ; Pattern B (MEDIUM confidence 75): just dimensions with units
   ; Pattern C (LOW confidence 35): numbers without units
   ```

2. **Context-Filtered Parsing** - Uses `FilterNonMeasurements()` to strip irrelevant text

3. **Confirmation Dialogs** - `ShowParseConfirmation()` shows parsed values before insertion

4. **OneDrive Compatibility** - `InitPreferencesPath()` handles read-only directories

### Global Variables

Configuration globals (loaded from INI):
- `TargetApps` - Apps where Shift+Right-click menu appears
- `ShowCitations` - Include literature references
- `DefaultSmartParse` - Default calculator for Quick Parse
- `DefaultMeasurementUnit` - cm or mm when units not detected
- `Show*Tools` - Visibility toggles for each calculator

Runtime globals:
- `g_SelectedText` - Currently selected text
- `g_ConfirmAction` - Dialog result
- `*GuiObj` - GUI object references (e.g., `RVLVGuiObj`)

## Development Guidelines

### AutoHotkey v2 Conventions

```autohotkey
; CORRECT v2 syntax:
MyFunction(param1, param2 := "default") {
    local var := "value"
    if (condition) {
        ; do something
    }
    return result
}

; GUI in v2:
myGui := Gui("+AlwaysOnTop")
myGui.Add("Text", "x10 y10", "Label")
myGui.Add("Button", "x10 y40", "Click Me").OnEvent("Click", MyHandler)
myGui.Show()

; WRONG (v1 syntax):
; MyFunction:
;     Gui, Add, Text, x10 y10, Label
; return
```

### Comment Conventions

The codebase uses structured comments:
```autohotkey
; WHY: Explains the reasoning behind a design decision
; ARCHITECTURE: Describes structural/pattern choices
; TRADEOFF: Documents compromises made
; NOTE: Important implementation details
```

### Adding a New Calculator

1. Add visibility toggle global: `global ShowNewTools := true`
2. Add to menu building (lines 137-200)
3. Create GUI function: `ShowNewGui()` and `NewGuiClose(*)`
4. Create calculation function: `CalcNew(*)`
5. Add smart parser: `ParseAndInsertNew(input)`
6. Add menu handlers: `MenuSmartNew(*)`
7. Add to settings GUI and INI read/write

### Testing Changes

1. **Desktop App**: Double-click `RadAssist.ahk` to run
   - Use backtick (`) to pause/resume
   - Look for green "H" tray icon
   - Test in Notepad (safer than PowerScribe)

2. **Web Interface**: Open `index.html` in any browser
   - All calculators work standalone
   - Test Quick Parse with sample text

### Common Debug Steps

```autohotkey
; Add message box for debugging
MsgBox("Debug: " . variableName)

; Use TrayTip for non-blocking notifications
TrayTip("Debug info", "RadAssist", 1)

; Check clipboard content
MsgBox("Clipboard: " . A_Clipboard)
```

## Known Issues (Pending Todos)

| Issue | Priority | Description |
|-------|----------|-------------|
| #004 | P2 | Duplicated prefilled GUI functions (~130 lines) |
| #007 | P2 | Excessive global state (14+ globals) |
| #010 | P3 | Mixed function/label syntax (already migrated to v2) |
| #017 | P3 | Hardcoded pixel coordinates (no DPI awareness) |
| #018 | P3 | Monolithic single-file structure |

See `todos/` directory for detailed task descriptions.

## Medical Calculator Reference

| Calculator | Formula/Logic | Key Function |
|------------|---------------|--------------|
| Ellipsoid Volume | π/6 × L × W × H | `CalcEllipsoidVolume()` |
| RV/LV Ratio | RV / LV (strain if ≥1.0) | `CalcRVLV()` |
| NASCET Stenosis | (distal - stenosis) / distal × 100 | `CalcNASCET()` |
| Adrenal Washout | Abs: (post-delayed)/(post-pre)×100 | `CalcAdrenalWashout()` |
| Fleischner 2017 | Decision tree by size/type/risk | `GetFleischnerRecommendation()` |
| ICH Volume | A × B × C / 2 (ABC/2 method) | `CalcICH()` |
| Vessel Stenosis | (normal - stenosis) / normal × 100 | `CalcStenosis()` |
| Follow-up Date | Base date + interval | `CalcDate()` |

## Important File Paths

- **Preferences INI**: `RadAssist_preferences.ini` (script dir or `%LOCALAPPDATA%\RadAssist\`)
- **Script Directory**: `A_ScriptDir` (where .ahk file is located)

## Git Workflow

- Main development on feature branches
- Commit messages should describe the "why" not just the "what"
- Test in Notepad before committing PowerScribe-related changes

## Quick Reference

### Keyboard Shortcuts (Desktop)
| Key | Action |
|-----|--------|
| Shift+Right-click | Open RadAssist menu (in target apps) |
| Backtick (`) | Pause/Resume script |
| Ctrl+Shift+H | Copy Sectra history |

### Regex Patterns Used
- Dimensions: `(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(cm|mm)?`
- HU values: `(\d+)\s*(?:hu|HU)`
- RV/LV keywords: `(?:RV|R\.V\.|Right\s*(?:ventricle|ventricular))`

## Contact / Resources

- **Issues**: https://github.com/Thornwalker87/Radiology-Right-Click/issues
- **AutoHotkey v2 Docs**: https://www.autohotkey.com/docs/v2/
