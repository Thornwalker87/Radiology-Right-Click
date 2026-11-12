; ==========================================
; RadAssist - Radiology Assistant Tool
; Version: 2.5 (AHK v2)
; Description: Lean radiology workflow tool with calculators
;              Triggered by Shift+Right-click in PowerScribe/Notepad
;              Smart text parsing with confirmation dialogs
; ARCHITECTURE: Context-filtered parsing with confidence scoring
; WHY: v2.5 converts to AHK v2 syntax for compatibility
; CHANGES in v2.5:
;   - Converted to AutoHotkey v2 syntax
;   - GUI system rewritten to use v2 Gui class
;   - Menu system converted to v2 Menu class
;   - All commands converted to v2 function syntax
; ==========================================

#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)

; -----------------------------------------
; OneDrive Compatibility - Determine preferences path
; WHY: Script may run from OneDrive folder with sync conflicts
; TRADEOFF: Falls back to LOCALAPPDATA if script dir is read-only
; -----------------------------------------
global PreferencesPath := ""

; Initialize preferences path (function defined in Functions section below)
; Call after global declaration to set path based on write permissions
; NOTE: Forward reference - function defined at end of file (AHK parses all functions first)
InitPreferencesPath()

; -----------------------------------------
; Global Configuration
; -----------------------------------------
global TargetApps := ["ahk_exe Nuance.PowerScribe360.exe", "ahk_exe notepad.exe", "ahk_class Notepad"]
; NOTE: Any program whose .exe name contains "PowerScribe" also counts (e.g. the
;       planned move to PowerScribe One). See RA_IsTargetApp().
global TargetAppPattern := "i)powerscribe|^notepad\.exe$"
global SectraWindowTitle := "Sectra"
global DataminingPhrase := "SSM lung nodule"
global IncludeDatamining := true
global ShowCitations := true
global DefaultSmartParse := "Auto"    ; Options: Auto, Volume, RVLV, NASCET, Stenosis, Adrenal, Fleischner, ICH, Date
global SmartParseConfirmation := true  ; Always show confirmation dialog before insert
global SmartParseFallbackToGUI := true ; Fall back to GUI when parsing confidence is low
global DefaultMeasurementUnit := "cm"  ; Options: cm, mm - used when no units in input
global RVLVOutputFormat := "Macro"     ; Options: Inline, Macro - output format for RV/LV
global UseASCIICharacters := true      ; Use ASCII <=/>= instead of Unicode
global FleischnerInsertAfterImpression := true  ; Find IMPRESSION: and insert below
global g_SPResult := ""      ; Smart Parse result waiting in the confirmation dialog
global g_TargetHwnd := 0     ; report window (PowerScribe/Notepad) to paste back into
global g_ParsedResultText := ""  ; Stores parsed result for insertion

; -----------------------------------------
; Tool Visibility Preferences
; WHY: Allow users to show/hide tools they don't use
; NOTE: These are saved to INI and loaded on startup
; -----------------------------------------
global ShowVolumeTools := true
global ShowRVLVTools := true
global ShowNASCETTools := true
global ShowAdrenalTools := true
global ShowFleischnerTools := true
global ShowStenosisTools := true
global ShowICHTools := true
global ShowDateCalculator := true
global ShowTIRADS := true          ; Thyroid ACR TI-RADS
global ShowORADS := true           ; Ovarian cyst O-RADS / SRU
global ShowBoneAge := false        ; Bone age (Greulich & Pyle) - mostly for MSK/peds readers
global DarkTheme := false          ; Dark colors for RadAssist windows
global RA_ThemeKeep := Map()       ; controls whose own text color should be kept

; -----------------------------------------
; Quick Call (floating always-on-top call panel, see QuickCall.ahk)
; WHY: Optional module - toggled from Settings, saved to INI
; -----------------------------------------
global QuickCallEnabled := true

; -----------------------------------------
; Exit Cleanup Handler
; WHY: Clear clipboard on exit to prevent PHI exposure
; -----------------------------------------
OnExit(CleanupOnExit)

CleanupOnExit(ExitReason, ExitCode) {
    A_Clipboard := ""
    return 0  ; Allow exit to proceed
}

; -----------------------------------------
; Global Hotkey: Ctrl+Shift+H - Sectra History Copy
; (Can be mapped to Contour ShuttlePRO button)
; -----------------------------------------
^+h:: {
    CopySectraHistory()
}

; -----------------------------------------
; Global Hotkey: Backtick (`) - Pause/Resume Script
; WHY: Quick toggle without opening menu
; -----------------------------------------
`:: {
    Suspend(-1)
    if (A_IsSuspended)
        TrayTip("Script PAUSED - Press `` to resume", "RadAssist", 1)
    else
        TrayTip("Script RESUMED", "RadAssist", 1)
}

; -----------------------------------------
; Shift+Right-Click Menu Handler
; -----------------------------------------
+RButton:: {
    global g_SelectedText, TargetApps, ShowVolumeTools, ShowRVLVTools, ShowNASCETTools
    global ShowAdrenalTools, ShowFleischnerTools, ShowStenosisTools, ShowICHTools
    global ShowDateCalculator, DefaultSmartParse, ShowTIRADS, ShowORADS, ShowBoneAge, DarkTheme

    ; Check if we're in a target application
    inTargetApp := RA_IsTargetApp()

    if (!inTargetApp) {
        ; Not in target app - send normal shift+right-click
        Send("+{RButton}")
        return
    }
    global g_TargetHwnd
    g_TargetHwnd := WinExist("A")   ; paste results back into this window later

    ; Store any selected text
    ; WHY: Extended timeout (0.5s → 1s) for slower applications like PowerScribe
    ; TRADEOFF: Slightly slower menu appearance vs better reliability
    g_SelectedText := RA_CopySelection()

    ; Build and show menu
    ; WHY: Conditionally build menu based on tool visibility preferences
    ; ARCHITECTURE: Menu items only added if corresponding Show*Tools is true
    RadAssistMenu := Menu()
    SmartParseMenu := Menu()

    smartParseHasItems := false
    if (ShowVolumeTools) {
        SmartParseMenu.Add("Smart Volume (parse dimensions)", MenuSmartVolume)
        smartParseHasItems := true
    }
    if (ShowRVLVTools) {
        SmartParseMenu.Add("Smart RV/LV (parse ratio)", MenuSmartRVLV)
        smartParseHasItems := true
    }
    if (ShowNASCETTools) {
        SmartParseMenu.Add("Smart NASCET (parse stenosis)", MenuSmartNASCET)
        smartParseHasItems := true
    }
    if (ShowStenosisTools) {
        SmartParseMenu.Add("Smart Vessel Stenosis (any vessel)", MenuSmartStenosis)
        smartParseHasItems := true
    }
    if (ShowAdrenalTools) {
        SmartParseMenu.Add("Smart Adrenal (parse HU values)", MenuSmartAdrenal)
        smartParseHasItems := true
    }
    if (ShowFleischnerTools) {
        if (smartParseHasItems)
            SmartParseMenu.Add()
        SmartParseMenu.Add("Parse Nodules (Fleischner)", MenuSmartFleischner)
        smartParseHasItems := true
    }
    if (ShowICHTools) {
        SmartParseMenu.Add("Smart ICH Volume (ABC/2)", MenuSmartICH)
        smartParseHasItems := true
    }
    if (ShowDateCalculator) {
        SmartParseMenu.Add("Smart Follow-up Date", MenuSmartDate)
        smartParseHasItems := true
    }
    if (ShowTIRADS || ShowORADS)
        SmartParseMenu.Add()
    if (ShowTIRADS) {
        SmartParseMenu.Add("Thyroid ACR TI-RADS", MenuSmartTIRADS)
        smartParseHasItems := true
    }
    if (ShowORADS) {
        SmartParseMenu.Add("Ovarian Cyst (O-RADS / SRU)", MenuSmartORADS)
        smartParseHasItems := true
    }

    ; Auto-detect works out which calculation the highlighted text needs
    RadAssistMenu.Add("Smart Parse (Auto-detect)", MenuAutoParse)
    if (smartParseHasItems)
        RadAssistMenu.Add("Smart Parse as...", SmartParseMenu)
    if (DefaultSmartParse != "Auto")
        RadAssistMenu.Add("Quick Parse (" DefaultSmartParse ")", MenuQuickSmartParse)
    RadAssistMenu.Add()

    ; GUI calculators - conditionally add based on visibility
    guiHasItems := false
    if (ShowVolumeTools) {
        RadAssistMenu.Add("Ellipsoid Volume (GUI)", MenuEllipsoidVolume)
        guiHasItems := true
    }
    if (ShowAdrenalTools) {
        RadAssistMenu.Add("Adrenal Washout (GUI)", MenuAdrenalWashout)
        guiHasItems := true
    }
    if (guiHasItems)
        RadAssistMenu.Add()

    stenosisHasItems := false
    if (ShowNASCETTools) {
        RadAssistMenu.Add("NASCET (Carotid)", MenuNASCET)
        stenosisHasItems := true
    }
    if (ShowStenosisTools) {
        RadAssistMenu.Add("Vessel Stenosis (General)", MenuStenosis)
        stenosisHasItems := true
    }
    if (ShowRVLVTools) {
        RadAssistMenu.Add("RV/LV Ratio (GUI)", MenuRVLV)
        stenosisHasItems := true
    }
    if (stenosisHasItems)
        RadAssistMenu.Add()

    if (ShowFleischnerTools) {
        RadAssistMenu.Add("Fleischner 2017 (GUI)", MenuFleischner)
        RadAssistMenu.Add()
    }

    ; New calculators section
    newCalcHasItems := false
    if (ShowICHTools) {
        RadAssistMenu.Add("ICH Volume (ABC/2)", MenuICHVolume)
        newCalcHasItems := true
    }
    if (ShowDateCalculator) {
        RadAssistMenu.Add("Follow-up Date Calculator", MenuDateCalc)
        newCalcHasItems := true
    }
    if (ShowBoneAge) {
        RadAssistMenu.Add("Bone Age (Greulich && Pyle)", MenuBoneAge)
        newCalcHasItems := true
    }
    if (newCalcHasItems)
        RadAssistMenu.Add()

    RadAssistMenu.Add("Copy Sectra History (Ctrl+Shift+H)", MenuSectraHistory)
    if (QuickCallEnabled)
        RadAssistMenu.Add("Quick Call Panel (Ctrl+Alt+P)", MenuQuickCall)
    RadAssistMenu.Add()
    RadAssistMenu.Add("Settings", MenuSettings)

    RA_SetDarkMenus(DarkTheme)
    RadAssistMenu.Show()
}

; -----------------------------------------
; Is the active window PowerScribe (360 or One) or Notepad?
; -----------------------------------------
RA_IsTargetApp() {
    global TargetApps, TargetAppPattern
    for app in TargetApps {
        if WinActive(app)
            return true
    }
    try return RegExMatch(WinGetProcessName("A"), TargetAppPattern) > 0
    return false
}

; -----------------------------------------
; Copy the highlighted text without disturbing the user's clipboard
; WHY: Ctrl+C sent while Shift is still held (from Shift+Right-click) can be read
;      as Ctrl+Shift+C and copy nothing. Retry once after Shift is released.
; -----------------------------------------
RA_CopySelection() {
    saved := ClipboardAll()
    txt := ""
    Loop 2 {
        A_Clipboard := ""
        if (A_Index = 2) {
            KeyWait("Shift", "T1")
            KeyWait("Control", "T0.5")
            Sleep(50)
        }
        Send("{Shift up}^c")
        if ClipWait(A_Index = 1 ? 0.6 : 1.2) {
            txt := A_Clipboard
            break
        }
    }
    A_Clipboard := saved
    return txt
}

; -----------------------------------------
; Utility: Show no-selection error with context
; -----------------------------------------
ShowNoSelectionError(parseType) {
    messages := Map("Volume", "dimensions", "RVLV", "RV/LV measurements", "NASCET", "stenosis values", "Adrenal", "HU values", "Fleischner", "nodule measurements")
    msg := messages.Has(parseType) ? messages[parseType] : "text"
    MsgBox("Please select text containing " msg " first.`n`nHighlight the relevant text and try again.", "No Selection", 0x40030)
}

; -----------------------------------------
; Menu Handlers (converted to functions for v2)
; -----------------------------------------

; Smart Parse handlers (inline text parsing with insertion)
MenuSmartVolume(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        ShowNoSelectionError("Volume")
        return
    }
    ParseAndInsertVolume(g_SelectedText)
}

MenuSmartRVLV(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        MsgBox('Please select text containing RV/LV measurements (e.g., "RV 42mm / LV 35mm")', "No Selection", 0x40030)
        return
    }
    ParseAndInsertRVLV(g_SelectedText)
}

MenuSmartNASCET(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        MsgBox('Please select text containing stenosis measurements (e.g., "distal 5.2mm, stenosis 2.1mm")', "No Selection", 0x40030)
        return
    }
    ParseAndInsertNASCET(g_SelectedText)
}

MenuSmartAdrenal(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        MsgBox('Please select text containing HU values (e.g., "pre-contrast 10 HU, enhanced 80 HU, delayed 40 HU")', "No Selection", 0x40030)
        return
    }
    ParseAndInsertAdrenalWashout(g_SelectedText)
}

MenuSmartFleischner(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        MsgBox("Please select the findings section containing nodule descriptions.", "No Selection", 0x40030)
        return
    }
    ParseAndInsertFleischner(g_SelectedText)
}

MenuQuickSmartParse(ItemName, ItemPos, MyMenu) {
    global g_SelectedText, DefaultSmartParse
    if (g_SelectedText = "") {
        MsgBox("Please select text to parse.", "No Selection", 0x40030)
        return
    }
    SP_Run(PE_ByName(DefaultSmartParse, g_SelectedText))
}

MenuAutoParse(ItemName, ItemPos, MyMenu) {
    global g_SelectedText, ShowBoneAge
    if (ShowBoneAge && RegExMatch(g_SelectedText, "i)bone\s+age")) {
        ShowBoneAgeGui(g_SelectedText)
        return
    }
    if (g_SelectedText = "") {
        MsgBox("Highlight the dictated sentence(s) first, then Shift+Right-click > Smart Parse.", "No Selection", 0x40030)
        return
    }
    ParseAndInsertAuto(g_SelectedText)
}

MenuSmartTIRADS(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        MsgBox("Highlight the thyroid nodule description(s) - or the whole report - first.", "No Selection", 0x40030)
        return
    }
    ParseAndInsertTIRADS(g_SelectedText)
}

MenuSmartORADS(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        MsgBox("Highlight the ovarian cyst description first (size, simple/hemorrhagic/endometrioma/dermoid, menopausal status if known).", "No Selection", 0x40030)
        return
    }
    ParseAndInsertORADS(g_SelectedText)
}

MenuBoneAge(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    ShowBoneAgeGui(g_SelectedText)
}

MenuSmartStenosis(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        ShowStenosisGui()
        return
    }
    ParseAndInsertStenosis(g_SelectedText)
}

MenuSmartICH(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        ShowICHVolumeGui()
        return
    }
    ParseAndInsertICH(g_SelectedText)
}

MenuSmartDate(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText = "") {
        ShowDateCalculatorGui()
        return
    }
    ParseAndInsertDate(g_SelectedText)
}

; GUI-based handlers
MenuEllipsoidVolume(ItemName, ItemPos, MyMenu) {
    ShowEllipsoidVolumeGui()
}

MenuAdrenalWashout(ItemName, ItemPos, MyMenu) {
    ShowAdrenalWashoutGui()
}

MenuNASCET(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    ; Try text parsing first, fall back to GUI
    if (g_SelectedText != "") {
        r := PE_NASCET(g_SelectedText)
        if (r.ok) {
            SP_Run(r)
            return
        }
    }
    ShowNASCETGui()
}

MenuStenosis(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText != "") {
        r := PE_Stenosis(g_SelectedText)
        if (r.ok) {
            SP_Run(r)
            return
        }
    }
    ShowStenosisGui()
}

MenuRVLV(ItemName, ItemPos, MyMenu) {
    ShowRVLVGui()
}

MenuFleischner(ItemName, ItemPos, MyMenu) {
    ShowFleischnerGui()
}

MenuICHVolume(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText != "") {
        ParseAndInsertICH(g_SelectedText)
    } else {
        ShowICHVolumeGui()
    }
}

MenuDateCalc(ItemName, ItemPos, MyMenu) {
    global g_SelectedText
    if (g_SelectedText != "") {
        ParseAndInsertDate(g_SelectedText)
    } else {
        ShowDateCalculatorGui()
    }
}

MenuSectraHistory(ItemName, ItemPos, MyMenu) {
    CopySectraHistory()
}

MenuQuickCall(ItemName, ItemPos, MyMenu) {
    QC_ShowPanel()
}

MenuSettings(ItemName, ItemPos, MyMenu) {
    ShowSettings()
}

; =========================================
; CALCULATOR 1: Ellipsoid Volume
; =========================================
; Global GUI object references for v2
global EllipsoidGuiObj := ""

ShowEllipsoidVolumeGui() {
    global EllipsoidGuiObj
    ; Position near mouse
    GetGuiPosition(&xPos, &yPos)

    EllipsoidGuiObj := Gui("+AlwaysOnTop")
    EllipsoidGuiObj.Title := "Ellipsoid Volume"
    EllipsoidGuiObj.Add("Text", "x10 y10 w280", "Ellipsoid Volume Calculator")
    EllipsoidGuiObj.Add("Text", "x10 y35", "AP (L):")
    EllipsoidGuiObj.Add("Edit", "x80 y32 w50 vEllipDim1")
    EllipsoidGuiObj.Add("Text", "x135 y35", "x   T (W):")
    EllipsoidGuiObj.Add("Edit", "x185 y32 w50 vEllipDim2")
    EllipsoidGuiObj.Add("Text", "x10 y60", "CC (H):")
    EllipsoidGuiObj.Add("Edit", "x80 y57 w50 vEllipDim3")
    EllipsoidGuiObj.Add("Text", "x135 y60", "Units:")
    EllipsoidGuiObj.Add("DropDownList", "x185 y57 w50 vEllipUnits Choose1", ["mm", "cm"])
    EllipsoidGuiObj.Add("Button", "x10 y95 w100", "Calculate").OnEvent("Click", CalcEllipsoid)
    EllipsoidGuiObj.Add("Button", "x120 y95 w80", "Cancel").OnEvent("Click", EllipsoidGuiClose)
    EllipsoidGuiObj.OnEvent("Close", EllipsoidGuiClose)
    EllipsoidGuiObj.Show("x" xPos " y" yPos " w250 h135")
    RA_Front(EllipsoidGuiObj.Hwnd)
}

EllipsoidGuiClose(*) {
    global EllipsoidGuiObj
    if (EllipsoidGuiObj)
        EllipsoidGuiObj.Destroy()
    EllipsoidGuiObj := ""
}

CalcEllipsoid(*) {
    global EllipsoidGuiObj
    saved := EllipsoidGuiObj.Submit(false)

    if (saved.EllipDim1 = "" || saved.EllipDim2 = "" || saved.EllipDim3 = "") {
        MsgBox("Please enter all three dimensions.", "Error", 0x40010)
        return
    }

    d1 := saved.EllipDim1 + 0
    d2 := saved.EllipDim2 + 0
    d3 := saved.EllipDim3 + 0

    if (d1 <= 0 || d2 <= 0 || d3 <= 0) {
        MsgBox("All dimensions must be greater than 0.", "Error", 0x40010)
        return
    }

    ; Convert to cm if input is mm
    if (saved.EllipUnits = "mm") {
        d1 := d1 / 10
        d2 := d2 / 10
        d3 := d3 / 10
    }

    ; Ellipsoid volume formula: (4/3) * pi * (a/2) * (b/2) * (c/2) = 0.5236 * a * b * c
    volume := 0.5236 * d1 * d2 * d3
    volumeRound := Round(volume, 1)

    ; WHY: Sentence style for inline insertion - matches smart parser output
    ; ARCHITECTURE: Leading space for dictation continuity
    ; Format dimensions in display units
    dimStr := saved.EllipDim1 " x " saved.EllipDim2 " x " saved.EllipDim3 " " saved.EllipUnits
    result := " This corresponds to a volume of " volumeRound " cc (" dimStr ")."

    EllipsoidGuiObj.Destroy()
    EllipsoidGuiObj := ""
    ShowResult(result)
}

; =========================================
; CALCULATOR 2: Adrenal Washout
; =========================================
global AdrenalGuiObj := ""

ShowAdrenalWashoutGui() {
    global AdrenalGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    AdrenalGuiObj := Gui("+AlwaysOnTop")
    AdrenalGuiObj.Title := "Adrenal Washout"
    AdrenalGuiObj.Add("Text", "x10 y10 w280", "Adrenal Washout Calculator")
    AdrenalGuiObj.Add("Text", "x10 y40", "Pre-contrast (HU):")
    AdrenalGuiObj.Add("Edit", "x140 y37 w70 vAdrenalPre")
    AdrenalGuiObj.Add("Text", "x10 y70", "Post-contrast (HU):")
    AdrenalGuiObj.Add("Edit", "x140 y67 w70 vAdrenalPost")
    AdrenalGuiObj.Add("Text", "x10 y100", "Delayed (15 min) (HU):")
    AdrenalGuiObj.Add("Edit", "x140 y97 w70 vAdrenalDelayed")
    AdrenalGuiObj.Add("Button", "x10 y135 w90", "Calculate").OnEvent("Click", CalcAdrenal)
    AdrenalGuiObj.Add("Button", "x110 y135 w80", "Cancel").OnEvent("Click", AdrenalGuiClose)
    AdrenalGuiObj.OnEvent("Close", AdrenalGuiClose)
    AdrenalGuiObj.Show("x" xPos " y" yPos " w230 h175")
    RA_Front(AdrenalGuiObj.Hwnd)
}

AdrenalGuiClose(*) {
    global AdrenalGuiObj
    if (AdrenalGuiObj)
        AdrenalGuiObj.Destroy()
    AdrenalGuiObj := ""
}

CalcAdrenal(*) {
    global AdrenalGuiObj, ShowCitations
    saved := AdrenalGuiObj.Submit(false)

    if (saved.AdrenalPre = "" || saved.AdrenalPost = "" || saved.AdrenalDelayed = "") {
        MsgBox("Please enter all three HU values.", "Error", 0x40010)
        return
    }

    pre := saved.AdrenalPre + 0
    post := saved.AdrenalPost + 0
    delayed := saved.AdrenalDelayed + 0

    ; WHY: Sentence style for inline insertion - matches smart parser output
    ; ARCHITECTURE: Leading space for dictation continuity
    result := " Adrenal washout: "

    ; Absolute washout (requires pre-contrast)
    if (post != pre) {
        absWashout := ((post - delayed) / (post - pre)) * 100
        absWashout := Round(absWashout, 1)
        result .= "absolute " absWashout "%"
        if (absWashout >= 60)
            result .= " (likely adenoma)"
        else
            result .= " (indeterminate)"
        result .= ", "
    }

    ; Relative washout (no pre-contrast needed)
    if (post != 0) {
        relWashout := ((post - delayed) / post) * 100
        relWashout := Round(relWashout, 1)
        result .= "relative " relWashout "%"
        if (relWashout >= 40)
            result .= " (likely adenoma)"
        else
            result .= " (indeterminate)"
        result .= "."
    }

    ; Pre-contrast assessment as additional sentence
    if (pre <= 10)
        result .= " Pre-contrast " pre " HU suggests lipid-rich adenoma."

    if (ShowCitations)
        result .= " (Mayo-Smith et al. Radiology 2017)"

    AdrenalGuiObj.Destroy()
    AdrenalGuiObj := ""
    ShowResult(result)
}

; =========================================
; CALCULATOR 3: NASCET Stenosis
; =========================================
global NASCETGuiObj := ""

CalculateNASCETResult(distal, stenosis) {
    global ShowCitations
    distal := distal + 0
    stenosis := stenosis + 0

    if (distal <= 0)
        return ""

    nascetVal := ((distal - stenosis) / distal) * 100
    nascetVal := Round(nascetVal, 1)

    ; WHY: Sentence style for inline insertion - matches smart parser output
    ; ARCHITECTURE: Leading space for dictation continuity
    distalRound := Round(distal, 1)
    stenosisRound := Round(stenosis, 1)

    result := " NASCET: " nascetVal "% stenosis (distal " distalRound "mm, stenosis " stenosisRound "mm), "

    if (nascetVal < 50)
        result .= "mild stenosis."
    else if (nascetVal < 70)
        result .= "moderate stenosis, consider intervention if symptomatic."
    else
        result .= "severe stenosis, strong indication for CEA/CAS."

    if (ShowCitations)
        result .= " (NASCET, NEJM 1991)"

    return result
}

ShowNASCETGui() {
    global NASCETGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    NASCETGuiObj := Gui("+AlwaysOnTop")
    NASCETGuiObj.Title := "NASCET Calculator"
    NASCETGuiObj.Add("Text", "x10 y10 w280", "NASCET Carotid Stenosis Calculator")
    NASCETGuiObj.Add("Text", "x10 y40", "Distal ICA diameter (mm):")
    NASCETGuiObj.Add("Edit", "x160 y37 w60 vNASCETDistal")
    NASCETGuiObj.Add("Text", "x10 y70", "Stenosis diameter (mm):")
    NASCETGuiObj.Add("Edit", "x160 y67 w60 vNASCETStenosis")
    NASCETGuiObj.Add("Button", "x10 y105 w90", "Calculate").OnEvent("Click", CalcNASCETGui)
    NASCETGuiObj.Add("Button", "x110 y105 w80", "Cancel").OnEvent("Click", NASCETGuiClose)
    NASCETGuiObj.OnEvent("Close", NASCETGuiClose)
    NASCETGuiObj.Show("x" xPos " y" yPos " w240 h145")
    RA_Front(NASCETGuiObj.Hwnd)
}

NASCETGuiClose(*) {
    global NASCETGuiObj
    if (NASCETGuiObj)
        NASCETGuiObj.Destroy()
    NASCETGuiObj := ""
}

CalcNASCETGui(*) {
    global NASCETGuiObj
    saved := NASCETGuiObj.Submit(false)

    if (saved.NASCETDistal = "" || saved.NASCETStenosis = "") {
        MsgBox("Please enter both measurements.", "Error", 0x40010)
        return
    }

    distal := saved.NASCETDistal + 0
    stenosis := saved.NASCETStenosis + 0

    if (distal <= 0) {
        MsgBox("Distal ICA must be greater than 0.", "Error", 0x40010)
        return
    }

    if (stenosis >= distal) {
        MsgBox("Stenosis should be less than distal ICA.", "Error", 0x40010)
        return
    }

    result := CalculateNASCETResult(distal, stenosis)
    NASCETGuiObj.Destroy()
    NASCETGuiObj := ""
    ShowResult(result)
}

; -----------------------------------------
; CALCULATOR 3b: General Stenosis Calculator
; NOTE: 90% similar to NASCET calculator above. Consider merging
; into single parameterized function: ShowStenosisGui(preset := "")
; where preset="NASCET" adds ICA-specific labels.
; -----------------------------------------
global StenosisGuiObj := ""

ShowStenosisGui() {
    global StenosisGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    StenosisGuiObj := Gui("+AlwaysOnTop")
    StenosisGuiObj.Title := "Stenosis Calculator"
    StenosisGuiObj.Add("Text", "x10 y10 w280", "Vessel Stenosis Calculator")
    StenosisGuiObj.Add("Text", "x10 y35", "Vessel (optional):")
    StenosisGuiObj.Add("Edit", "x120 y32 w130 vStenosisVessel")
    StenosisGuiObj.Add("Text", "x10 y65", "Normal diameter (mm):")
    StenosisGuiObj.Add("Edit", "x140 y62 w60 vStenosisNormal")
    StenosisGuiObj.Add("Text", "x10 y95", "Stenosis diameter (mm):")
    StenosisGuiObj.Add("Edit", "x140 y92 w60 vStenosisMeasure")
    StenosisGuiObj.Add("Button", "x10 y130 w90", "Calculate").OnEvent("Click", CalcStenosis)
    StenosisGuiObj.Add("Button", "x110 y130 w80", "Cancel").OnEvent("Click", StenosisGuiClose)
    StenosisGuiObj.OnEvent("Close", StenosisGuiClose)
    StenosisGuiObj.Show("x" xPos " y" yPos " w270 h170")
    RA_Front(StenosisGuiObj.Hwnd)
}

StenosisGuiClose(*) {
    global StenosisGuiObj
    if (StenosisGuiObj)
        StenosisGuiObj.Destroy()
    StenosisGuiObj := ""
}

CalcStenosis(*) {
    global StenosisGuiObj, ShowCitations
    saved := StenosisGuiObj.Submit(false)

    if (saved.StenosisNormal = "" || saved.StenosisMeasure = "") {
        MsgBox("Please enter both diameter measurements.", "Error", 0x40010)
        return
    }

    normal := saved.StenosisNormal + 0
    stenosis := saved.StenosisMeasure + 0

    if (normal <= 0) {
        MsgBox("Normal diameter must be greater than 0.", "Error", 0x40010)
        return
    }

    if (stenosis >= normal) {
        MsgBox("Stenosis should be less than normal diameter.", "Error", 0x40010)
        return
    }

    ; Calculate percent stenosis
    stenosisPercent := ((normal - stenosis) / normal) * 100
    stenosisPercent := Round(stenosisPercent, 1)

    vesselName := saved.StenosisVessel != "" ? saved.StenosisVessel : "Vessel"

    ; WHY: Sentence style for inline insertion - leading space for dictation continuity
    ; ARCHITECTURE: Matches NASCET parser output format for consistency
    normalRound := Round(normal, 1)
    stenosisRound := Round(stenosis, 1)

    ; Build severity interpretation
    if (stenosisPercent < 50)
        severity := "mild stenosis"
    else if (stenosisPercent < 70)
        severity := "moderate stenosis"
    else
        severity := "severe stenosis"

    ; Sentence format: " Stenosis: X% (normal Ymm, stenosis Zmm), severity."
    result := " " vesselName " stenosis: " stenosisPercent "% (normal " normalRound "mm, stenosis " stenosisRound "mm), " severity "."

    StenosisGuiObj.Destroy()
    StenosisGuiObj := ""
    ShowResult(result)
}

; =========================================
; CALCULATOR 4: RV/LV Ratio
; =========================================
global RVLVGuiObj := ""

ShowRVLVGui() {
    global RVLVGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    RVLVGuiObj := Gui("+AlwaysOnTop")
    RVLVGuiObj.Title := "RV/LV Ratio"
    RVLVGuiObj.Add("Text", "x10 y10 w280", "RV/LV Ratio Calculator (4-chamber axial)")
    RVLVGuiObj.Add("Text", "x10 y40", "RV diameter (mm):")
    RVLVGuiObj.Add("Edit", "x130 y37 w60 vRVDiam")
    RVLVGuiObj.Add("Text", "x10 y70", "LV diameter (mm):")
    RVLVGuiObj.Add("Edit", "x130 y67 w60 vLVDiam")
    RVLVGuiObj.Add("Button", "x10 y105 w90", "Calculate").OnEvent("Click", CalcRVLV)
    RVLVGuiObj.Add("Button", "x110 y105 w80", "Cancel").OnEvent("Click", RVLVGuiClose)
    RVLVGuiObj.OnEvent("Close", RVLVGuiClose)
    RVLVGuiObj.Show("x" xPos " y" yPos " w220 h145")
    RA_Front(RVLVGuiObj.Hwnd)
}

RVLVGuiClose(*) {
    global RVLVGuiObj
    if (RVLVGuiObj)
        RVLVGuiObj.Destroy()
    RVLVGuiObj := ""
}

CalcRVLV(*) {
    global RVLVGuiObj, ShowCitations
    saved := RVLVGuiObj.Submit(false)

    if (saved.RVDiam = "" || saved.LVDiam = "") {
        MsgBox("Please enter both RV and LV diameters.", "Error", 0x40010)
        return
    }

    rv := saved.RVDiam + 0
    lv := saved.LVDiam + 0

    if (lv <= 0) {
        MsgBox("LV diameter must be greater than 0.", "Error", 0x40010)
        return
    }

    ratio := rv / lv
    ratio := Round(ratio, 2)

    ; WHY: Sentence style for inline insertion - matches smart parser output
    ; ARCHITECTURE: Leading space for dictation continuity
    rvRound := Round(rv, 1)
    lvRound := Round(lv, 1)

    ; Same objective wording as the smart parser (see PE_RVLVInterp)
    result := " RV/LV ratio: " PE_Fmt(ratio, 2) " (RV " rvRound "mm, LV " lvRound "mm). " PE_RVLVInterp(ratio)

    if (ShowCitations)
        result .= " (Meinel et al. Radiology 2015)"

    RVLVGuiObj.Destroy()
    RVLVGuiObj := ""
    ShowResult(result)
}

; =========================================
; CALCULATOR 5: Fleischner 2017
; =========================================
global FleischnerGuiObj := ""

ShowFleischnerGui() {
    global FleischnerGuiObj, IncludeDatamining
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    FleischnerGuiObj := Gui("+AlwaysOnTop")
    FleischnerGuiObj.Title := "Fleischner 2017"
    FleischnerGuiObj.Add("Text", "x10 y10 w300", "Fleischner 2017 - Incidental Pulmonary Nodule")
    FleischnerGuiObj.Add("Text", "x10 y40", "Nodule size (mm):")
    FleischnerGuiObj.Add("Edit", "x130 y37 w60 vFleischSize")
    FleischnerGuiObj.Add("Text", "x10 y70", "Nodule type:")
    FleischnerGuiObj.Add("DropDownList", "x130 y67 w120 vFleischType Choose1", ["Solid", "Part-solid", "Ground glass"])
    FleischnerGuiObj.Add("Text", "x10 y100", "Number:")
    FleischnerGuiObj.Add("DropDownList", "x130 y97 w120 vFleischNumber Choose1", ["Single", "Multiple"])
    FleischnerGuiObj.Add("Text", "x10 y130", "Risk:")
    FleischnerGuiObj.Add("DropDownList", "x130 y127 w120 vFleischRisk Choose1", ["Low and High risk", "Low risk", "High risk"])
    dmChecked := IncludeDatamining ? "Checked" : ""
    FleischnerGuiObj.Add("Checkbox", "x10 y160 w250 vFleischDatamine " dmChecked, "Include datamining phrase (SSM lung nodule)")
    FleischnerGuiObj.Add("Button", "x10 y190 w100", "Get Recommendation").OnEvent("Click", CalcFleischner)
    FleischnerGuiObj.Add("Button", "x120 y190 w80", "Cancel").OnEvent("Click", FleischnerGuiClose)
    FleischnerGuiObj.OnEvent("Close", FleischnerGuiClose)
    FleischnerGuiObj.Show("x" xPos " y" yPos " w280 h230")
    RA_Front(FleischnerGuiObj.Hwnd)
}

FleischnerGuiClose(*) {
    global FleischnerGuiObj
    if (FleischnerGuiObj)
        FleischnerGuiObj.Destroy()
    FleischnerGuiObj := ""
}

CalcFleischner(*) {
    global FleischnerGuiObj, DataminingPhrase, ShowCitations
    saved := FleischnerGuiObj.Submit(false)

    if (saved.FleischSize = "") {
        MsgBox("Please enter nodule size.", "Error", 0x40010)
        return
    }

    size := saved.FleischSize + 0
    risk := saved.FleischRisk
    result := "Fleischner 2017 Recommendation:`n"
    result .= "Size: " size " mm | " saved.FleischType " | " saved.FleischNumber "`n`n"

    ; WHY: Risk is usually not known at reading time - give both by default
    if (risk = "Low risk" || risk = "High risk") {
        result .= StrUpper(risk) " recommendation:`n"
        result .= GetFleischnerRecommendation(size, saved.FleischType, saved.FleischNumber, risk)
    } else {
        result .= "LOW RISK recommendation:`n"
        result .= GetFleischnerRecommendation(size, saved.FleischType, saved.FleischNumber, "Low risk")
        result .= "`n`nHIGH RISK recommendation:`n"
        result .= GetFleischnerRecommendation(size, saved.FleischType, saved.FleischNumber, "High risk")
    }

    if (saved.FleischDatamine) {
        result .= "`n`n[" DataminingPhrase "]"
    }

    if (ShowCitations)
        result .= "`n`nRef: MacMahon H et al. Radiology 2017;284:228-243"

    FleischnerGuiObj.Destroy()
    FleischnerGuiObj := ""
    ShowResult(result)
}

GetFleischnerRecommendation(size, type, number, risk) {
    ; Solid nodules
    if (type = "Solid") {
        if (number = "Single") {
            if (size < 6) {
                return "No routine follow-up recommended.`n(Optional CT at 12 months if high-risk)"
            } else if (size < 8) {
                if (risk = "Low risk")
                    return "CT at 6-12 months, then consider CT at 18-24 months."
                else
                    return "CT at 6-12 months, then CT at 18-24 months."
            } else {
                return "Consider CT at 3 months, PET/CT, or tissue sampling."
            }
        } else {  ; Multiple
            if (size < 6) {
                return "No routine follow-up recommended.`n(Optional CT at 12 months if high-risk)"
            } else {
                if (risk = "Low risk")
                    return "CT at 3-6 months, then consider CT at 18-24 months."
                else
                    return "CT at 3-6 months, then CT at 18-24 months."
            }
        }
    }
    ; Part-solid nodules
    else if (type = "Part-solid") {
        if (number = "Single") {
            if (size < 6) {
                return "No routine follow-up recommended."
            } else {
                return "CT at 3-6 months. If stable, annual CT for 5 years.`nIf solid component >=6 mm, consider PET/CT or biopsy."
            }
        } else {
            return "CT at 3-6 months. If stable, annual CT for 5 years."
        }
    }
    ; Ground glass nodules
    else if (type = "Ground glass") {
        if (number = "Single") {
            if (size < 6) {
                return "No routine follow-up recommended."
            } else {
                return "CT at 6-12 months, then every 2 years for 5 years."
            }
        } else {
            return "CT at 3-6 months. If stable, consider CT at 2 and 4 years."
        }
    }
    return "Unable to determine recommendation."
}

; =========================================
; PRE-FILLED GUI FUNCTIONS
; WHY: Allow user to edit parsed values in GUI when confidence is low
; =========================================

ShowEllipsoidVolumeGuiPrefilled(d1, d2, d3) {
    global EllipsoidGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    ; Pre-fill values (convert to string)
    dim1 := Round(d1, 2)
    dim2 := Round(d2, 2)
    dim3 := Round(d3, 2)

    EllipsoidGuiObj := Gui("+AlwaysOnTop")
    EllipsoidGuiObj.Title := "Ellipsoid Volume"
    EllipsoidGuiObj.Add("Text", "x10 y10 w280", "Ellipsoid Volume Calculator (Pre-filled)")
    EllipsoidGuiObj.Add("Text", "x10 y35", "AP (L):")
    EllipsoidGuiObj.Add("Edit", "x80 y32 w50 vEllipDim1", dim1)
    EllipsoidGuiObj.Add("Text", "x135 y35", "x   T (W):")
    EllipsoidGuiObj.Add("Edit", "x185 y32 w50 vEllipDim2", dim2)
    EllipsoidGuiObj.Add("Text", "x10 y60", "CC (H):")
    EllipsoidGuiObj.Add("Edit", "x80 y57 w50 vEllipDim3", dim3)
    EllipsoidGuiObj.Add("Text", "x135 y60", "Units:")
    EllipsoidGuiObj.Add("DropDownList", "x185 y57 w50 vEllipUnits Choose2", ["mm", "cm"])
    EllipsoidGuiObj.Add("Button", "x10 y95 w100", "Calculate").OnEvent("Click", CalcEllipsoid)
    EllipsoidGuiObj.Add("Button", "x120 y95 w80", "Cancel").OnEvent("Click", EllipsoidGuiClose)
    EllipsoidGuiObj.OnEvent("Close", EllipsoidGuiClose)
    EllipsoidGuiObj.Show("x" xPos " y" yPos " w250 h135")
    RA_Front(EllipsoidGuiObj.Hwnd)
}

ShowRVLVGuiPrefilled(rv, lv) {
    global RVLVGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    rvVal := Round(rv, 1)
    lvVal := Round(lv, 1)

    RVLVGuiObj := Gui("+AlwaysOnTop")
    RVLVGuiObj.Title := "RV/LV Ratio"
    RVLVGuiObj.Add("Text", "x10 y10 w280", "RV/LV Ratio Calculator (Pre-filled)")
    RVLVGuiObj.Add("Text", "x10 y40", "RV diameter (mm):")
    RVLVGuiObj.Add("Edit", "x130 y37 w60 vRVDiam", rvVal)
    RVLVGuiObj.Add("Text", "x10 y70", "LV diameter (mm):")
    RVLVGuiObj.Add("Edit", "x130 y67 w60 vLVDiam", lvVal)
    RVLVGuiObj.Add("Button", "x10 y105 w90", "Calculate").OnEvent("Click", CalcRVLV)
    RVLVGuiObj.Add("Button", "x110 y105 w80", "Cancel").OnEvent("Click", RVLVGuiClose)
    RVLVGuiObj.OnEvent("Close", RVLVGuiClose)
    RVLVGuiObj.Show("x" xPos " y" yPos " w220 h145")
    RA_Front(RVLVGuiObj.Hwnd)
}

ShowNASCETGuiPrefilled(distal, stenosis) {
    global NASCETGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    distalVal := Round(distal, 1)
    stenosisVal := Round(stenosis, 1)

    NASCETGuiObj := Gui("+AlwaysOnTop")
    NASCETGuiObj.Title := "NASCET Calculator"
    NASCETGuiObj.Add("Text", "x10 y10 w280", "NASCET Calculator (Pre-filled)")
    NASCETGuiObj.Add("Text", "x10 y40", "Distal ICA diameter (mm):")
    NASCETGuiObj.Add("Edit", "x160 y37 w60 vNASCETDistal", distalVal)
    NASCETGuiObj.Add("Text", "x10 y70", "Stenosis diameter (mm):")
    NASCETGuiObj.Add("Edit", "x160 y67 w60 vNASCETStenosis", stenosisVal)
    NASCETGuiObj.Add("Button", "x10 y105 w90", "Calculate").OnEvent("Click", CalcNASCETGui)
    NASCETGuiObj.Add("Button", "x110 y105 w80", "Cancel").OnEvent("Click", NASCETGuiClose)
    NASCETGuiObj.OnEvent("Close", NASCETGuiClose)
    NASCETGuiObj.Show("x" xPos " y" yPos " w240 h145")
    RA_Front(NASCETGuiObj.Hwnd)
}

ShowAdrenalWashoutGuiPrefilled(pre, post, delayed) {
    global AdrenalGuiObj
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    preVal := (pre != "") ? Round(pre, 0) : ""
    postVal := Round(post, 0)
    delayedVal := Round(delayed, 0)

    AdrenalGuiObj := Gui("+AlwaysOnTop")
    AdrenalGuiObj.Title := "Adrenal Washout"
    AdrenalGuiObj.Add("Text", "x10 y10 w280", "Adrenal Washout Calculator (Pre-filled)")
    AdrenalGuiObj.Add("Text", "x10 y40", "Pre-contrast (HU):")
    AdrenalGuiObj.Add("Edit", "x140 y37 w70 vAdrenalPre", preVal)
    AdrenalGuiObj.Add("Text", "x10 y70", "Post-contrast (HU):")
    AdrenalGuiObj.Add("Edit", "x140 y67 w70 vAdrenalPost", postVal)
    AdrenalGuiObj.Add("Text", "x10 y100", "Delayed (15 min) (HU):")
    AdrenalGuiObj.Add("Edit", "x140 y97 w70 vAdrenalDelayed", delayedVal)
    AdrenalGuiObj.Add("Button", "x10 y135 w90", "Calculate").OnEvent("Click", CalcAdrenal)
    AdrenalGuiObj.Add("Button", "x110 y135 w80", "Cancel").OnEvent("Click", AdrenalGuiClose)
    AdrenalGuiObj.OnEvent("Close", AdrenalGuiClose)
    AdrenalGuiObj.Show("x" xPos " y" yPos " w230 h175")
    RA_Front(AdrenalGuiObj.Hwnd)
}

ShowFleischnerGuiPrefilled(size, nodeType, number) {
    global FleischnerGuiObj, IncludeDatamining
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    sizeVal := Round(size, 0)

    ; Determine dropdown selection for type
    typeSelect := 1
    if (InStr(nodeType, "Part") || InStr(nodeType, "part"))
        typeSelect := 2
    else if (InStr(nodeType, "Ground") || InStr(nodeType, "glass") || InStr(nodeType, "GGN"))
        typeSelect := 3

    ; Determine dropdown selection for number
    numberSelect := (number = "Multiple") ? 2 : 1

    FleischnerGuiObj := Gui("+AlwaysOnTop")
    FleischnerGuiObj.Title := "Fleischner 2017"
    FleischnerGuiObj.Add("Text", "x10 y10 w300", "Fleischner 2017 (Pre-filled)")
    FleischnerGuiObj.Add("Text", "x10 y40", "Nodule size (mm):")
    FleischnerGuiObj.Add("Edit", "x130 y37 w60 vFleischSize", sizeVal)
    FleischnerGuiObj.Add("Text", "x10 y70", "Nodule type:")
    FleischnerGuiObj.Add("DropDownList", "x130 y67 w120 vFleischType Choose" typeSelect, ["Solid", "Part-solid", "Ground glass"])
    FleischnerGuiObj.Add("Text", "x10 y100", "Number:")
    FleischnerGuiObj.Add("DropDownList", "x130 y97 w120 vFleischNumber Choose" numberSelect, ["Single", "Multiple"])
    FleischnerGuiObj.Add("Text", "x10 y130", "Risk:")
    FleischnerGuiObj.Add("DropDownList", "x130 y127 w120 vFleischRisk Choose1", ["Low and High risk", "Low risk", "High risk"])
    dmChecked := IncludeDatamining ? "Checked" : ""
    FleischnerGuiObj.Add("Checkbox", "x10 y160 w250 vFleischDatamine " dmChecked, "Include datamining phrase")
    FleischnerGuiObj.Add("Button", "x10 y190 w100", "Get Recommendation").OnEvent("Click", CalcFleischner)
    FleischnerGuiObj.Add("Button", "x120 y190 w80", "Cancel").OnEvent("Click", FleischnerGuiClose)
    FleischnerGuiObj.OnEvent("Close", FleischnerGuiClose)
    FleischnerGuiObj.Show("x" xPos " y" yPos " w280 h230")
    RA_Front(FleischnerGuiObj.Hwnd)
}

; -----------------------------------------
; Utility: Get mouse position for GUI placement
; WHY: Reduces code duplication across 15+ GUI functions
; -----------------------------------------
GetGuiPosition(&xPos, &yPos, offset := 10) {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + offset
    yPos := mouseY + offset
}

; =========================================
; SMART PARSE FUNCTIONS
; WHY: Parse dictated text and insert calculations inline without GUI re-entry.
; ARCHITECTURE: Text parsing with regex, calculation, and clipboard-based insertion.
; =========================================

; -----------------------------------------
; Utility: Paste text while preserving clipboard
; WHY: Reduces duplication and ensures clipboard is always restored
; TRADEOFF: Slight overhead for save/restore, but safer
; -----------------------------------------
; WHY waitMs = 700: Windows 11 Notepad and PowerScribe read the clipboard
;      asynchronously; restoring it after only 100 ms made them paste the OLD
;      clipboard (or nothing).
PasteTextPreserveClipboard(text, waitMs := 700) {
    ClipSaved := ClipboardAll()
    A_Clipboard := ""
    A_Clipboard := text
    ClipWait(1)
    Send("{Shift up}{Ctrl up}^v")
    Sleep(waitMs)
    A_Clipboard := ClipSaved
}

; -----------------------------------------
; Utility: Insert text after current selection
; WHY: Preserves original text and appends calculation result.
; -----------------------------------------
InsertAfterSelection(textToInsert) {
    ; Move cursor to end of selection and insert text
    Send("{Right}")
    Sleep(50)

    ; Use helper to paste text while preserving clipboard
    PasteTextPreserveClipboard(textToInsert)

    ToolTip("Calculation inserted!")
    SetTimer(RemoveToolTip, -1500)
}

; -----------------------------------------
; Utility: Insert text at the end of the report (end of the IMPRESSION)
; WHY: Fleischner recommendations belong after the impression
; NOTE: Turn off in Settings to insert right after the highlighted text instead
; -----------------------------------------
InsertAtImpression(textToInsert) {
    ; WHY: The old version selected/copied the whole report and drove the editor's
    ;      Find dialog (Ctrl+F), which differs between PowerScribe and Notepad and
    ;      often pasted nowhere. The IMPRESSION is the last section of the report,
    ;      so the end of the document is the end of the impression.
    ; BONUS: The full report is never copied to the clipboard (PHI).
    Send("^{End}")
    Sleep(80)
    PasteTextPreserveClipboard(textToInsert)
    ToolTip("Inserted at end of report (after IMPRESSION)")
    SetTimer(RemoveToolTip, -2000)
}

; -----------------------------------------
; Utility: Filter out non-measurement numbers
; WHY: Prevents picking up image numbers (23/75), slice numbers, etc.
; TRADEOFF: May occasionally filter legitimate measurements, but safety > convenience
; -----------------------------------------
FilterNonMeasurements(input) {
    filtered := input

    ; Remove image/slice references: (image 23/75), (I23), slice 45, series 3
    filtered := RegExReplace(filtered, "i)\(\s*(?:image|img|i|slice|ser|seq)\s*\d+\s*/\s*\d+\s*\)", "")
    filtered := RegExReplace(filtered, "i)(?:image|img|slice|series|seq|level)\s*[:=#]?\s*\d+(?:\s*/\s*\d+)?", "")

    ; Remove window/level settings: W:400 L:40, WW/WL
    ; WHY: Case-sensitive and requires ":" or "=" so words ending in w/l keep their numbers
    filtered := RegExReplace(filtered, "\b(?:W|L|WW|WL)\s*[:=]\s*-?\d+", "")

    ; Remove dates: 1/15/2024, 2024-01-15
    filtered := RegExReplace(filtered, "\d{1,2}/\d{1,2}/\d{2,4}", "")
    filtered := RegExReplace(filtered, "\d{4}-\d{1,2}-\d{1,2}", "")

    ; Remove page numbers: page 3 of 10, 3/10
    filtered := RegExReplace(filtered, "i)page\s*\d+\s*(?:of|/)\s*\d+", "")

    ; Remove accession/MRN patterns: ACC# 123456, MRN: 123456
    filtered := RegExReplace(filtered, "i)(?:ACC|MRN|ID)\s*#?\s*:?\s*\d+", "")

    return filtered
}

; -----------------------------------------
; Utility: Show confirmation dialog before inserting parsed result
; WHY: User verification prevents wrong insertions
; RETURNS: "insert", "edit", or "cancel"
; -----------------------------------------
global ConfirmGuiObj := ""

ShowParseConfirmation(parseType, parsedValues, calculatedResult, confidence) {
    global SmartParseFallbackToGUI, g_ParsedResultText, ConfirmGuiObj, DarkTheme
    Critical()      ; build and show the dialog before any button click can run

    g_ParsedResultText := calculatedResult

    ; parsedValues: Array of [label, value] pairs (keeps display order) or a Map
    displayText := ""
    if (Type(parsedValues) = "Array") {
        for pair in parsedValues
            displayText .= pair[1] ": " pair[2] "`r`n"
    } else {
        for key, val in parsedValues
            displayText .= key ": " val "`r`n"
    }
    if (confidence < 50)
        conf := "[!] LOW CONFIDENCE - check the values"
    else if (confidence < 80)
        conf := "[~] Medium confidence"
    else
        conf := "[OK] High confidence"

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)

    if (ConfirmGuiObj != "")
        RA_CloseConfirm()

    ConfirmGuiObj := Gui("+AlwaysOnTop -MinimizeBox", "Confirm " parseType)
    ConfirmGuiObj.SetFont("s10", "Segoe UI")
    ConfirmGuiObj.OnEvent("Close", ConfirmGuiClose)
    ConfirmGuiObj.OnEvent("Escape", ConfirmGuiClose)
    ConfirmGuiObj.SetFont("s10 bold")
    ConfirmGuiObj.Add("Text", "x10 y10 w440", parseType)
    ConfirmGuiObj.SetFont("s10 norm")
    ConfirmGuiObj.Add("Text", "x10 y+6 w440", "Found:")
    ConfirmGuiObj.SetFont("s10 bold c" (DarkTheme ? "9CDCFE" : "1F4E79"))
    tFound := ConfirmGuiObj.Add("Text", "x20 y+2 w430", Trim(displayText, "`r`n"))
    RA_ThemeKeep[tFound.Hwnd] := true
    ConfirmGuiObj.SetFont("s10 norm cDefault")
    ConfirmGuiObj.Add("Text", "x10 y+8 w440", "Will insert:")
    lines := StrSplit(Trim(calculatedResult, "`r`n "), "`n").Length
    ePreview := ConfirmGuiObj.Add("Edit", "x10 y+2 w440 r" Min(14, Max(2, lines + 1)) " ReadOnly", Trim(StrReplace(calculatedResult, "`n", "`r`n"), "`r`n "))
    tConf := ConfirmGuiObj.Add("Text", "x10 y+8 w440 c" (DarkTheme ? (confidence < 50 ? "FF7070" : confidence < 80 ? "FFC060" : "70E070") : (confidence < 50 ? "C00000" : confidence < 80 ? "A06000" : "008000")), conf)
    RA_ThemeKeep[tConf.Hwnd] := true

    lowConf := (confidence < 50 && SmartParseFallbackToGUI)
    btnIns := ConfirmGuiObj.Add("Button", "x10 y+10 w130" (lowConf ? "" : " Default"), lowConf ? "Insert Anyway" : "Insert")
    btnIns.OnEvent("Click", ConfirmInsert)
    btnEdit := ConfirmGuiObj.Add("Button", "x+10 yp w130" (lowConf ? " Default" : ""), "Edit in GUI")
    btnEdit.OnEvent("Click", ConfirmEdit)
    global g_SPResult
    if !(IsObject(g_SPResult) && g_SPResult.edit)
        btnEdit.Enabled := false          ; no calculator window for this result (TI-RADS, O-RADS)
    ConfirmGuiObj.Add("Button", "x+10 yp w130", "Cancel").OnEvent("Click", ConfirmCancel)

    ConfirmGuiObj.Show("x" (mouseX + 10) " y" (mouseY + 10) " AutoSize")

    ; WHY: PowerScribe/Sectra windows can sit above normal always-on-top windows.
    ;      Force the dialog to the front now and keep it there while it is open.
    ; NOTE: Non-blocking - the buttons do the work, so Shift+Right-click keeps working.
    hConfirm := ConfirmGuiObj.Hwnd
    try SendMessage(0x115, 6, 0, ePreview)    ; preview scrolled to the top
    RA_Front(hConfirm)
    try (lowConf ? btnEdit : btnIns).Focus()  ; Enter = default action, preview text not selected
    ; Windows sometimes refuses the first activation; try again shortly after
    SetTimer(RA_FrontIfNotActive.Bind(hConfirm), -150)
    SetTimer(RA_FrontIfNotActive.Bind(hConfirm), -600)
    SetTimer(RA_KeepConfirmFront, 300)
    Critical("Off")
}

; Keep the confirmation dialog above other apps' windows while it is open
RA_KeepConfirmFront() {
    global ConfirmGuiObj
    try {
        if !IsObject(ConfirmGuiObj) {
            SetTimer(RA_KeepConfirmFront, 0)
            return
        }
        h := ConfirmGuiObj.Hwnd
        if !WinExist("ahk_id " h) {
            SetTimer(RA_KeepConfirmFront, 0)
            return
        }
        if QC_IsObscured(h)
            QC_RaiseTop(h)
    } catch {
        SetTimer(RA_KeepConfirmFront, 0)
    }
}

; Bring one of our windows to the very front and give it the keyboard focus.
; WHY: Windows blocks focus stealing; briefly attaching to the foreground
;      window's input thread is the standard way to be allowed to activate.
RA_FrontIfNotActive(hwnd) {
    try {
        if (WinExist("ahk_id " hwnd) && !WinActive("ahk_id " hwnd))
            RA_Front(hwnd)
    }
}

; Move a window so it is completely visible on the monitor under the mouse
; WHY: Popups open at the mouse; on multi-monitor / scaled displays they could
;      land partly or fully off-screen ("can't see it even after Alt+Tab").
RA_FitOnMouseMonitor(hwnd) {
    try {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        l := 0, t := 0, r := A_ScreenWidth, b := A_ScreenHeight
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if (mx >= ml && mx < mr && my >= mt && my < mb)
                l := ml, t := mt, r := mr, b := mb
        }
        nx := Max(l, Min(x, r - w)), ny := Max(t, Min(y, b - h))
        if (nx != x || ny != y)
            WinMove(nx, ny, , , "ahk_id " hwnd)
    }
}

; Dark context menus (Shift+Right-click menu): Windows 10 1903+/11 draw an app's
; popup menus dark with light text once it opts in (uxtheme ordinals 135/136).
RA_SetDarkMenus(on) {
    static last := ""
    if (last = on)
        return
    last := on
    hMod := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr") || DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
    setMode := DllCall("GetProcAddress", "Ptr", hMod, "Ptr", 135, "Ptr")     ; SetPreferredAppMode
    flush := DllCall("GetProcAddress", "Ptr", hMod, "Ptr", 136, "Ptr")       ; FlushMenuThemes
    if setMode
        DllCall(setMode, "Int", on ? 2 : 3)      ; 2 = force dark, 3 = force light
    if flush
        DllCall(flush)
}

; Dark theme for a RadAssist window (Settings > Appearance > Dark theme)
RA_ApplyTheme(hwnd) {
    global DarkTheme, RA_ThemeKeep
    if !DarkTheme
        return
    try g := GuiFromHwnd(hwnd)
    catch
        return
    if !IsObject(g) || hwnd = (IsSet(QC_Gui) && IsObject(QC_Gui) ? QC_Gui.Hwnd : 0)
        return
    g.BackColor := "1E1E1E"
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 20, "Int*", 1, "Int", 4)   ; dark title bar (Win10 20H1+/Win11)
    for ctrl in g {
        try {
            switch ctrl.Type {
                case "Edit", "ComboBox", "DDL", "ListBox":
                    ctrl.Opt("Background2D2D2D")
                    ctrl.SetFont("cE6E6E6")
                case "Button":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                case "CheckBox", "Radio":
                    ctrl.Opt("-Theme")            ; themed checkboxes ignore text color
                    ctrl.SetFont("cE6E6E6")
                case "GroupBox":
                    ; Group box titles stay black even unthemed: draw the title as a Text label
                    if (ctrl.Text != "") {
                        title := ctrl.Text
                        ctrl.GetPos(&gx, &gy)
                        ctrl.Text := ""
                        g.SetFont("cE6E6E6")
                        g.Add("Text", "x" (gx + 8) " y" (gy - 1) " Background1E1E1E", " " title " ")
                    }
                case "Text", "Link":
                    if !RA_ThemeKeep.Has(ctrl.Hwnd)
                        ctrl.SetFont("cE6E6E6")
            }
        }
    }
    DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
}

RA_Front(hwnd) {
    RA_ApplyTheme(hwnd)
    RA_FitOnMouseMonitor(hwnd)
    try {
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -2, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        fg := DllCall("GetForegroundWindow", "Ptr")
        fgThread := fg ? DllCall("GetWindowThreadProcessId", "Ptr", fg, "Ptr", 0, "UInt") : 0
        myThread := DllCall("GetCurrentThreadId", "UInt")
        attached := (fgThread && fgThread != myThread) ? DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", 1) : 0
        DllCall("BringWindowToTop", "Ptr", hwnd)
        DllCall("SetForegroundWindow", "Ptr", hwnd)
        if attached
            DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", 0)
        WinActivate("ahk_id " hwnd)
    }
}

; Re-activate the report window the user Shift+Right-clicked in, before pasting
RA_ActivateTarget() {
    global g_TargetHwnd
    t := g_TargetHwnd
    if (!t || !WinExist("ahk_id " t))
        return
    if WinActive("ahk_id " t)          ; usually already active once our dialog closes
        return
    ; Fast path: hand focus straight back (allowed because we own the foreground)
    try {
        fg := DllCall("GetForegroundWindow", "Ptr")
        fgThread := fg ? DllCall("GetWindowThreadProcessId", "Ptr", fg, "Ptr", 0, "UInt") : 0
        myThread := DllCall("GetCurrentThreadId", "UInt")
        attached := (fgThread && fgThread != myThread) ? DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", 1) : 0
        DllCall("SetForegroundWindow", "Ptr", t)
        if attached
            DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", 0)
    }
    if !WinWaitActive("ahk_id " t, , 0.4) {
        WinActivate("ahk_id " t)
        WinWaitActive("ahk_id " t, , 0.6)
    }
    Sleep(50)
}

RA_CloseConfirm() {
    global ConfirmGuiObj
    SetTimer(RA_KeepConfirmFront, 0)
    try ConfirmGuiObj.Destroy()
    ConfirmGuiObj := ""
}

ConfirmInsert(*) {
    global g_SPResult
    Critical()      ; finish the paste before another Shift+Right-click can start
    r := g_SPResult
    SetTimer(RA_KeepConfirmFront, 0)
    if !IsObject(r) {
        RA_CloseConfirm()
        return
    }
    ; WHY: Hand focus back to the report window BEFORE closing the dialog. If the
    ;      dialog closes first, Windows activates the next window in line - often
    ;      the always-on-top Quick Call panel - and the paste goes nowhere.
    RA_ActivateTarget()
    try ConfirmGuiObj.Hide()
    if r.atImpression
        InsertAtImpression(r.text)
    else
        InsertAfterSelection(r.text)
    RA_CloseConfirm()
}

ConfirmEdit(*) {
    global g_SPResult
    Critical()
    r := g_SPResult
    RA_CloseConfirm()
    if (IsObject(r) && r.edit)
        r.edit.Call()
}

ConfirmCancel(*) {
    RA_CloseConfirm()
}

ConfirmGuiClose(*) {
    RA_CloseConfirm()
}

; =========================================
; SMART PARSE ENGINE
; WHY: One set of tolerant parsers for real dictation. Each PE_* function is pure:
;      it takes the selected text and returns a result object, so it can be tested
;      without any GUI. SP_Run() shows the confirmation dialog and inserts.
; UNITS: Every number keeps its own unit (cm or mm, mixed freely in one sentence);
;        numbers without units fall back to a sensible guess / DefaultMeasurementUnit.
; RESULT: {ok, title, values: [[label, value], ...], text, conf, edit, atImpression}
;         or {ok: false, err}
; =========================================

; Number not glued to a preceding digit/decimal point (avoids "4.5" -> "5")
global PE_N := "(?<![\d.])(\d+(?:\.\d+)?|\.\d+)"
global PE_U := "(mm|cm|millimeters?|centimeters?|millimetres?|centimetres?)"

PE_Fail(msg) => {ok: false, err: msg}

PE_Ok(title, values, text, conf, edit := "", atImpression := false) {
    return {ok: true, title: title, values: values, text: text, conf: conf, edit: edit, atImpression: atImpression}
}

; Normalize the selection: one line, plain "x", no image/series/date numbers
PE_Clean(text) {
    t := RegExReplace(text, "\R", " ")
    t := StrReplace(t, Chr(0xD7), "x")          ; multiplication sign
    t := RegExReplace(t, "\s+", " ")
    return FilterNonMeasurements(t)
}

PE_Unit(u) {
    if (u = "")
        return ""
    return (SubStr(StrLower(u), 1, 1) = "c") ? "cm" : "mm"
}

PE_ToMm(v, u) => (u = "cm") ? v * 10 : v
PE_ToCm(v, u) => (u = "mm") ? v / 10 : v

; Round and drop trailing zeros: 32.0 -> 32, 4.50 -> 4.5
PE_Fmt(v, dec := 1) {
    s := String(Round(v, dec))
    if InStr(s, ".")
        s := RTrim(RTrim(s, "0"), ".")
    return s
}

; First "N (unit)" in s; skips percentages and things like "15-minute"
PE_FirstValue(s) {
    if RegExMatch(s, "i)" PE_N "\s*-?\s*" PE_U "?(?!\d|\.\d|\s*%|-?\s*(?:min|sec|hour|hr|day|week|month|year|HU|o'?clock))", &m)
        return {val: m[1] + 0, unit: PE_Unit(m[2]), pos: m.Pos, len: m.Len}
    return ""
}

; Value that follows a label (e.g. "residual lumen ... 1.2 mm"), without crossing
; a stop label (e.g. "normal"). Tries every label occurrence in order.
PE_ValueAfter(t, labelRe, stopRe := "", maxGap := 90) {
    pos := 1
    while (p := RegExMatch(t, "i)" labelRe, &lm, pos)) {
        after := SubStr(t, p + lm.Len, maxGap)
        if (stopRe != "" && (sp := RegExMatch(after, "i)" stopRe)))
            after := SubStr(after, 1, sp - 1)
        if (v := PE_FirstValue(after)) {
            v.labelPos := p
            return v
        }
        pos := p + lm.Len
    }
    return ""
}

; All "N unit" measurements (units required)
PE_Measures(t) {
    out := [], pos := 1
    while (p := RegExMatch(t, "i)" PE_N "\s*-?\s*" PE_U "\b", &m, pos)) {
        out.Push({val: m[1] + 0, unit: PE_Unit(m[2]), pos: p})
        pos := p + m.Len
    }
    return out
}

; Three dimensions: "4.5 x 3.2 x 4.1 cm", "32 x 24 x 28 mm", "4.5 cm x 32 mm x 4.1 cm", "4 by 3 by 2 cm"
PE_FindDims(t) {
    n := PE_N, u := "\s*" PE_U "?", sep := "\s*(?:x|by|\*)\s*"
    if !RegExMatch(t, "i)" n u sep n u sep n u "(?!\d|\.\d)", &m)
        return ""
    vals := [m[1] + 0, m[3] + 0, m[5] + 0]
    units := [PE_Unit(m[2]), PE_Unit(m[4]), PE_Unit(m[6])]
    hasUnit := (units[1] != "" || units[2] != "" || units[3] != "")
    ; A number without its own unit takes the next unit written after it ("4.5 x 3.2 x 4.1 cm")
    Loop 3 {
        i := 4 - A_Index
        if (units[i] = "")
            units[i] := (i < 3 && units[i + 1] != "") ? units[i + 1] : ""
    }
    Loop 3 {
        if (units[A_Index] = "")
            units[A_Index] := (A_Index > 1 && units[A_Index - 1] != "") ? units[A_Index - 1] : ""
    }
    guessed := false
    if (!hasUnit) {
        guessed := true
        mx := Max(vals*)
        g := (mx >= 20) ? "mm" : PE_DefaultUnit()
        units := [g, g, g]
    }
    return {vals: vals, units: units, hasUnit: hasUnit, guessed: guessed, pos: m.Pos, len: m.Len}
}

PE_DefaultUnit() {
    global DefaultMeasurementUnit
    return (DefaultMeasurementUnit = "mm") ? "mm" : "cm"
}

PE_DimsText(d) {
    same := (d.units[1] = d.units[2] && d.units[2] = d.units[3])
    if same
        return PE_Fmt(d.vals[1], 2) " x " PE_Fmt(d.vals[2], 2) " x " PE_Fmt(d.vals[3], 2) " " d.units[1]
    return PE_Fmt(d.vals[1], 2) " " d.units[1] " x " PE_Fmt(d.vals[2], 2) " " d.units[2] " x " PE_Fmt(d.vals[3], 2) " " d.units[3]
}

; Text of the sentence part before position pos (for organ/vessel words)
PE_Before(t, pos, n := 140) {
    start := Max(1, pos - n)
    s := SubStr(t, start, pos - start)
    ; only the current sentence
    if (p := InStr(s, ". ", , -1))
        s := SubStr(s, p + 2)
    return s
}

; ---------------- VOLUME (ellipsoid) ----------------
PE_Volume(text) {
    t := PE_Clean(text)
    d := PE_FindDims(t)
    if !d
        return PE_Fail("Could not find three dimensions.`n`nExamples:`n- The prostate gland measures 4.5 x 3.2 x 4.1 cm.`n- Right ovarian cyst measuring 32 x 24 x 28 mm.")
    cm := [PE_ToCm(d.vals[1], d.units[1]), PE_ToCm(d.vals[2], d.units[2]), PE_ToCm(d.vals[3], d.units[3])]
    vol := 0.5236 * cm[1] * cm[2] * cm[3]
    organ := PE_Organ(PE_Before(t, d.pos))

    conf := d.hasUnit ? (RegExMatch(t, "i)measur|size|dimension") || organ != "" ? 95 : 85) : 40
    if (Max(cm*) > 50)
        conf -= 30

    res := " This corresponds to a volume of " PE_Fmt(vol) " cc (mL)"
    ; Size grading ONLY for the prostate (no descriptors for ICH, cysts, other organs)
    if (organ = "prostate") {
        g := PE_ProstateGrade(vol)
        res .= ", " g "."
        grade := g
    } else {
        res .= "."
    }
    vals := [["Structure", organ != "" ? organ : "(not detected)"], ["Dimensions", PE_DimsText(d) (d.guessed ? "  (units assumed)" : "")], ["Volume", PE_Fmt(vol) " cc"]]
    if (organ = "prostate")
        vals.Push(["Grade", "<30 normal, 30-49 mild, 50-79 moderate, 80+ severe"])
    return PE_Ok(organ = "prostate" ? "Prostate Volume" : "Ellipsoid Volume", vals, res, conf, ShowEllipsoidVolumeGuiPrefilled.Bind(cm[1], cm[2], cm[3]))
}

; Prostate volume grading (cc): <30 normal, 30-49 mild, 50-79 moderate, >=80 severe
PE_ProstateGrade(vol) {
    if (vol < 30)
        return "normal in size"
    if (vol < 50)
        return "compatible with mild prostatomegaly"
    if (vol < 80)
        return "compatible with moderate prostatomegaly"
    return "compatible with severe prostatomegaly"
}

PE_Organ(s) {
    static organs := [["prostat", "prostate"], ["bladder", "bladder"], ["thyroid", "thyroid"], ["ovar", "ovary"], ["uter", "uterus"]
        , ["testi", "testis"], ["kidney|renal", "kidney"], ["spleen|splenic", "spleen"], ["liver|hepatic", "liver"]
        , ["hematoma", "hematoma"], ["hemorrhage|bleed", "hemorrhage"], ["abscess", "abscess"], ["collection", "collection"]
        , ["cyst", "cyst"], ["lymph node|node", "lymph node"], ["mass", "mass"], ["lesion", "lesion"], ["nodule", "nodule"]]
    for o in organs {
        if RegExMatch(s, "i)\b(?:" o[1] ")")
            return o[2]
    }
    return ""
}

; ---------------- ICH (ABC/2) ----------------
PE_ICH(text) {
    t := PE_Clean(text)
    d := PE_FindDims(t)
    if !d
        return PE_Fail("Could not find three hemorrhage dimensions.`n`nExample: Intraparenchymal hemorrhage measuring 4.2 x 2.8 x 3.5 cm.")
    a := PE_ToCm(d.vals[1], d.units[1]), b := PE_ToCm(d.vals[2], d.units[2]), c := PE_ToCm(d.vals[3], d.units[3])
    vol := (a * b * c) / 2
    conf := d.hasUnit ? 90 : 40
    res := " ICH volume approximately " PE_Fmt(vol) " cc (ABC/2: " PE_Fmt(a) " x " PE_Fmt(b) " x " PE_Fmt(c) " cm)."
    vals := [["Dimensions", PE_DimsText(d) (d.guessed ? "  (units assumed)" : "")], ["A x B x C", PE_Fmt(a) " x " PE_Fmt(b) " x " PE_Fmt(c) " cm"], ["Volume (ABC/2)", PE_Fmt(vol) " cc"]]
    return PE_Ok("ICH Volume (ABC/2)", vals, res, conf, ShowICHVolumeGuiPrefilled.Bind(a, b, c))
}

; ---------------- RV / LV ----------------
PE_RVLV(text) {
    global RVLVOutputFormat
    t := PE_Clean(text)
    rvRe := "(?:\bRV\b|\bR\.V\.|\bright\s+ventric(?:le|ular)|\brt\.?\s+ventric(?:le|ular)|\brvval\b)"
    lvRe := "(?:\bLV\b|\bL\.V\.|\bleft\s+ventric(?:le|ular)|\blt\.?\s+ventric(?:le|ular)|\blvval\b)"
    rv := "", lv := "", conf := 0

    ; "RV/LV 42/35" or "RV:LV = 4.2:3.5"
    if RegExMatch(t, "i)\bRV\s*[/:]\s*LV\b[^\d]{0,20}" PE_N "\s*[/:]\s*" PE_N, &m) {
        rv := {val: m[1] + 0, unit: ""}, lv := {val: m[2] + 0, unit: ""}, conf := 80
    }
    ; "RV/LV ratio of 1.2" (ratio only)
    else if RegExMatch(t, "i)\bRV\s*(?:/|:|to)\s*LV\b(?:\s*(?:diameter\s*)?ratio)?[^\d]{0,20}" PE_N "(?!\s*[/:]\s*\d)", &m) && (m[1] + 0) < 4 {
        ratio := PE_Fmt(m[1] + 0, 2)
        res := " RV/LV ratio: " ratio ". " PE_RVLVInterp(ratio)
        return PE_Ok("RV/LV Ratio", [["Ratio", ratio]], res, 80)
    }
    else {
        rv := PE_ValueAfter(t, rvRe, lvRe)
        lv := PE_ValueAfter(t, lvRe, rvRe)
        if (rv && lv)
            conf := 90
    }
    if (!rv || !lv)
        return PE_Fail("Could not find both RV and LV measurements.`n`nExamples:`n- The right ventricle measures 4.2 cm and the left ventricle measures 3.8 cm.`n- RV 42 mm / LV 35 mm")

    ; No unit: values under 10 are cm, otherwise mm
    rvU := rv.unit != "" ? rv.unit : (rv.val < 10 ? "cm" : "mm")
    lvU := lv.unit != "" ? lv.unit : (lv.val < 10 ? "cm" : "mm")
    if (rv.unit = "" || lv.unit = "")
        conf -= 15
    rvMm := PE_ToMm(rv.val, rvU), lvMm := PE_ToMm(lv.val, lvU)
    if (lvMm <= 0)
        return PE_Fail("LV diameter must be greater than 0.")
    if (rvMm < 10 || rvMm > 100 || lvMm < 10 || lvMm > 100)
        conf -= 30
    ratio := PE_Fmt(rvMm / lvMm, 2)
    if (RVLVOutputFormat = "Macro")
        res := " RV/LV ratio: " ratio " (RV " PE_Fmt(rvMm / 10) "cm, LV " PE_Fmt(lvMm / 10) "cm). " PE_RVLVInterp(ratio)
    else
        res := " RV/LV ratio: " ratio " (RV " PE_Fmt(rvMm) "mm, LV " PE_Fmt(lvMm) "mm). " PE_RVLVInterp(ratio)
    vals := [["RV", PE_Fmt(rv.val, 2) " " rvU], ["LV", PE_Fmt(lv.val, 2) " " lvU], ["Ratio", ratio]]
    return PE_Ok("RV/LV Ratio", vals, res, conf, ShowRVLVGuiPrefilled.Bind(rvMm, lvMm))
}

PE_LcFirst(s) => StrLower(SubStr(s, 1, 1)) SubStr(s, 2)

; WHY: The RV/LV ratio has no validated mild/moderate/severe grading on CT, so
;      the text only states what the number shows. It never says "severe" or
;      diagnoses strain/PE severity - that would prompt calls on stable patients.
;      Thresholds: <0.9 normal, 0.9-0.99 borderline, >=1.0 elevated.
PE_RVLVInterp(ratio) {
    if (ratio >= 1.0)
        return "Elevated (1.0 or greater), compatible with right ventricular dilatation. Correlate clinically and with echocardiography for right heart strain."
    if (ratio >= 0.9)
        return "Borderline (0.9-0.99)."
    return "Normal (less than 0.9)."
}

; ---------------- STENOSIS (NASCET for ICA, % diameter for any vessel) ----------------
PE_Stenosis(text, forceNascet := false) {
    t := PE_Clean(text)
    stenRe := "(?:residual\s+(?:lumen|luminal\s+diameter|diameter)|minimal\s+lumen(?:al)?(?:\s+diameter)?|\bMLD\b|narrowest|tightest|"
            . "narrowing|narrowed|stenos[ie]s|stenotic|lumen\s+at\s+the\s+(?:stenosis|narrowing))"
    normRe := "(?:\bnormal|\breference|\bdistal|non-?stenotic|unaffected|uninvolved|beyond\s+the\s+(?:stenosis|narrowing)|downstream)"

    sten := PE_ValueAfter(t, stenRe, normRe)
    norm := PE_ValueAfter(t, normRe, stenRe)
    conf := 90
    ; "1.2 mm residual lumen" (value before the label)
    if (!sten && RegExMatch(t, "i)" PE_N "\s*-?\s*" PE_U "?\s+(?:residual\s+lumen|stenosis|narrowing)", &m))
        sten := {val: m[1] + 0, unit: PE_Unit(m[2])}
    if (!sten || !norm || (sten.val = norm.val && sten.unit = norm.unit)) {
        ; Fallback: exactly two measurements -> smaller is the stenosis
        ms := PE_Measures(t)
        if (ms.Length = 2 && RegExMatch(t, "i)" stenRe)) {
            a := ms[1], b := ms[2]
            if (PE_ToMm(a.val, a.unit) <= PE_ToMm(b.val, b.unit))
                sten := a, norm := b
            else
                sten := b, norm := a
            conf := 60
        } else {
            return PE_Fail("Could not find a stenosis measurement and a normal (reference) measurement.`n`nExamples:`n- The proximal ICA residual lumen measures 1.2 mm and the normal distal cervical ICA measures 4.5 mm.`n- The SMA has a focal narrowing measuring 2 mm with a normal distal caliber of 6 mm.")
        }
    }
    ; Numbers without units are mm (vessel calibers); "0.5" style values with a cm partner stay cm
    sU := sten.unit != "" ? sten.unit : (norm.unit = "cm" && sten.val < 2 ? "cm" : "mm")
    nU := norm.unit != "" ? norm.unit : (sten.unit = "cm" && norm.val < 2 ? "cm" : "mm")
    if (sten.unit = "" || norm.unit = "")
        conf -= 10
    s := PE_ToMm(sten.val, sU), n := PE_ToMm(norm.val, nU)
    if (s >= n) {
        if (s > n) {              ; labels were probably swapped
            tmp := s, s := n, n := tmp
            conf -= 25
        } else {
            return PE_Fail("Stenosis and normal diameters are the same (" PE_Fmt(s) " mm) - nothing to calculate.")
        }
    }
    if (n <= 0)
        return PE_Fail("Normal diameter must be greater than 0.")
    pct := Round((n - s) / n * 100, 1)
    vessel := PE_Vessel(t)
    isICA := forceNascet || vessel = "ICA"
    severity := pct < 50 ? "mild stenosis" : pct < 70 ? "moderate stenosis" : "severe stenosis"
    if (isICA) {
        res := " NASCET: " PE_Fmt(pct) "% stenosis (distal " PE_Fmt(n) "mm, stenosis " PE_Fmt(s) "mm), "
        res .= pct < 50 ? "mild stenosis." : pct < 70 ? "moderate stenosis, consider intervention if symptomatic." : "severe stenosis, strong indication for CEA/CAS."
        title := "NASCET Stenosis"
        edit := ShowNASCETGuiPrefilled.Bind(n, s)
    } else {
        name := vessel != "" ? vessel : "Vessel"
        res := " " name " stenosis: " PE_Fmt(pct) "% (normal " PE_Fmt(n) "mm, stenosis " PE_Fmt(s) "mm), " severity "."
        title := "Vessel Stenosis"
        edit := ShowStenosisGui
    }
    vals := [["Vessel", vessel != "" ? vessel : "(not detected)"], ["Stenosis", PE_Fmt(sten.val, 2) " " sU], ["Normal", PE_Fmt(norm.val, 2) " " nU], ["% stenosis", PE_Fmt(pct) "%"]]
    return PE_Ok(title, vals, res, conf, edit)
}

PE_Vessel(t) {
    static vessels := [["\bICA\b|internal\s+carotid", "ICA"], ["\bCCA\b|common\s+carotid", "CCA"], ["\bECA\b|external\s+carotid", "ECA"]
        , ["\bSMA\b|superior\s+mesenteric", "SMA"], ["\bIMA\b|inferior\s+mesenteric", "IMA"], ["celiac", "Celiac"]
        , ["renal\s+arter", "Renal artery"], ["vertebral", "Vertebral artery"], ["basilar", "Basilar artery"]
        , ["\bMCA\b|middle\s+cerebral", "MCA"], ["\bACA\b|anterior\s+cerebral", "ACA"], ["\bPCA\b|posterior\s+cerebral", "PCA"]
        , ["subclavian", "Subclavian artery"], ["\bCIA\b|common\s+iliac", "Common iliac artery"], ["\bEIA\b|external\s+iliac", "External iliac artery"]
        , ["\bIIA\b|internal\s+iliac", "Internal iliac artery"], ["\bSFA\b|superficial\s+femoral", "SFA"], ["\bCFA\b|common\s+femoral", "CFA"]
        , ["popliteal", "Popliteal artery"], ["\bLAD\b", "LAD"], ["\bRCA\b", "RCA"], ["circumflex|\bLCx\b", "LCx"], ["left\s+main", "Left main"]
        , ["carotid", "ICA"], ["aort", "Aorta"], ["iliac", "Iliac artery"], ["femoral", "Femoral artery"]]
    for v in vessels {
        if RegExMatch(t, "i)" v[1])
            return v[2]
    }
    return ""
}

PE_NASCET(text) => PE_Stenosis(text, true)

; ---------------- ADRENAL WASHOUT ----------------
PE_Adrenal(text) {
    t := PE_Clean(text)
    huRe := "i)(?<![\d.])(-?\d+(?:\.\d+)?)\s*(?:HU\b|Hounsfield(?:\s+units?)?)"
    vals := [], pos := 1
    while (p := RegExMatch(t, huRe, &m, pos)) {
        vals.Push({val: m[1] + 0, pos: p, end: p + m.Len, phase: ""})
        pos := p + m.Len
    }
    ; "HU of 45" / "attenuation of 45 HU" handled above; also "measuring 45 Hounsfield"
    if (vals.Length < 2)
        return PE_Fail("Could not find at least two HU values.`n`nExample: Left adrenal nodule measures 45 HU on noncontrast, 85 HU on portal venous phase, and 50 HU on 15-minute delayed phase.")

    ; Label each value from the words right after it ("45 HU on noncontrast") or,
    ; failing that, the words right before it ("pre-contrast 10 HU")
    for i, v in vals {
        nextStart := (i < vals.Length) ? vals[i + 1].pos : StrLen(t) + 1
        prevEnd := (i > 1) ? vals[i - 1].end : 1
        after := SubStr(t, v.end, Min(45, nextStart - v.end))
        before := SubStr(t, prevEnd, v.pos - prevEnd)
        ; "45 HU on noncontrast" / "45 HU (delayed)" -> label after; otherwise label before
        ph := ""
        if RegExMatch(after, "i)^\s*(?:\(|on\b|in\b|at\b|during\b|with\b|for\b)\s*(?:the\s+)?(.{0,30})", &am)
            ph := PE_Phase(am[1], true)
        if (ph = "")
            ph := PE_Phase(before, false)
        if (ph = "" && RegExMatch(after, "i)^[\s,]*(.{0,30})", &am))
            ph := PE_Phase(am[1], true)
        v.phase := ph
    }
    pre := "", post := "", del := "", labeled := 0
    for v in vals {
        if (v.phase = "pre" && pre = "")
            pre := v.val, labeled++
        else if (v.phase = "post" && post = "")
            post := v.val, labeled++
        else if (v.phase = "delayed" && del = "")
            del := v.val, labeled++
    }
    conf := 95
    if (labeled < vals.Length || post = "" || del = "") {
        ; Unlabeled: assume reporting order (pre, post, delayed) or (post, delayed)
        if (vals.Length >= 3)
            pre := vals[1].val, post := vals[2].val, del := vals[3].val
        else
            pre := "", post := vals[1].val, del := vals[2].val
        conf := 55
    }
    if (post < -50 || post > 300 || del < -50 || del > 300)
        conf -= 25

    res := " Adrenal washout: "
    if (pre != "" && post != pre) {
        abs := Round((post - del) / (post - pre) * 100, 1)
        res .= "absolute " PE_Fmt(abs) "%" (abs >= 60 ? " (likely adenoma)" : " (indeterminate)") ", "
    }
    if (post != 0) {
        rel := Round((post - del) / post * 100, 1)
        res .= "relative " PE_Fmt(rel) "%" (rel >= 40 ? " (likely adenoma)" : " (indeterminate)") "."
    }
    if (pre != "" && pre <= 10)
        res .= " Pre-contrast " PE_Fmt(pre) " HU suggests lipid-rich adenoma."
    out := [["Pre-contrast", pre != "" ? PE_Fmt(pre) " HU" : "N/A"], ["Portal venous", PE_Fmt(post) " HU"], ["Delayed", PE_Fmt(del) " HU"]]
    return PE_Ok("Adrenal Washout", out, res, conf, ShowAdrenalWashoutGuiPrefilled.Bind(pre, post, del))
}

; Classify a phrase as pre / post / delayed contrast phase
PE_Phase(s, fromStart) {
    static pre := "non-?contrast|non-?enhanced|unenhanced|pre-?contrast|precontrast|without\s+contrast|native|baseline|plain|non-?con\b|\bNC\b"
    static del := "delayed|15[- ]?min(?:ute)?|10[- ]?min(?:ute)?|\blate\b|washout\s+phase"
    static post := "portal(?:\s+venous)?|\bvenous|\bPV\b|post-?contrast|postcontrast|contrast[- ]enhanced|\benhanced|arterial|nephrographic|60[- ]?(?:70[- ]?)?sec"
    best := "", bestPos := fromStart ? 999 : 0
    for name, re in Map("pre", pre, "delayed", del, "post", post) {
        if fromStart {
            if ((p := RegExMatch(s, "i)" re)) && p < bestPos)
                best := name, bestPos := p
        } else {
            ; last label before the value wins
            q := 1
            while (p := RegExMatch(s, "i)" re, &m, q)) {
                if (p >= bestPos)
                    best := name, bestPos := p
                q := p + Max(1, m.Len)
            }
        }
    }
    ; "non-enhanced" also matches "enhanced": pre wins at the same spot
    return best
}

; ---------------- FLEISCHNER ----------------
PE_Fleischner(text) {
    global DataminingPhrase, IncludeDatamining, ShowCitations, FleischnerInsertAfterImpression
    t := RegExReplace(text, "\R", " ")
    t := StrReplace(t, Chr(0xD7), "x")
    t := FilterNonMeasurements(t)
    ; Split into sentences (not on decimal points)
    t := RegExReplace(t, "(?<!\d)\.(?!\d)|;|(?<=\d)\.(?=\s+[A-Z])", "`n")
    nodRe := "i)\b(?:nodules?|nodular\s+(?:opacit(?:y|ies)|densit(?:y|ies))|micronodules?|GGNs?|GGOs?|ground[- ]?glass\s+(?:opacit(?:y|ies)|nodules?|lesions?|focus)|subsolid\s+(?:lesions?|opacit(?:y|ies)))\b"
    nonLung := "i)\b(?:thyroid|adrenal|renal|kidney|hepatic|liver|breast|splenic|spleen|pancrea|ovar|testic|prostat|lymph|skin|subcutaneous|bone|osseous)"
    found := []
    plural := false
    for s in StrSplit(t, "`n") {
        if !RegExMatch(s, nodRe)
            continue
        if (RegExMatch(s, nonLung) && !RegExMatch(s, "i)lung|pulmonary|lobe|lingula|\b[RL][UML]L\b"))
            continue
        if (RegExMatch(s, "i)\bcalcified\b") && !RegExMatch(s, "i)\b(?:non-?|partially\s+)calcified\b"))
            continue    ; calcified nodules are benign - not Fleischner
        size := 0, sub6 := false, sizeTxt := ""
        if RegExMatch(s, "i)sub[- ]?(?:6|centimeter)|<\s*6\s*mm|less\s+than\s+6\s*mm|smaller\s+than\s+6\s*mm")
            size := 5, sub6 := true, sizeTxt := "<6 mm"
        ; two dimensions: average (Fleischner 2017 uses mean of long and short axis)
        if (sub6) {
            ; already sized
        } else if RegExMatch(s, "i)" PE_N "\s*" PE_U "?\s*(?:x|by)\s*" PE_N "\s*" PE_U, &m) {
            u1 := PE_Unit(m[2] != "" ? m[2] : m[4]), u2 := PE_Unit(m[4])
            a := PE_ToMm(m[1] + 0, u1), b := PE_ToMm(m[3] + 0, u2)
            size := Round((a + b) / 2)
            sizeTxt := PE_Fmt(a) " x " PE_Fmt(b) " mm, mean " size " mm"
        } else {
            for v in PE_Measures(s) {
                mm := PE_ToMm(v.val, v.unit)
                if (mm > size)
                    size := mm
            }
            if (size > 0)
                sizeTxt := PE_Fmt(size) " mm"
        }
        if (size = 0 && RegExMatch(s, "i)punctate|tiny|small|micronodul|miliary"))
            size := 5, sub6 := true, sizeTxt := "<6 mm"
        if (size = 0 || size > 30)
            continue
        size := PE_Fmt(size) + 0      ; 7 not 7.0
        type := "solid"
        if RegExMatch(s, "i)part[- ]?solid|semi[- ]?solid|mixed(?:\s+(?:solid|density|attenuation))?")
            type := "part-solid"
        else if RegExMatch(s, "i)ground[- ]?glass|\bGG[NO]s?\b|sub[- ]?solid|non-?solid|hazy")
            type := "subsolid"
        lobe := PE_Lobe(s)
        if RegExMatch(s, "i)\b(?:nodules|micronodules|GGNs|GGOs|opacities|multiple|several|numerous|innumerable|scattered|few|bilateral|two|three|four)\b")
            plural := true
        ; Same nodule mentioned again (e.g. findings + impression): same type, ~same size, same/unknown lobe
        dup := false
        for f in found {
            if (f.type = type && Abs(f.size - size) <= 1 && (f.lobe = "" || lobe = "" || f.lobe = lobe)) {
                dup := true
                if (size > f.size)
                    f.size := size
                if (f.lobe = "")
                    f.lobe := lobe
                break
            }
        }
        if !dup
            found.Push({type: type, size: size, sizeTxt: sizeTxt, lobe: lobe, sub6: sub6})
    }
    if (found.Length = 0)
        return PE_Fail("Could not find a pulmonary nodule with a size.`n`nExamples:`n- There is a 7 mm solid noncalcified pulmonary nodule in the right upper lobe.`n- 8 x 6 mm ground-glass nodule in the left lower lobe.")

    isMultiple := (found.Length > 1) || plural
    maxSolid := 0, maxSub := 0, maxPart := 0, nSolid := 0, nSub := 0, nPart := 0
    for f in found {
        if (f.type = "solid")
            maxSolid := Max(maxSolid, f.size), nSolid++
        else if (f.type = "subsolid")
            maxSub := Max(maxSub, f.size), nSub++
        else
            maxPart := Max(maxPart, f.size), nPart++
    }

    r := "`n`n___________________________________________________________`n"
    r .= "Incidental Lung Nodule Discussion:`n"
    r .= "2017 ACR Fleischner Society expert consensus recommendations on incidental pulmonary nodules.`n"
    r .= "Target Demographic: 35+ years without known cancer or immunosuppressive disorder.`n`n"
    r .= "Detected nodules:`n"
    for i, f in found {
        typeName := f.type = "solid" ? "solid" : f.type = "subsolid" ? "ground glass/subsolid" : "part-solid"
        r .= i ". " (f.sub6 ? "<6" : PE_Fmt(f.size)) " mm " typeName " nodule" (f.lobe != "" ? " (" f.lobe ")" : "") "`n"
    }
    recLow := GenerateFleischnerRec(maxSolid, maxSub, maxPart, isMultiple, "Low risk")
    recHigh := GenerateFleischnerRec(maxSolid, maxSub, maxPart, isMultiple, "High risk")
    for f in found {
        if (f.sub6) {   ; show "<6mm" instead of the placeholder 5 mm
            nm := f.type = "solid" ? "Solid" : f.type = "subsolid" ? "Ground glass" : "Part-solid"
            recLow := StrReplace(recLow, nm " 5mm", nm " <6mm"), recHigh := StrReplace(recHigh, nm " 5mm", nm " <6mm")
        }
    }
    r .= "`nLOW RISK recommendation:`n" recLow
    r .= "`n`nHIGH RISK recommendation:`n" recHigh
    if (IncludeDatamining)
        r .= "`n`nData Mining: " DataminingPhrase " . ACR and AMA MIPS #364"
    r .= "`n`nNote: The need for followup depends on clinical discussion of patient's comorbid conditions, demographics, and willingness to undergo followup imaging and potential intervention."
    if (ShowCitations)
        r .= "`nRef: MacMahon H et al. Radiology 2017;284:228-243"
    r .= "`n___________________________________________________________"

    summary := ""
    for f in found
        summary .= (summary != "" ? "; " : "") f.type " " (f.sub6 ? "<6" : PE_Fmt(f.size)) " mm" (f.lobe != "" ? " " f.lobe : "")
    vals := [["Nodules", summary], ["Count", isMultiple ? "Multiple" : "Single"]]
    dom := Max(maxSolid, maxSub, maxPart)
    domType := maxSolid >= dom ? "Solid" : maxSub >= dom ? "Ground glass" : "Part-solid"
    conf := found.Length > 3 ? 75 : 90
    return PE_Ok("Fleischner Nodules", vals, r, conf, ShowFleischnerGuiPrefilled.Bind(dom, domType, isMultiple ? "Multiple" : "Single"), FleischnerInsertAfterImpression)
}

PE_Lobe(s) {
    if RegExMatch(s, "i)\b(right|left)\s+(upper|middle|lower)\s+lobe", &m)
        return StrLower(m[1] " " m[2]) " lobe"
    static abbr := Map("RUL", "right upper lobe", "RML", "right middle lobe", "RLL", "right lower lobe", "LUL", "left upper lobe", "LLL", "left lower lobe")
    if RegExMatch(s, "\b(RUL|RML|RLL|LUL|LLL)\b", &m)
        return abbr[m[1]]
    if RegExMatch(s, "i)lingula")
        return "lingula"
    return ""
}

; ---------------- FOLLOW-UP DATE ----------------
PE_Date(text) {
    t := RegExReplace(text, "\R", " ")
    static words := Map("a", 1, "an", 1, "one", 1, "two", 2, "three", 3, "four", 4, "five", 5, "six", 6, "seven", 7, "eight", 8
        , "nine", 9, "ten", 10, "eleven", 11, "twelve", 12, "eighteen", 18, "twenty-four", 24, "twenty four", 24)
    num := "(\d+|twenty[- ]four|eighteen|twelve|eleven|ten|nine|eight|seven|six|five|four|three|two|one|an?)"
    unitRe := "(days?|weeks?|wks?|months?|mos?|years?|yrs?)"
    re := "i)\b" num "(?:\s*(?:-|to|or)\s*" num ")?[\s-]*" unitRe "\b(?![\s-]*old)"
    if !RegExMatch(t, re, &m) {
        ; shorthand "3m", "6w", "1y"
        if !RegExMatch(t, "i)\b(\d+)\s*(d|w|m|y)\b", &m)
            return PE_Fail("Could not find a follow-up interval.`n`nExamples:`n- Recommend follow-up ultrasound in 6 months.`n- Please schedule follow-up MRI in 3 weeks.")
        n1 := m[1] + 0, n2 := "", u := m[2]
    } else {
        n1 := IsNumber(m[1]) ? m[1] + 0 : words[StrLower(m[1])]
        n2 := m[2] = "" ? "" : (IsNumber(m[2]) ? m[2] + 0 : words[StrLower(m[2])])
        u := m[3]
    }
    c := StrLower(SubStr(u, 1, 1))
    unit := c = "d" ? "days" : c = "w" ? "weeks" : c = "m" ? "months" : "years"
    if (n1 = 0)
        return PE_Fail("Follow-up interval must be greater than 0.")
    d1 := CalculateFutureDate(n1, unit)
    span := n1 (n2 != "" ? "-" n2 : "") " " (n2 = "" && n1 = 1 ? RTrim(unit, "s") : unit)
    when := d1
    if (n2 != "")
        when := d1 " to " CalculateFutureDate(n2, unit)
    modality := ""
    if RegExMatch(t, "i)\b(CT|MRI|MR|ultrasound|sonogra\w*|US|PET(?:/CT)?|mammogra\w*|radiograph\w*|x-?ray|CTA|MRA)\b", &mm)
        modality := mm[1]
    ; If the sentence already recommends follow-up, just add the due date
    if RegExMatch(t, "i)follow[- ]?up|recommend|repeat|re-?evaluat|re-?image|schedul")
        res := " (Due approximately " when ".)"
    else
        res := " Recommend follow-up" (modality != "" ? " " modality : "") " in " span " (approximately " when ")."
    vals := [["Interval", span], ["Modality", modality != "" ? modality : "(not stated)"], ["Due date", when]]
    return PE_Ok("Follow-up Date", vals, res, 95, ShowDateCalculatorGuiPrefilled.Bind(n1, unit))
}

; ---------------- AUTO-DETECT ----------------
; Picks the calculation from the words in the selection.
PE_Auto(text) {
    t := PE_Clean(text)
    tried := []
    tryOrder := []
    huCount := 0, pos := 1
    while (p := RegExMatch(t, "i)\d\s*(?:HU\b|Hounsfield)", &m, pos))
        huCount++, pos := p + m.Len
    if (huCount >= 2)
        tryOrder.Push("Adrenal")
    if (RegExMatch(t, "i)\bRV\b|right\s+ventric|rvval") && RegExMatch(t, "i)\bLV\b|left\s+ventric|lvval"))
        tryOrder.Push("RVLV")
    if RegExMatch(t, "i)stenos|stenotic|narrow|residual\s+lumen|NASCET|minimal\s+lumen")
        tryOrder.Push("Stenosis")
    if (RegExMatch(t, "i)thyroid|\bTI-?RADS|isthmus|\b(?:right|left)\s+lobe\b") && RegExMatch(t, "i)nodul"))
        tryOrder.Push("TIRADS")
    if (RegExMatch(t, "i)ovar|adnex") && RegExMatch(t, "i)\bsimple\b|hemorrhag|endometrioma|dermoid|teratoma|reticular|ground[- ]?glass|low[- ]level\s+echoes|menopaus|O-?RADS"))
        tryOrder.Push("ORADS")
    if PE_FindDims(t)
        tryOrder.Push(RegExMatch(t, "i)hemorrhage|hematoma|\bICH\b|\bbleed|intraparenchymal|intracerebral") ? "ICH" : "Volume")
    if RegExMatch(t, "i)nodul|\bGG[NO]|ground[- ]?glass")
        tryOrder.Push("Fleischner")
    if RegExMatch(t, "i)\b(?:\d+|one|two|three|four|six|twelve|an?)[\s-]*(?:days?|weeks?|months?|years?)\b(?![\s-]*old)")
        tryOrder.Push("Date")
    for name in tryOrder {
        r := PE_ByName(name, text)
        if r.ok
            return r
        tried.Push(name)
    }
    msg := "Could not recognize a calculation in the selected text."
    if tried.Length {
        list := ""
        for n in tried
            list .= (list != "" ? ", " : "") n
        msg .= "`n`nTried: " list
    }
    msg .= "`n`nSupported: 3-D volumes, ICH (ABC/2), RV/LV, NASCET / vessel stenosis, adrenal washout (HU), Fleischner nodules, thyroid TI-RADS, ovarian cysts (O-RADS/SRU), follow-up dates."
    return PE_Fail(msg)
}

PE_ByName(name, text) {
    switch name {
        case "Volume": return PE_Volume(text)
        case "ICH": return PE_ICH(text)
        case "RVLV": return PE_RVLV(text)
        case "NASCET": return PE_NASCET(text)
        case "Stenosis": return PE_Stenosis(text)
        case "Adrenal": return PE_Adrenal(text)
        case "Fleischner": return PE_Fleischner(text)
        case "Date": return PE_Date(text)
        case "TIRADS": return PE_TIRADS(text)
        case "ORADS": return PE_ORADS(text)
        default: return PE_Auto(text)
    }
}

; Show confirmation, then insert / open GUI
; NOTE: Returns right away; the dialog's Insert / Edit buttons finish the job.
SP_Run(r) {
    global g_SPResult
    if !r.ok {
        MsgBox(r.err, "Smart Parse", 0x40030)   ; 0x40000 = always on top, 0x30 = warning icon
        return
    }
    g_SPResult := r
    ShowParseConfirmation(r.title, r.values, r.text, r.conf)
}

; ---------------- THYROID: ACR TI-RADS ----------------
; Scores each nodule from its descriptors (ACR TI-RADS, Tessler et al. JACR 2017).
; Highlight one description or the whole report; text after IMPRESSION is ignored
; so nodules repeated in the impression are not double-counted.
PE_TIRADS(text) {
    t := RegExReplace(text, "\R", "`n")
    if RegExMatch(t, "i)(?:^|\n)\s*(?:CLINICAL\s+)?IMPRESSIONS?\s*:", &im)
        t := SubStr(t, 1, im.Pos - 1)
    t := RegExReplace(t, "\s+", " ")
    t := StrReplace(t, Chr(0xD7), "x")
    t := RegExReplace(t, "(?<!\d)\.(?!\d)|;", ".`n")          ; sentences (not decimals)

    ; Group sentences into nodules: a sentence that mentions a nodule with a size
    ; starts a new nodule; following sentences without a new size add descriptors.
    nodules := [], cur := ""
    for s in StrSplit(t, "`n") {
        s := Trim(s)
        if (s = "")
            continue
        hasNod := RegExMatch(s, "i)\b(?:nodules?|lesions?|mass|TR\d)\b")
        sz := PE_TIRADSSize(s)
        if (hasNod && sz > 0) {
            if RegExMatch(s, "i)\bno\s+(?:\w+\s+){0,3}nodules?\b")
                continue
            cur := {text: s, size: sz}
            nodules.Push(cur)
        } else if IsObject(cur) {
            if (RegExMatch(s, "i)\b(?:nodules?|lobe|isthmus)\b") && !RegExMatch(s, "i)\b(?:it|this|the\s+nodule|which|there\s+is)\b"))
                cur := ""                      ; talking about something else now
            else
                cur.text .= " " s
        }
    }
    if (nodules.Length = 0)
        return PE_Fail("Could not find a thyroid nodule with a size.`n`nExample: Right lobe: solid, hypoechoic, 1.5 cm nodule with macrocalcifications, wider-than-tall with smooth margins.")

    out := "`n`nACR TI-RADS:"
    vals := [], fnaCount := 0, conf := 90
    for i, n in nodules {
        sc := PE_TIRADSScore(n.text)
        tr := PE_TIRADSLevel(sc.total)
        rec := PE_TIRADSRec(tr, n.size)
        if InStr(rec, "FNA recommended")
            fnaCount++
        loc := PE_ThyroidLoc(n.text)
        out .= "`nNodule " i (loc != "" ? " (" loc ")" : "") ", " PE_Fmt(n.size) " cm: " sc.detail
        out .= " = " sc.total " point" (sc.total = 1 ? "" : "s") ", TR" tr " (" PE_TIRADSName(tr) "). " rec
        vals.Push(["Nodule " i, (loc != "" ? loc " " : "") PE_Fmt(n.size) " cm, " sc.total " pts, TR" tr (sc.missing != "" ? "  [assumed: " sc.missing "]" : "")])
        if (sc.missing != "")
            conf := Min(conf, 70)
    }
    if (fnaCount > 2)
        out .= "`nNote: ACR TI-RADS suggests FNA of no more than two nodules, those with the highest point totals."
    out .= "`nRef: Tessler FN et al. ACR Thyroid Imaging, Reporting and Data System (TI-RADS). JACR 2017;14:587-595."
    return PE_Ok("ACR TI-RADS", vals, out, conf, "", true)     ; true = insert after the IMPRESSION
}

; Largest dimension in cm ("1.5 x 1.2 x 1.0 cm", "15 mm", "1.5 cm")
PE_TIRADSSize(s) {
    best := 0, pos := 1
    while (p := RegExMatch(s, "i)" PE_N "\s*(?:" PE_U ")?((?:\s*(?:x|by)\s*(?:\d+(?:\.\d+)?|\.\d+)\s*(?:" PE_U ")?){0,2})", &m, pos)) {
        pos := p + Max(1, m.Len)
        ; unit = last unit written in this measurement
        u := ""
        if RegExMatch(m[0], "i)(mm|cm|millimet|centimet)[a-z]*\s*$", &um)
            u := PE_Unit(um[1])
        if (u = "")
            continue
        nums := [], q := 1
        while (qq := RegExMatch(m[0], "(\d+(?:\.\d+)?|\.\d+)", &nm, q))
            nums.Push(nm[1] + 0), q := qq + nm.Len
        mx := Max(nums*)
        best := Max(best, u = "mm" ? mx / 10 : mx)
    }
    return best
}

PE_TIRADSScore(s) {
    ; Drop negated findings first ("no microcalcifications", "not taller-than-wide")
    t := RegExReplace(s, "i)\b(?:no|without|absent|negative\s+for)\s+(?:\w+[\s,]+){0,4}?(?:micro|macro)?calcifications?|\b(?:no|without)\s+(?:\w+\s+){0,3}?echogenic\s+foci", " ")
    t := RegExReplace(t, "i)\b(?:no|without)\s+(?:evidence\s+of\s+)?extra-?\s?thyroidal\s+extension", " ")
    t := RegExReplace(t, "i)\bnot\s+taller[- ]than[- ]wide", " wider-than-tall")
    detail := "", missing := ""

    ; Composition
    if RegExMatch(t, "i)spongiform") {
        return {total: 0, detail: "spongiform (0; other features not scored)", missing: ""}
    } else if RegExMatch(t, "i)mixed|partially\s+cystic|predominantly\s+(?:solid|cystic)|solid\s+and\s+cystic|cystic\s+and\s+solid|complex\s+cystic|cystic\s+(?:and|with)\s+solid|solid\s+(?:with|and)\s+cystic") {
        comp := 1, cname := "mixed cystic and solid"
    } else if RegExMatch(t, "i)(?:purely|completely|entirely|almost\s+completely|simple)\s+cystic|\bcyst\b|anechoic\s+cyst|\bcystic\b") && !RegExMatch(t, "i)\bsolid\b") {
        comp := 0, cname := "cystic"
    } else if RegExMatch(t, "i)\bsolid\b") {
        comp := 2, cname := "solid"
    } else {
        comp := 2, cname := "solid (composition not stated)", missing .= "composition "
    }
    ; Echogenicity
    if (comp = 0) {
        echo := 0, ename := "anechoic"
    } else if RegExMatch(t, "i)(?:very|markedly)\s+hypoechoic") {
        echo := 3, ename := "very hypoechoic"
    } else if RegExMatch(t, "i)hypoechoic|hypoechogenic") {
        echo := 2, ename := "hypoechoic"
    } else if RegExMatch(t, "i)isoechoic|hyperechoic|iso-?\s?echoic|hyper-?\s?echoic|echogenic\s+nodule") {
        echo := 1, ename := RegExMatch(t, "i)hyper") ? "hyperechoic" : "isoechoic"
    } else if RegExMatch(t, "i)anechoic") {
        echo := 0, ename := "anechoic"
    } else {
        echo := 1, ename := "echogenicity not stated", missing .= "echogenicity "
    }
    ; Shape
    if RegExMatch(t, "i)taller[- ]than[- ]wide|anti-?parallel") {
        shape := 3, sname := "taller-than-wide"
    } else {
        shape := 0, sname := "wider-than-tall"
        if !RegExMatch(t, "i)wider[- ]than[- ]tall|parallel|oval|round")
            sname .= " (shape not stated)"
    }
    ; Margin
    if RegExMatch(t, "i)extra-?\s?thyroidal|\bETE\b|invad(?:es|ing)\s+(?:the\s+)?(?:strap|capsule|trachea)") {
        margin := 3, mname := "extrathyroidal extension"
    } else if RegExMatch(t, "i)lobulated|irregular|spiculated|angular|microlobulated") {
        margin := 2, mname := "lobulated/irregular margins"
    } else if RegExMatch(t, "i)smooth|well[- ]?(?:defined|circumscribed)|circumscribed|ill[- ]?defined") {
        margin := 0, mname := "smooth margins"
    } else {
        margin := 0, mname := "margins not stated"
    }
    ; Echogenic foci (additive)
    foci := 0, fnames := ""
    if RegExMatch(t, "i)microcalcification|punctate\s+(?:echogenic\s+foci|calcification)|psammoma") {
        foci += 3, fnames .= "punctate echogenic foci (3) "
    }
    if RegExMatch(t, "i)peripheral\s+(?:rim\s+)?calcification|rim\s+calcification|eggshell|peripheral\s+calcific") {
        foci += 2, fnames .= "peripheral calcifications (2) "
    }
    if RegExMatch(t, "i)macro-?\s?calcification|coarse\s+calcification|large\s+calcification") {
        foci += 1, fnames .= "macrocalcifications (1) "
    }
    if (fnames = "")
        fnames := RegExMatch(t, "i)comet[- ]tail") ? "comet-tail artifacts (0) " : "no echogenic foci (0) "

    total := comp + echo + shape + margin + foci
    detail := cname " (" comp "), " ename " (" echo "), " sname " (" shape "), " mname " (" margin "), " Trim(fnames)
    return {total: total, detail: detail, missing: Trim(missing)}
}

PE_TIRADSLevel(pts) => pts >= 7 ? 5 : pts >= 4 ? 4 : pts = 3 ? 3 : pts = 2 ? 2 : 1
PE_TIRADSName(tr) => ["benign", "not suspicious", "mildly suspicious", "moderately suspicious", "highly suspicious"][tr]

PE_TIRADSRec(tr, cm) {
    static fna := [0, 0, 2.5, 1.5, 1.0], fu := [0, 0, 1.5, 1.0, 0.5]
    static when := ["", "", "ultrasound at 1, 3 and 5 years", "ultrasound at 1, 2, 3 and 5 years", "ultrasound annually for up to 5 years"]
    if (tr <= 2)
        return "No FNA."
    if (cm >= fna[tr])
        return "FNA recommended (TR" tr " nodule " PE_Fmt(fna[tr]) " cm or larger)."
    if (cm >= fu[tr])
        return "Follow-up " when[tr] " (TR" tr " nodule " PE_Fmt(fu[tr]) " cm or larger)."
    return "No FNA or follow-up needed based on size."
}

PE_ThyroidLoc(s) {
    loc := ""
    if RegExMatch(s, "i)\bisthmus")
        loc := "isthmus"
    else if RegExMatch(s, "i)\b(right|left)\b", &m)
        loc := StrLower(m[1]) " lobe"
    if RegExMatch(s, "i)\b(upper|mid(?:dle)?|lower|inferior|superior)\s*(?:pole|portion|third)?", &p) && loc != "isthmus"
        loc := Trim(loc " " StrLower(p[1]) " pole")
    return loc
}

; ---------------- OVARIAN / ADNEXAL CYST: O-RADS US + SRU ----------------
; Classic benign cysts only (simple, hemorrhagic, endometrioma, dermoid).
; Category: O-RADS US. Follow-up: SRU consensus (simple cysts: Levine et al.
; Radiology 2019; hemorrhagic/endometrioma/dermoid: Levine et al. Radiology 2010).
PE_ORADS(text) {
    t := RegExReplace(text, "\R", " ")
    t := StrReplace(t, Chr(0xD7), "x")
    cm := PE_TIRADSSize(t)
    if (cm <= 0)
        return PE_Fail("Could not find the cyst size.`n`nExample: Simple right ovarian cyst measuring 4.2 x 3.8 x 3.5 cm in a premenopausal patient.")
    if RegExMatch(t, "i)papillary|solid\s+(?:component|nodule|portion|area)|mural\s+nodul|thick(?:ened)?\s+septa|irregular\s+(?:wall|septa)|internal\s+(?:blood\s+)?flow|vascular\s+(?:solid|septa)|multilocular|ascites")
        return PE_Fail("This lesion has features that are not a classic benign cyst (solid component, papillary projection, thick/irregular septation, flow or multilocularity).`n`nUse the full O-RADS US lexicon (O-RADS 3-5); no automatic follow-up recommendation.")
    type := ""
    if RegExMatch(t, "i)dermoid|teratoma|echogenic\s+plug|dermoid\s+mesh|rokitansky")
        type := "dermoid"
    else if RegExMatch(t, "i)endometrioma|ground[- ]?glass|homogeneous\s+low[- ]level\s+echoes|chocolate")
        type := "endometrioma"
    else if RegExMatch(t, "i)hemorrhag|haemorrhag|reticular|lace-?like|fishnet|retract(?:ing|ile)\s+clot|cobweb")
        type := "hemorrhagic"
    else if RegExMatch(t, "i)\bsimple\b|anechoic|unilocular\s+(?:thin|smooth)|thin[- ]walled")
        type := "simple"
    if (type = "")
        return PE_Fail("Found a " PE_Fmt(cm) " cm cyst but not its type.`n`nAdd a descriptor: simple / anechoic, hemorrhagic (reticular, retracting clot), endometrioma (ground-glass, low-level echoes) or dermoid (echogenic plug).")

    meno := ""
    if RegExMatch(t, "i)post-?\s?menopaus")
        meno := "post"
    else if RegExMatch(t, "i)pre-?\s?menopaus|reproductive[- ]age|\bLMP\b|last\s+menstrual|day\s+\d+\s+of\s+(?:her\s+)?cycle|pregnan")
        meno := "pre"
    else if RegExMatch(t, "i)\b(\d{2})[- ]?(?:year|yr|y)[- ]?(?:old|o\b)", &am) {
        age := am[1] + 0
        meno := age < 45 ? "pre" : age >= 55 ? "post" : ""
    }

    if (cm >= 10) {
        cat := "O-RADS US 3 (low risk)"
        rec := "Classic benign-appearing lesion 10 cm or larger: management by gynecologist; consider MRI (O-RADS MRI)."
        res := "`n`nOvarian/adnexal cyst: " PE_Fmt(cm) " cm " type " cyst. " cat ". " rec
    } else {
        cat := (type = "simple" && cm <= 3 && meno != "post") ? "O-RADS US 1 (normal ovary, physiologic follicle)" : "O-RADS US 2 (almost certainly benign)"
        if (meno = "")
            rec := "Premenopausal: " PE_ORADSRec(type, cm, "pre") " Postmenopausal: " PE_ORADSRec(type, cm, "post")
        else
            rec := PE_ORADSRec(type, cm, meno)
        if (type = "simple" && cm <= 3 && meno = "")
            cat := "O-RADS US 1 if premenopausal (physiologic follicle), O-RADS US 2 if postmenopausal"
        res := "`n`nOvarian/adnexal cyst: " PE_Fmt(cm) " cm " type " cyst" (meno != "" ? " in a " meno "menopausal patient" : "") ". " cat ". " rec
    }
    res .= "`nRef: O-RADS US v2022 (ACR); follow-up per SRU consensus (Levine et al. Radiology 2010;256:943-954 and 2019;293:359-371)."
    vals := [["Size (largest)", PE_Fmt(cm) " cm"], ["Type", type], ["Menopausal status", meno = "" ? "not stated (both given)" : meno "menopausal"], ["Category", cat]]
    return PE_Ok("Ovarian Cyst (O-RADS / SRU)", vals, res, meno = "" ? 75 : 90, "", true)
}

PE_ORADSRec(type, cm, meno) {
    switch type {
        case "simple":
            if (meno = "pre") {
                if (cm <= 3)
                    return "Physiologic follicle; no follow-up."
                if (cm <= 5)
                    return "No follow-up needed."
                if (cm <= 7)
                    return "Follow-up ultrasound in 1 year."
                return "MRI or surgical evaluation."
            }
            if (cm <= 1)
                return "No follow-up needed."
            if (cm <= 7)
                return "Follow-up ultrasound in 1 year."
            return "MRI or surgical evaluation."
        case "hemorrhagic":
            if (meno = "pre")
                return cm <= 5 ? "No follow-up needed." : "Follow-up ultrasound in 6-12 weeks to confirm resolution."
            return "Early postmenopause: follow-up ultrasound in 6-12 weeks to confirm resolution; late postmenopause: surgical evaluation."
        case "endometrioma":
            return meno = "pre" ? "Follow-up ultrasound in 6-12 weeks, then yearly if not surgically removed." : "Surgical evaluation may be considered; otherwise follow-up ultrasound in 6-12 weeks, then yearly."
        case "dermoid":
            return "Yearly follow-up ultrasound if not surgically removed."
    }
    return ""
}

; ---------------- BONE AGE: Greulich & Pyle ----------------
; Parse an age in many dictation styles -> months (or "" if none)
; "13 years 6 months", "13y6m", "13 yrs 6 mos", "13.5 years", "13 and a half years",
; "13 1/2", "13 6/12", "13-6/12", "162 months", "13:6", "13 years"
PE_AgeMonths(s) {
    s := Trim(RegExReplace(s, "\s+", " "))
    uY := "(?:years?|yrs?|y/?o|y\.?o\.?|y)"
    uM := "(?:months?|mos?|m)"
    if RegExMatch(s, "^(\d+)\s*:\s*(\d+)$", &m)          ; "13:6"
        return m[1] * 12 + m[2]
    if RegExMatch(s, "^(\d+(?:\.\d+)?)$", &m)             ; bare number = years
        return Round(m[1] * 12)
    if RegExMatch(s, "i)(\d+)\s*-?\s*" uY "\.?\s*and\s+(?:a\s+)?half", &m)   ; "9 years and a half"
        return m[1] * 12 + 6
    if RegExMatch(s, "i)(\d+)\s*-?\s*" uY "\.?(?:\s*(?:,|and|\+)?\s*(\d+(?:\.\d+)?)\s*-?\s*" uM "\b)", &m)
        return m[1] * 12 + Round(m[2] + 0)
    if RegExMatch(s, "i)(\d+)\s*(?:-|\s)\s*(\d+)\s*/\s*12\b", &m)
        return m[1] * 12 + m[2]
    if RegExMatch(s, "i)(\d+)\s*(?:and\s+(?:a\s+)?half|-?\s*1/2|" Chr(0xBD) ")", &m)
        return m[1] * 12 + 6
    if RegExMatch(s, "i)(\d+)\s*(?:and\s+(?:a\s+)?quarter|-?\s*1/4)", &m)
        return m[1] * 12 + 3
    if RegExMatch(s, "i)(\d+)\s*(?:and\s+three\s+quarters|-?\s*3/4)", &m)
        return m[1] * 12 + 9
    if RegExMatch(s, "i)(\d+(?:\.\d+)?)\s*-?\s*" uY "\b", &m)
        return Round(m[1] * 12)
    if RegExMatch(s, "i)(\d+)\s*-?\s*" uM "\b", &m)
        return m[1] + 0
    return ""
}

PE_AgeText(months) {
    months := Round(months)
    y := months // 12, m := Mod(months, 12)
    return y " year" (y = 1 ? "" : "s") (m ? " " m " month" (m = 1 ? "" : "s") : "")
}

; Chronological age, sex and bone age from report text (header and/or dictation)
PE_BoneAgeExtract(text) {
    t := RegExReplace(text, "\R", " ")
    r := {chrono: "", sex: "", bone: "", dob: "", examDate: ""}
    ; Bone age written in the dictation
    if RegExMatch(t, "i)bone\s+age\s*(?:is|of|:|=|estimated\s+(?:at|to\s+be)|approximately|approx\.?|consistent\s+with|corresponds\s+to)?\s*(?:approximately\s+|about\s+)?(.{1,40}?)(?:[.;,](?!\d)|\(|$|\s+(?:which|by|per|using|according)|\s+and\s+(?!(?:a\s+)?half|\d))", &m)
        r.bone := PE_AgeMonths(m[1])
    ; Chronological age stated directly
    if RegExMatch(t, "i)(?:chronologic(?:al)?\s+age|actual\s+age|patient(?:'s)?\s+age|(?<!bone\s)(?<!bone)\bage)\s*(?:is|of|:|=)?\s*(.{1,30}?)(?:[.;,](?!\d)|\(|$|\s+(?:male|female|boy|girl|M\b|F\b))", &m)
        r.chrono := PE_AgeMonths(m[1])
    if (r.chrono = "" && RegExMatch(t, "i)(\d+)[- ](?:year|yr)[- ]?(?:s)?[- ](?:and[- ])?(\d+)[- ]month[- ]?(?:s)?[- ]old", &m))
        r.chrono := m[1] * 12 + m[2]
    if (r.chrono = "" && RegExMatch(t, "i)(\d+(?:\.\d+)?)[- ]?(?:year|yr)s?[- ]?old|(\d+(?:\.\d+)?)\s*(?:yo|y/o|y\.o\.)\b", &m))
        r.chrono := Round((m[1] != "" ? m[1] : m[2]) * 12)
    if (r.chrono = "" && RegExMatch(t, "i)(\d+)[- ]month[- ]old", &m))
        r.chrono := m[1] + 0
    ; DOB + exam date (more exact than a rounded age)
    dateRe := "(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})"
    if RegExMatch(t, "i)(?:DOB|D\.O\.B\.|date\s+of\s+birth|birth\s*date|born)\s*:?\s*" dateRe, &d) {
        r.dob := PE_Ymd(d[1], d[2], d[3])
        ex := ""
        if RegExMatch(t, "i)(?:exam(?:ination)?|study|service|procedure|scan|accession)\s*(?:date|dt)?\s*:?\s*" dateRe, &e)
            ex := PE_Ymd(e[1], e[2], e[3])
        r.examDate := ex != "" ? ex : FormatTime(, "yyyyMMdd")
        if (r.dob != "" && r.dob < r.examDate)
            r.chrono := PE_MonthsBetween(r.dob, r.examDate)
    }
    ; Sex
    if RegExMatch(t, "i)\b(female|girl|f)\b(?!\.?\s*(?:u|/u))", &s) || RegExMatch(t, "i)\b(male|boy|m)\b", &s)
        r.sex := RegExMatch(s[1], "i)^(?:female|girl|f)$") ? "Female" : "Male"
    if RegExMatch(t, "i)\b(?:sex|gender)\s*:?\s*(m|f|male|female)\b", &s)
        r.sex := RegExMatch(s[1], "i)^f") ? "Female" : "Male"
    return r
}

PE_Ymd(mo, d, y) {
    y := y + 0
    if (y < 100)
        y += (y > Mod(A_YYYY, 100) ? 1900 : 2000)
    if (mo < 1 || mo > 12 || d < 1 || d > 31)
        return ""
    return Format("{:04}{:02}{:02}", y, mo, d)
}

PE_MonthsBetween(a, b) {
    m := (SubStr(b, 1, 4) - SubStr(a, 1, 4)) * 12 + (SubStr(b, 5, 2) - SubStr(a, 5, 2))
    if (SubStr(b, 7, 2) + 0 < SubStr(a, 7, 2) + 0)
        m -= 1
    return m
}

; Greulich & Pyle standard deviations (months) by chronological age (months),
; Brush Foundation data as tabulated in the G&P atlas. Linear interpolation.
PE_GPSD(chronoMonths, sex) {
    static ages := [3, 6, 9, 12, 18, 24, 30, 36, 42, 48, 54, 60, 72, 84, 96, 108, 120, 132, 144, 156, 168, 180, 192, 204]
    static male := [0.72, 1.13, 1.43, 1.97, 3.52, 3.92, 4.52, 5.08, 5.40, 6.66, 8.36, 8.79, 9.17, 8.91, 9.10, 11.00, 11.38, 10.77, 10.44, 10.72, 11.32, 12.86, 13.05, 13.84]
    static female := [0.72, 1.16, 1.36, 1.77, 3.49, 4.64, 5.37, 5.97, 7.48, 8.98, 10.73, 11.65, 10.23, 9.64, 10.23, 10.74, 11.73, 11.94, 10.24, 10.67, 11.30, 9.23, 7.31, 7.31]
    sd := (sex = "Female") ? female : male
    if (chronoMonths <= ages[1])
        return sd[1]
    if (chronoMonths >= ages[ages.Length])
        return sd[ages.Length]
    Loop ages.Length - 1 {
        i := A_Index
        if (chronoMonths <= ages[i + 1]) {
            f := (chronoMonths - ages[i]) / (ages[i + 1] - ages[i])
            return sd[i] + f * (sd[i + 1] - sd[i])
        }
    }
    return sd[ages.Length]
}

; Standard bone age paragraph
PE_BoneAgeReport(boneMonths, chronoMonths, sex) {
    if (boneMonths = "" || chronoMonths = "" || sex = "")
        return PE_Fail("Need bone age, chronological age and sex.")
    sd := PE_GPSD(chronoMonths, sex)
    diff := boneMonths - chronoMonths
    z := sd > 0 ? diff / sd : 0
    if (Abs(z) <= 2)
        interp := "The bone age is within normal limits (within 2 standard deviations of the chronological age)."
    else if (z > 0)
        interp := "The bone age is advanced (greater than 2 standard deviations above the chronological age)."
    else
        interp := "The bone age is delayed (greater than 2 standard deviations below the chronological age)."
    who := (sex = "Female") ? "a girl" : "a boy"
    r := " Using the standards of Greulich and Pyle, the bone age is estimated to be " PE_AgeText(boneMonths) "."
    r .= " The chronological age is " PE_AgeText(chronoMonths) "."
    r .= " The standard deviation for " who " of this chronological age is " PE_Fmt(sd, 1) " months."
    r .= " The bone age is " (diff = 0 ? "equal to" : PE_Fmt(Abs(diff), 0) " month" (Abs(diff) = 1 ? "" : "s") (diff > 0 ? " greater than" : " less than")) " the chronological age (" (z >= 0 ? "+" : "-") PE_Fmt(Abs(z), 1) " SD). " interp
    vals := [["Bone age", PE_AgeText(boneMonths)], ["Chronological age", PE_AgeText(chronoMonths)], ["Sex", sex], ["SD at this age", PE_Fmt(sd, 1) " months"], ["Difference", (diff >= 0 ? "+" : "") diff " months (" (z >= 0 ? "+" : "") PE_Fmt(z, 1) " SD)"]]
    return PE_Ok("Bone Age (Greulich & Pyle)", vals, r, 90)
}


; -----------------------------------------
; Bone Age (Greulich & Pyle) window
; WHY: The reader types only the bone age; chronological age and sex are taken
;      from the highlighted text / report header (DOB + exam date, "Age: 12y 3m",
;      "12-year-old girl", ...). Every field stays editable; preview updates live.
; -----------------------------------------
global BoneAgeGuiObj := "", g_BoneAgeText := ""

ShowBoneAgeGui(prefill := "") {
    global BoneAgeGuiObj
    if IsObject(BoneAgeGuiObj)
        try BoneAgeGuiObj.Destroy()
    x := PE_BoneAgeExtract(prefill)
    g := Gui("+AlwaysOnTop -MinimizeBox", "Bone Age (Greulich & Pyle)")
    g.SetFont("s10", "Segoe UI")
    g.OnEvent("Close", BoneAgeClose)
    g.OnEvent("Escape", BoneAgeClose)
    g.Add("Text", "x10 y12 w160", "Bone age (as read):")
    g.eBone := g.Add("Edit", "x175 y9 w230", x.bone != "" ? PE_AgeText(x.bone) : "")
    g.Add("Text", "x10 y+12 w160", "Chronological age:")
    g.eChrono := g.Add("Edit", "x175 yp-3 w230", (x.chrono != "" && x.dob = "") ? PE_AgeText(x.chrono) : "")
    g.Add("Text", "x10 y+12 w160", "or DOB  /  exam date:")
    g.eDob := g.Add("Edit", "x175 yp-3 w110", x.dob != "" ? FormatTime(x.dob, "M/d/yyyy") : "")
    g.eExam := g.Add("Edit", "x+10 yp w110", x.examDate != "" ? FormatTime(x.examDate, "M/d/yyyy") : FormatTime(, "M/d/yyyy"))
    g.Add("Text", "x10 y+12 w160", "Sex:")
    g.ddSex := g.Add("DropDownList", "x175 yp-3 w110" (x.sex = "Male" ? " Choose1" : x.sex = "Female" ? " Choose2" : ""), ["Male", "Female"])
    g.Add("Button", "x295 yp-1 w110", "Read report").OnEvent("Click", BoneAgeReadReport)
    g.SetFont("s8 c808080")
    g.Add("Text", "x10 y+8 w400", "Any style works: 13 years 6 months, 13y6m, 13.5, 13 1/2, 13 6/12, 13:6, 162 months")
    g.SetFont("s10 cDefault")
    g.preview := g.Add("Edit", "x10 y+6 w395 r7 ReadOnly")
    g.Add("Button", "x10 y+10 w125 Default", "Insert").OnEvent("Click", BoneAgeInsert)
    g.Add("Button", "x+10 yp w125", "Copy").OnEvent("Click", BoneAgeCopy)
    g.Add("Button", "x+10 yp w125", "Cancel").OnEvent("Click", BoneAgeClose)
    for c in [g.eBone, g.eChrono, g.eDob, g.eExam]
        c.OnEvent("Change", BoneAgeUpdate)
    g.ddSex.OnEvent("Change", BoneAgeUpdate)
    BoneAgeGuiObj := g
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    g.Show("x" (mx + 10) " y" (my + 10) " AutoSize")
    RA_Front(g.Hwnd)
    g.eBone.Focus()
    BoneAgeUpdate()
}

BoneAgeUpdate(*) {
    global BoneAgeGuiObj, g_BoneAgeText
    g := BoneAgeGuiObj
    if !IsObject(g)
        return
    bone := PE_AgeMonths(g.eBone.Value)
    chrono := ""
    dob := PE_ParseDate(g.eDob.Value), exam := PE_ParseDate(g.eExam.Value)
    if (dob != "" && exam != "" && dob < exam)
        chrono := PE_MonthsBetween(dob, exam)
    else
        chrono := PE_AgeMonths(g.eChrono.Value)
    sex := g.ddSex.Text
    g_BoneAgeText := ""
    if (bone = "") {
        g.preview.Value := "Type the bone age above."
        return
    }
    if (chrono = "") {
        g.preview.Value := "Enter the chronological age, or DOB and exam date."
        return
    }
    if (sex = "") {
        g.preview.Value := "Select the sex."
        return
    }
    r := PE_BoneAgeReport(bone, chrono, sex)
    g_BoneAgeText := r.text
    g.preview.Value := Trim(r.text)
}

PE_ParseDate(s) {
    if RegExMatch(s, "(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})", &d)
        return PE_Ymd(d[1], d[2], d[3])
    return ""
}

; Read age / DOB / sex from the whole report (cursor ends at the end of the report)
BoneAgeReadReport(*) {
    global BoneAgeGuiObj
    g := BoneAgeGuiObj
    RA_ActivateTarget()
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^a")
    Sleep(50)
    Send("^c")
    txt := ClipWait(1) ? A_Clipboard : ""
    A_Clipboard := saved
    Send("{Right}")                ; clear the select-all
    if (txt = "") {
        MsgBox("Could not read the report text.", "Bone Age", 0x40030)
        return
    }
    x := PE_BoneAgeExtract(txt)
    if (x.dob != "") {
        g.eDob.Value := FormatTime(x.dob, "M/d/yyyy")
        g.eExam.Value := FormatTime(x.examDate, "M/d/yyyy")
    } else if (x.chrono != "") {
        g.eChrono.Value := PE_AgeText(x.chrono)
    }
    if (x.sex != "")
        g.ddSex.Choose(x.sex = "Male" ? 1 : 2)
    if (x.bone != "" && g.eBone.Value = "")
        g.eBone.Value := PE_AgeText(x.bone)
    RA_Front(g.Hwnd)
    BoneAgeUpdate()
}

BoneAgeInsert(*) {
    global BoneAgeGuiObj, g_BoneAgeText
    Critical()
    BoneAgeUpdate()
    if (g_BoneAgeText = "") {
        MsgBox("Fill in bone age, chronological age and sex first.", "Bone Age", 0x40030)
        return
    }
    txt := g_BoneAgeText
    RA_ActivateTarget()
    try BoneAgeGuiObj.Hide()
    InsertAfterSelection(txt)
    BoneAgeClose()
}

BoneAgeCopy(*) {
    global g_BoneAgeText
    BoneAgeUpdate()
    if (g_BoneAgeText = "")
        return
    A_Clipboard := Trim(g_BoneAgeText)
    ToolTip("Copied to clipboard")
    SetTimer(RemoveToolTip, -1500)
}

BoneAgeClose(*) {
    global BoneAgeGuiObj
    try BoneAgeGuiObj.Destroy()
    BoneAgeGuiObj := ""
}

; -----------------------------------------
; Smart parse entry points (kept for menu handlers)
; -----------------------------------------
ParseAndInsertVolume(input) => SP_Run(PE_Volume(input))
ParseAndInsertRVLV(input) => SP_Run(PE_RVLV(input))
ParseAndInsertNASCET(input) => SP_Run(PE_NASCET(input))
ParseAndInsertStenosis(input) => SP_Run(PE_Stenosis(input))
ParseAndInsertAdrenalWashout(input) => SP_Run(PE_Adrenal(input))
ParseAndInsertFleischner(input) => SP_Run(PE_Fleischner(input))
ParseAndInsertICH(input) => SP_Run(PE_ICH(input))
ParseAndInsertDate(input) => SP_Run(PE_Date(input))
ParseAndInsertAuto(input) => SP_Run(PE_Auto(input))
ParseAndInsertTIRADS(input) => SP_Run(PE_TIRADS(input))
ParseAndInsertORADS(input) => SP_Run(PE_ORADS(input))

; -----------------------------------------
; Generate Fleischner recommendation for specific nodule sizes and risk level
; -----------------------------------------
GenerateFleischnerRec(maxSolid, maxSubsolid, maxPartsolid, isMultiple, risk) {
    result := ""
    number := isMultiple ? "Multiple" : "Single"

    ; Solid nodules take priority
    if (maxSolid > 0) {
        if (maxSolid < 6) {
            if (risk = "Low risk")
                result .= "- Solid " . maxSolid . "mm: No routine follow-up required."
            else
                result .= "- Solid " . maxSolid . "mm: Optional CT at 12 months."
        } else if (maxSolid <= 8) {
            if (isMultiple) {
                if (risk = "Low risk")
                    result .= "- Solid " . maxSolid . "mm (multiple): CT at 3-6 months, then consider CT at 18-24 months."
                else
                    result .= "- Solid " . maxSolid . "mm (multiple): CT at 3-6 months, then CT at 18-24 months."
            } else {
                if (risk = "Low risk")
                    result .= "- Solid " . maxSolid . "mm: CT at 6-12 months, then consider CT at 18-24 months."
                else
                    result .= "- Solid " . maxSolid . "mm: CT at 6-12 months, then CT at 18-24 months."
            }
        } else {
            result .= "- Solid " . maxSolid . "mm: Consider CT at 3 months, PET/CT, or tissue sampling."
        }
    }

    ; Subsolid/Ground glass nodules
    if (maxSubsolid > 0) {
        if (result != "")
            result .= "`n"

        if (maxSubsolid < 6) {
            if (isMultiple)
                result .= "- Ground glass " . maxSubsolid . "mm (multiple): CT at 3-6 months. If stable, consider CT at 2 and 4 years."
            else
                result .= "- Ground glass " . maxSubsolid . "mm: No routine follow-up required."
        } else {
            if (isMultiple)
                result .= "- Ground glass " . maxSubsolid . "mm (multiple): CT at 3-6 months, subsequent management based on most suspicious nodule."
            else
                result .= "- Ground glass " . maxSubsolid . "mm: CT at 6-12 months, then every 2 years for 5 years."
        }
    }

    ; Part-solid nodules
    if (maxPartsolid > 0) {
        if (result != "")
            result .= "`n"

        if (maxPartsolid < 6) {
            result .= "- Part-solid " . maxPartsolid . "mm: No routine follow-up required."
        } else {
            if (isMultiple)
                result .= "- Part-solid " . maxPartsolid . "mm (multiple): CT at 3-6 months. If stable, annual CT for 5 years."
            else
                result .= "- Part-solid " . maxPartsolid . "mm: CT at 3-6 months. If stable, annual CT for 5 years. If solid component >=6mm, consider PET/CT or biopsy."
        }
    }

    return result
}

; =========================================
; CALCULATOR 7: ICH Volume (ABC/2)
; WHY: Calculate intracerebral hemorrhage volume using ABC/2 method
; ARCHITECTURE: Smart parse + GUI fallback pattern
; =========================================

; -----------------------------------------
; ICH Volume GUI
; -----------------------------------------
global ICHGuiObj := ""

ShowICHVolumeGui() {
    global ICHGuiObj
    GetGuiPosition(&xPos, &yPos)

    ICHGuiObj := Gui("+AlwaysOnTop")
    ICHGuiObj.OnEvent("Close", ICHGuiClose)
    ICHGuiObj.OnEvent("Escape", ICHGuiClose)
    ICHGuiObj.Add("Text", "x10 y10 w280", "ICH Volume Calculator (ABC/2)")
    ICHGuiObj.Add("Text", "x10 y40", "A (longest axis, cm):")
    ICHGuiObj.Add("Edit", "x140 y37 w60 vICHDimA")
    ICHGuiObj.Add("Text", "x10 y70", "B (perpendicular, cm):")
    ICHGuiObj.Add("Edit", "x140 y67 w60 vICHDimB")
    ICHGuiObj.Add("Text", "x10 y100", "C (# of slices x thickness, cm):")
    ICHGuiObj.Add("Edit", "x200 y97 w60 vICHDimC")
    ICHGuiObj.Add("Button", "x30 y135 w80", "Calculate").OnEvent("Click", CalcICH)
    ICHGuiObj.Add("Button", "x130 y135 w80", "Cancel").OnEvent("Click", ICHGuiClose)
    ICHGuiObj.Show("x" xPos " y" yPos " w280 h175")
    RA_Front(ICHGuiObj.Hwnd)
    ICHGuiObj.Title := "ICH Volume (ABC/2)"
}

ShowICHVolumeGuiPrefilled(a, b, c) {
    global ICHGuiObj
    GetGuiPosition(&xPos, &yPos)

    aVal := Round(a, 1)
    bVal := Round(b, 1)
    cVal := Round(c, 1)

    ICHGuiObj := Gui("+AlwaysOnTop")
    ICHGuiObj.OnEvent("Close", ICHGuiClose)
    ICHGuiObj.OnEvent("Escape", ICHGuiClose)
    ICHGuiObj.Add("Text", "x10 y10 w280", "ICH Volume Calculator (Pre-filled)")
    ICHGuiObj.Add("Text", "x10 y40", "A (longest axis, cm):")
    ICHGuiObj.Add("Edit", "x140 y37 w60 vICHDimA", aVal)
    ICHGuiObj.Add("Text", "x10 y70", "B (perpendicular, cm):")
    ICHGuiObj.Add("Edit", "x140 y67 w60 vICHDimB", bVal)
    ICHGuiObj.Add("Text", "x10 y100", "C (# of slices x thickness, cm):")
    ICHGuiObj.Add("Edit", "x200 y97 w60 vICHDimC", cVal)
    ICHGuiObj.Add("Button", "x30 y135 w80", "Calculate").OnEvent("Click", CalcICH)
    ICHGuiObj.Add("Button", "x130 y135 w80", "Cancel").OnEvent("Click", ICHGuiClose)
    ICHGuiObj.Show("x" xPos " y" yPos " w280 h175")
    RA_Front(ICHGuiObj.Hwnd)
    ICHGuiObj.Title := "ICH Volume (ABC/2)"
}

ICHGuiClose(*) {
    global ICHGuiObj
    ICHGuiObj.Destroy()
}

CalcICH(*) {
    global ICHGuiObj
    saved := ICHGuiObj.Submit(false)

    if (saved.ICHDimA = "" || saved.ICHDimB = "" || saved.ICHDimC = "") {
        MsgBox("Please enter all three dimensions.", "Error", 0x40010)
        return
    }

    a := saved.ICHDimA + 0
    b := saved.ICHDimB + 0
    c := saved.ICHDimC + 0

    if (a <= 0 || b <= 0 || c <= 0) {
        MsgBox("All dimensions must be greater than 0.", "Error", 0x40010)
        return
    }

    ; ABC/2 formula
    volume := (a * b * c) / 2
    volume := Round(volume, 1)

    ; Sentence style output
    result := " ICH volume approximately " . volume . " cc (ABC/2: " . Round(a, 1) . " x " . Round(b, 1) . " x " . Round(c, 1) . " cm)."

    ICHGuiObj.Destroy()
    ShowResult(result)
}

; =========================================
; CALCULATOR 8: Follow-up Date Calculator
; WHY: Calculate follow-up dates from interval specifications
; ARCHITECTURE: Smart parse + GUI fallback pattern
; =========================================

; -----------------------------------------
; Calculate Future Date (calendar months/years; day clamped to month length)
; -----------------------------------------
CalculateFutureDate(interval, unit) {
    today := FormatTime(, "yyyyMMdd")
    if (unit = "days")
        d := DateAdd(today, interval, "days")
    else if (unit = "weeks")
        d := DateAdd(today, interval * 7, "days")
    else {
        months := (unit = "years") ? interval * 12 : interval
        y := A_YYYY + 0, m := A_MM + 0 + months, day := A_DD + 0
        y += Floor((m - 1) / 12)
        m := Mod(m - 1, 12) + 1
        first := Format("{:04}{:02}01", y, m)
        nextFirst := SubStr(DateAdd(first, 32, "days"), 1, 6) "01"
        dim := DateDiff(nextFirst, first, "days")
        d := Format("{:04}{:02}{:02}", y, m, Min(day, dim))
    }
    return FormatTime(d, "MMMM d, yyyy")
}

; -----------------------------------------
; Date Calculator GUI
; -----------------------------------------
global DateGuiObj := ""

ShowDateCalculatorGui() {
    global DateGuiObj
    GetGuiPosition(&xPos, &yPos)

    DateGuiObj := Gui("+AlwaysOnTop")
    DateGuiObj.OnEvent("Close", DateGuiClose)
    DateGuiObj.OnEvent("Escape", DateGuiClose)
    DateGuiObj.Add("Text", "x10 y10 w250", "Follow-up Date Calculator")
    DateGuiObj.Add("Text", "x10 y45", "Interval:")
    DateGuiObj.Add("Edit", "x80 y42 w50 vDateInterval", "3")
    DateGuiObj.Add("DropDownList", "x140 y42 w100 vDateUnit Choose1", ["Months", "Weeks", "Days", "Years"])
    DateGuiObj.Add("Button", "x30 y85 w80", "Calculate").OnEvent("Click", CalcDate)
    DateGuiObj.Add("Button", "x130 y85 w80", "Cancel").OnEvent("Click", DateGuiClose)
    DateGuiObj.Show("x" xPos " y" yPos " w260 h125")
    RA_Front(DateGuiObj.Hwnd)
    DateGuiObj.Title := "Follow-up Date"
}

ShowDateCalculatorGuiPrefilled(interval, unit) {
    global DateGuiObj
    GetGuiPosition(&xPos, &yPos)

    ; Determine dropdown selection
    unitSelect := 1
    if (unit = "weeks")
        unitSelect := 2
    else if (unit = "days")
        unitSelect := 3
    else if (unit = "years")
        unitSelect := 4

    DateGuiObj := Gui("+AlwaysOnTop")
    DateGuiObj.OnEvent("Close", DateGuiClose)
    DateGuiObj.OnEvent("Escape", DateGuiClose)
    DateGuiObj.Add("Text", "x10 y10 w250", "Follow-up Date Calculator (Pre-filled)")
    DateGuiObj.Add("Text", "x10 y45", "Interval:")
    DateGuiObj.Add("Edit", "x80 y42 w50 vDateInterval", interval)
    DateGuiObj.Add("DropDownList", "x140 y42 w100 vDateUnit Choose" unitSelect, ["Months", "Weeks", "Days", "Years"])
    DateGuiObj.Add("Button", "x30 y85 w80", "Calculate").OnEvent("Click", CalcDate)
    DateGuiObj.Add("Button", "x130 y85 w80", "Cancel").OnEvent("Click", DateGuiClose)
    DateGuiObj.Show("x" xPos " y" yPos " w260 h125")
    RA_Front(DateGuiObj.Hwnd)
    DateGuiObj.Title := "Follow-up Date"
}

DateGuiClose(*) {
    global DateGuiObj
    DateGuiObj.Destroy()
}

CalcDate(*) {
    global DateGuiObj
    saved := DateGuiObj.Submit(false)

    if (saved.DateInterval = "") {
        MsgBox("Please enter an interval.", "Error", 0x40010)
        return
    }

    interval := saved.DateInterval + 0
    if (interval <= 0) {
        MsgBox("Interval must be greater than 0.", "Error", 0x40010)
        return
    }

    ; Normalize unit name
    unit := "months"
    if (saved.DateUnit = "Weeks")
        unit := "weeks"
    else if (saved.DateUnit = "Days")
        unit := "days"
    else if (saved.DateUnit = "Years")
        unit := "years"

    ; Calculate future date
    futureDate := CalculateFutureDate(interval, unit)

    ; Sentence style output
    result := " Recommend follow-up in " . interval . " " . unit . " (approximately " . futureDate . ")."

    DateGuiObj.Destroy()
    ShowResult(result)
}

; =========================================
; TOOL 6: Sectra History Copy
; =========================================
CopySectraHistory() {
    global SectraWindowTitle, g_SelectedText, TargetApps

    ; Save clipboard
    ClipSaved := ClipboardAll()
    A_Clipboard := ""

    ; Check if text is already selected (from our earlier capture)
    if (g_SelectedText != "") {
        A_Clipboard := g_SelectedText
    } else {
        ; Try to get from Sectra
        if (WinExist(SectraWindowTitle)) {
            WinActivate(SectraWindowTitle)
            if (WinWaitActive(SectraWindowTitle, , 2)) {
                Send("^c")
                ClipWait(1)
            }
        }
    }

    if (A_Clipboard = "") {
        MsgBox("No text found. Select history text in Sectra first.", "Info", 0x40030)
        A_Clipboard := ClipSaved
        return
    }

    historyText := A_Clipboard

    ; Find PowerScribe and paste
    foundPS := false
    for index, app in TargetApps {
        if (InStr(app, "PowerScribe") || InStr(app, "Nuance")) {
            if (WinExist(app)) {
                WinActivate(app)
                if (WinWaitActive(app, , 2)) {
                    foundPS := true
                    break
                }
            }
        }
    }

    if (!foundPS) {
        ; Just activate any target app
        WinActivate("ahk_exe notepad.exe")
        WinWaitActive("ahk_exe notepad.exe", , 1)
    }

    Sleep(100)
    Send("^v")

    ; Restore clipboard
    Sleep(100)
    A_Clipboard := ClipSaved

    ToolTip("History pasted!")
    SetTimer(RemoveToolTip, -1500)
    return
}

RemoveToolTip(*) {
    ToolTip()
}

; =========================================
; Settings GUI
; =========================================
global SettingsGuiObj := ""

ShowSettings() {
    global IncludeDatamining, ShowCitations, DataminingPhrase, DefaultSmartParse
    global SmartParseConfirmation, SmartParseFallbackToGUI
    global DefaultMeasurementUnit, RVLVOutputFormat, FleischnerInsertAfterImpression
    global ShowVolumeTools, ShowRVLVTools, ShowNASCETTools
    global ShowAdrenalTools, ShowFleischnerTools, ShowStenosisTools
    global ShowICHTools, ShowDateCalculator, QuickCallEnabled, ShowTIRADS, ShowORADS, ShowBoneAge, DarkTheme
    global SettingsGuiObj

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    dmChecked := IncludeDatamining ? "Checked" : ""
    citChecked := ShowCitations ? "Checked" : ""
    confirmChecked := SmartParseConfirmation ? "Checked" : ""
    fallbackChecked := SmartParseFallbackToGUI ? "Checked" : ""
    fleischnerImprChecked := FleischnerInsertAfterImpression ? "Checked" : ""

    ; Tool visibility checkboxes
    volChecked := ShowVolumeTools ? "Checked" : ""
    rvlvChecked := ShowRVLVTools ? "Checked" : ""
    nascetChecked := ShowNASCETTools ? "Checked" : ""
    adrenalChecked := ShowAdrenalTools ? "Checked" : ""
    fleischnerChecked := ShowFleischnerTools ? "Checked" : ""
    stenosisChecked := ShowStenosisTools ? "Checked" : ""
    ichChecked := ShowICHTools ? "Checked" : ""
    dateChecked := ShowDateCalculator ? "Checked" : ""
    qcChecked := QuickCallEnabled ? "Checked" : ""

    ; Determine which item to select in dropdown (1-based index)
    parseChoices := ["Auto", "Volume", "RVLV", "NASCET", "Stenosis", "Adrenal", "Fleischner", "ICH", "Date", "TIRADS", "ORADS"]
    smartParseSelect := 1
    for i, name in parseChoices {
        if (DefaultSmartParse = name)
            smartParseSelect := i
    }

    ; Unit selection
    unitSelect := (DefaultMeasurementUnit = "mm") ? 2 : 1

    ; RV/LV format selection
    rvlvSelect := (RVLVOutputFormat = "Inline") ? 2 : 1

    SettingsGuiObj := Gui("+AlwaysOnTop")
    SettingsGuiObj.OnEvent("Close", SettingsGuiClose)
    SettingsGuiObj.OnEvent("Escape", SettingsGuiClose)
    SettingsGuiObj.SetFont("s9", "Segoe UI")
    SettingsGuiObj.Add("Text", "x10 y10 w280", "RadAssist Settings")
    SettingsGuiObj.Add("Text", "x10 y40", "Default Quick Parse:")
    SettingsGuiObj.Add("DropDownList", "x130 y37 w120 vSetDefaultParse Choose" smartParseSelect, parseChoices)

    ; ---- left column
    SettingsGuiObj.Add("GroupBox", "x10 y65 w280 h170", "Tool Visibility (uncheck to hide)")
    SettingsGuiObj.Add("Checkbox", "x20 y85 w125 vSetShowVolume " volChecked, "Volume")
    SettingsGuiObj.Add("Checkbox", "x155 y85 w125 vSetShowRVLV " rvlvChecked, "RV/LV Ratio")
    SettingsGuiObj.Add("Checkbox", "x20 y108 w125 vSetShowNASCET " nascetChecked, "NASCET")
    SettingsGuiObj.Add("Checkbox", "x155 y108 w125 vSetShowAdrenal " adrenalChecked, "Adrenal")
    SettingsGuiObj.Add("Checkbox", "x20 y131 w125 vSetShowFleischner " fleischnerChecked, "Fleischner")
    SettingsGuiObj.Add("Checkbox", "x155 y131 w125 vSetShowStenosis " stenosisChecked, "Stenosis")
    SettingsGuiObj.Add("Checkbox", "x20 y154 w125 vSetShowICH " ichChecked, "ICH Volume")
    SettingsGuiObj.Add("Checkbox", "x155 y154 w125 vSetShowDate " dateChecked, "Date Calculator")
    SettingsGuiObj.Add("Checkbox", "x20 y177 w125 vSetShowTIRADS " (ShowTIRADS ? "Checked" : ""), "Thyroid TI-RADS")
    SettingsGuiObj.Add("Checkbox", "x155 y177 w125 vSetShowORADS " (ShowORADS ? "Checked" : ""), "Ovarian O-RADS")
    SettingsGuiObj.Add("Checkbox", "x20 y200 w260 vSetShowBoneAge " (ShowBoneAge ? "Checked" : ""), "Bone Age (Greulich && Pyle) - MSK/peds")

    SettingsGuiObj.Add("GroupBox", "x10 y245 w280 h105", "Smart Parse Options")
    SettingsGuiObj.Add("Checkbox", "x20 y265 w260 vSetConfirmation " confirmChecked, "Show confirmation dialog before insert")
    SettingsGuiObj.Add("Checkbox", "x20 y290 w260 vSetFallbackGUI " fallbackChecked, "Fall back to GUI when confidence low")
    SettingsGuiObj.Add("Text", "x20 y318", "Default units (no units in text):")
    SettingsGuiObj.Add("DropDownList", "x200 y315 w70 vSetDefaultUnit Choose" unitSelect, ["cm", "mm"])

    ; ---- right column
    SettingsGuiObj.Add("GroupBox", "x305 y65 w280 h80", "RV/LV && Fleischner Output")
    SettingsGuiObj.Add("Text", "x315 y85", "RV/LV format:")
    SettingsGuiObj.Add("DropDownList", "x400 y82 w80 vSetRVLVFormat Choose" rvlvSelect, ["Macro", "Inline"])
    SettingsGuiObj.Add("Text", "x488 y85 w90", "(Macro = cm)")
    SettingsGuiObj.Add("Checkbox", "x315 y112 w260 vSetFleischnerImpression " fleischnerImprChecked, "Insert Fleischner / TI-RADS at end of report")

    SettingsGuiObj.Add("GroupBox", "x305 y155 w280 h105", "Output Options")
    SettingsGuiObj.Add("Checkbox", "x315 y175 w260 vSetDatamine " dmChecked, "Include datamining phrase by default")
    SettingsGuiObj.Add("Checkbox", "x315 y200 w260 vSetCitations " citChecked, "Show citations in output")
    SettingsGuiObj.Add("Text", "x315 y228", "Datamining phrase:")
    SettingsGuiObj.Add("Edit", "x420 y225 w155 vSetDMPhrase", DataminingPhrase)

    SettingsGuiObj.Add("GroupBox", "x305 y270 w280 h80", "Appearance && Quick Call")
    SettingsGuiObj.Add("Checkbox", "x315 y290 w260 vSetDarkTheme " (DarkTheme ? "Checked" : ""), "Dark theme")
    SettingsGuiObj.Add("Checkbox", "x315 y315 w260 vSetQuickCall " qcChecked, "Enable Quick Call panel (Ctrl+Alt+P)")

    SettingsGuiObj.Add("Button", "x200 y365 w90 Default", "Save").OnEvent("Click", SaveSettings)
    SettingsGuiObj.Add("Button", "x305 y365 w90", "Cancel").OnEvent("Click", SettingsGuiClose)
    SettingsGuiObj.Show("x" xPos " y" yPos " w595 h405")
    RA_Front(SettingsGuiObj.Hwnd)
    SettingsGuiObj.Title := "Settings"
}

SettingsGuiClose(*) {
    global SettingsGuiObj
    SettingsGuiObj.Destroy()
}

SaveSettings(*) {
    global IncludeDatamining, ShowCitations, DataminingPhrase, DefaultSmartParse
    global SmartParseConfirmation, SmartParseFallbackToGUI
    global DefaultMeasurementUnit, RVLVOutputFormat, FleischnerInsertAfterImpression
    global ShowVolumeTools, ShowRVLVTools, ShowNASCETTools
    global ShowAdrenalTools, ShowFleischnerTools, ShowStenosisTools
    global ShowICHTools, ShowDateCalculator, QuickCallEnabled, ShowTIRADS, ShowORADS, ShowBoneAge, DarkTheme
    global PreferencesPath
    global SettingsGuiObj

    saved := SettingsGuiObj.Submit()

    ; Convert checkbox values (variable names must match GUI vVar names)
    IncludeDatamining := saved.SetDatamine
    ShowCitations := saved.SetCitations
    SmartParseConfirmation := saved.SetConfirmation
    SmartParseFallbackToGUI := saved.SetFallbackGUI
    FleischnerInsertAfterImpression := saved.SetFleischnerImpression
    DataminingPhrase := saved.SetDMPhrase
    DefaultSmartParse := saved.SetDefaultParse
    DefaultMeasurementUnit := saved.SetDefaultUnit
    RVLVOutputFormat := saved.SetRVLVFormat

    ; Tool visibility settings
    ShowVolumeTools := saved.SetShowVolume
    ShowRVLVTools := saved.SetShowRVLV
    ShowNASCETTools := saved.SetShowNASCET
    ShowAdrenalTools := saved.SetShowAdrenal
    ShowFleischnerTools := saved.SetShowFleischner
    ShowStenosisTools := saved.SetShowStenosis
    ShowICHTools := saved.SetShowICH
    ShowDateCalculator := saved.SetShowDate
    ShowTIRADS := saved.SetShowTIRADS
    ShowORADS := saved.SetShowORADS
    ShowBoneAge := saved.SetShowBoneAge
    DarkTheme := saved.SetDarkTheme

    ; Quick Call - apply immediately (open the panel when newly enabled)
    wasQuickCall := QuickCallEnabled
    QuickCallEnabled := saved.SetQuickCall
    if (QuickCallEnabled && !wasQuickCall)
        QC_Enable(1)
    else if (!QuickCallEnabled && wasQuickCall)
        QC_Disable()

    ; Batch all writes together (reduces file operations)
    writeSuccess := true
    writeSuccess := writeSuccess && IniWriteWithRetry("IncludeDatamining", IncludeDatamining)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowCitations", ShowCitations)
    writeSuccess := writeSuccess && IniWriteWithRetry("DataminingPhrase", DataminingPhrase)
    writeSuccess := writeSuccess && IniWriteWithRetry("DefaultSmartParse", DefaultSmartParse)
    writeSuccess := writeSuccess && IniWriteWithRetry("SmartParseConfirmation", SmartParseConfirmation)
    writeSuccess := writeSuccess && IniWriteWithRetry("SmartParseFallbackToGUI", SmartParseFallbackToGUI)
    writeSuccess := writeSuccess && IniWriteWithRetry("DefaultMeasurementUnit", DefaultMeasurementUnit)
    writeSuccess := writeSuccess && IniWriteWithRetry("RVLVOutputFormat", RVLVOutputFormat)
    writeSuccess := writeSuccess && IniWriteWithRetry("FleischnerInsertAfterImpression", FleischnerInsertAfterImpression)

    ; Tool visibility preferences
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowVolumeTools", ShowVolumeTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowRVLVTools", ShowRVLVTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowNASCETTools", ShowNASCETTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowAdrenalTools", ShowAdrenalTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowFleischnerTools", ShowFleischnerTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowStenosisTools", ShowStenosisTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowICHTools", ShowICHTools)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowDateCalculator", ShowDateCalculator)
    writeSuccess := writeSuccess && IniWriteWithRetry("QuickCallEnabled", QuickCallEnabled)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowTIRADS", ShowTIRADS)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowORADS", ShowORADS)
    writeSuccess := writeSuccess && IniWriteWithRetry("ShowBoneAge", ShowBoneAge)
    writeSuccess := writeSuccess && IniWriteWithRetry("DarkTheme", DarkTheme)

    if (!writeSuccess)
        MsgBox("Some settings may not have saved. Check file permissions or OneDrive sync status.", "Warning", 0x40030)

    ToolTip("Settings saved")
    SetTimer(RemoveToolTip, -1500)
}

; -----------------------------------------
; INI Write with retry for OneDrive sync conflicts
; WHY: OneDrive may lock files during sync, retry helps
; -----------------------------------------
IniWriteWithRetry(key, value, maxRetries := 3) {
    global PreferencesPath
    Loop maxRetries
    {
        try {
            IniWrite(value, PreferencesPath, "Settings", key)
            return true
        } catch {
            Sleep(100)  ; Wait 100ms before retry
        }
    }
    return false
}

; =========================================
; Result Display
; =========================================
global ResultGuiObj := ""

ShowResult(text) {
    global ResultGuiObj
    ; Copy to clipboard and show message
    A_Clipboard := text

    ; Create result window
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mouseX, &mouseY)
    xPos := mouseX + 10
    yPos := mouseY + 10

    ResultGuiObj := Gui("+AlwaysOnTop")
    ResultGuiObj.OnEvent("Close", ResultGuiClose)
    ResultGuiObj.OnEvent("Escape", ResultGuiClose)
    ResultGuiObj.Add("Edit", "x10 y10 w380 h200 ReadOnly", text)
    ResultGuiObj.Add("Button", "x10 y220 w120", "Insert into Report").OnEvent("Click", InsertResult)
    ResultGuiObj.Add("Button", "x140 y220 w120", "Copy to Clipboard").OnEvent("Click", CopyResult)
    ResultGuiObj.Add("Button", "x270 y220 w120", "Close").OnEvent("Click", ResultGuiClose)
    ResultGuiObj.Show("x" xPos " y" yPos " w400 h260")
    RA_Front(ResultGuiObj.Hwnd)
    ResultGuiObj.Title := "Result"
}

ResultGuiClose(*) {
    global ResultGuiObj
    ResultGuiObj.Destroy()
}

CopyResult(*) {
    global ResultGuiObj
    ; Already in clipboard from ShowResult
    ToolTip("Copied to clipboard!")
    SetTimer(RemoveToolTip, -1500)
    ResultGuiObj.Destroy()
}

InsertResult(*) {
    global ResultGuiObj
    ResultGuiObj.Destroy()
    RA_ActivateTarget()
    Sleep(100)
    ; WHY: Deselect any selected text first to prevent replacing it
    ; NOTE: Right arrow moves cursor to end of selection without deleting
    Send("{Right}")
    Sleep(50)
    Send("^v")
}

; =========================================
; Initialize Preferences Path (OneDrive Compatibility)
; WHY: Determines writable location for INI file
; TRADEOFF: Falls back to LOCALAPPDATA if script dir is read-only
; =========================================
InitPreferencesPath() {
    global PreferencesPath
    ; Try script directory first
    testPath := A_ScriptDir . "\RadAssist_preferences.ini"
    testFile := A_ScriptDir . "\.radassist_write_test"

    ; Test if we can write to script directory
    canWrite := true
    try {
        FileAppend("test", testFile)
        FileDelete(testFile)
    } catch {
        canWrite := false
    }

    if (canWrite) {
        PreferencesPath := testPath
    } else {
        ; Fall back to LOCALAPPDATA
        fallbackDir := A_AppData . "\..\Local\RadAssist"
        if (!FileExist(fallbackDir)) {
            DirCreate(fallbackDir)
        }
        PreferencesPath := fallbackDir . "\RadAssist_preferences.ini"
    }
}

; =========================================
; Load Preferences on Startup
; =========================================
LoadPreferences() {
    global IncludeDatamining, ShowCitations, DataminingPhrase, DefaultSmartParse
    global SmartParseConfirmation, SmartParseFallbackToGUI
    global DefaultMeasurementUnit, RVLVOutputFormat, FleischnerInsertAfterImpression
    global ShowVolumeTools, ShowRVLVTools, ShowNASCETTools
    global ShowAdrenalTools, ShowFleischnerTools, ShowStenosisTools
    global ShowICHTools, ShowDateCalculator, QuickCallEnabled, ShowTIRADS, ShowORADS, ShowBoneAge, DarkTheme
    global PreferencesPath

    ; Use PreferencesPath set by InitPreferencesPath() for OneDrive compatibility
    if (FileExist(PreferencesPath)) {
        IncludeDatamining := IniRead(PreferencesPath, "Settings", "IncludeDatamining", "1")
        ShowCitations := IniRead(PreferencesPath, "Settings", "ShowCitations", "1")
        DataminingPhrase := IniRead(PreferencesPath, "Settings", "DataminingPhrase", "SSM lung nodule")
        DefaultSmartParse := IniRead(PreferencesPath, "Settings", "DefaultSmartParse", "Auto")
        SmartParseConfirmation := IniRead(PreferencesPath, "Settings", "SmartParseConfirmation", "1")
        SmartParseFallbackToGUI := IniRead(PreferencesPath, "Settings", "SmartParseFallbackToGUI", "1")
        DefaultMeasurementUnit := IniRead(PreferencesPath, "Settings", "DefaultMeasurementUnit", "cm")
        RVLVOutputFormat := IniRead(PreferencesPath, "Settings", "RVLVOutputFormat", "Macro")
        FleischnerInsertAfterImpression := IniRead(PreferencesPath, "Settings", "FleischnerInsertAfterImpression", "1")

        ; Tool visibility preferences (default to true/1)
        ShowVolumeTools := IniRead(PreferencesPath, "Settings", "ShowVolumeTools", "1")
        ShowRVLVTools := IniRead(PreferencesPath, "Settings", "ShowRVLVTools", "1")
        ShowNASCETTools := IniRead(PreferencesPath, "Settings", "ShowNASCETTools", "1")
        ShowAdrenalTools := IniRead(PreferencesPath, "Settings", "ShowAdrenalTools", "1")
        ShowFleischnerTools := IniRead(PreferencesPath, "Settings", "ShowFleischnerTools", "1")
        ShowStenosisTools := IniRead(PreferencesPath, "Settings", "ShowStenosisTools", "1")
        ShowICHTools := IniRead(PreferencesPath, "Settings", "ShowICHTools", "1")
        ShowDateCalculator := IniRead(PreferencesPath, "Settings", "ShowDateCalculator", "1")
        QuickCallEnabled := IniRead(PreferencesPath, "Settings", "QuickCallEnabled", "1")
        ShowTIRADS := IniRead(PreferencesPath, "Settings", "ShowTIRADS", "1") = "1"
        ShowORADS := IniRead(PreferencesPath, "Settings", "ShowORADS", "1") = "1"
        ShowBoneAge := IniRead(PreferencesPath, "Settings", "ShowBoneAge", "0") = "1"
        DarkTheme := IniRead(PreferencesPath, "Settings", "DarkTheme", "0") = "1"

        IncludeDatamining := (IncludeDatamining = "1")
        ShowCitations := (ShowCitations = "1")
        SmartParseConfirmation := (SmartParseConfirmation = "1")
        SmartParseFallbackToGUI := (SmartParseFallbackToGUI = "1")
        FleischnerInsertAfterImpression := (FleischnerInsertAfterImpression = "1")

        ; Convert visibility settings to boolean
        ShowVolumeTools := (ShowVolumeTools = "1")
        ShowRVLVTools := (ShowRVLVTools = "1")
        ShowNASCETTools := (ShowNASCETTools = "1")
        ShowAdrenalTools := (ShowAdrenalTools = "1")
        ShowFleischnerTools := (ShowFleischnerTools = "1")
        ShowStenosisTools := (ShowStenosisTools = "1")
        ShowICHTools := (ShowICHTools = "1")
        ShowDateCalculator := (ShowDateCalculator = "1")
        QuickCallEnabled := (QuickCallEnabled = "1")
    }

    ; Validate loaded preferences
    validParsers := ",Auto,Volume,RVLV,NASCET,Stenosis,Adrenal,Fleischner,ICH,Date,TIRADS,ORADS,"
    if (DefaultSmartParse = "" || !InStr(validParsers, "," DefaultSmartParse ","))
        DefaultSmartParse := "Auto"

    validUnits := "cm,mm"
    if (!InStr(validUnits, DefaultMeasurementUnit))
        DefaultMeasurementUnit := "cm"

    validFormats := "Inline,Macro"
    if (!InStr(validFormats, RVLVOutputFormat))
        RVLVOutputFormat := "Macro"
}
LoadPreferences()

; =========================================
; Tray Menu
; =========================================
A_TrayMenu.Delete()
A_TrayMenu.Add("RadAssist v2.4", TrayAbout)
A_TrayMenu.Add()
A_TrayMenu.Add("Settings", MenuSettings)
A_TrayMenu.Add("Reload", TrayReload)
A_TrayMenu.Add("Exit", TrayExit)
A_IconTip := "RadAssist v2.4 - Smart Radiology Tools"

; =========================================
; Quick Call module (floating always-on-top call panel)
; NOTE: Embedded here (same code as QuickCall.ahk) so RadAssist is a single file.
;       Must come after the tray menu and before QC_Enable(). Toggle in Settings > Quick Call.
; =========================================
; >>> QUICKCALL BEGIN (generated from QuickCall.ahk - edit there, then re-embed) >>>
; ================= SETTINGS =================
global QC_PopupHotkey    := "^!p"   ; Ctrl+Alt+P  show / minimize panel
global QC_DialSelHotkey  := "^!d"   ; Ctrl+Alt+D  dial highlighted number
global QC_LogHotkey      := "^!l"   ; Ctrl+Alt+L  paste critical-result statement
global QC_OpenAtStart    := true    ; open the panel when the script starts
global QC_DialMode       := "url"   ; "url" = voice.google.com link | "tel" = tel: link
global QC_GVAccount      := 0       ; Google account index if signed into several
global QC_AutoConfirm    := true    ; auto-press Call on Google Voice's "Call?" prompt
global QC_ConfirmDelayMs := 1500    ; ms to let the Voice page load before confirming
global QC_RadName        := "Dr. Harwood"
global QC_IncludeReadBack := true

global QC_BookFile := A_ScriptDir "\QuickCall_PhoneBook.txt"
global QC_IniFile  := A_ScriptDir "\QuickCall_Settings.ini"

; Used only to create QuickCall_PhoneBook.txt the first time
global QC_DefaultBook := "
(
; QuickCall phone book. One contact per line: Group|Label|Number
; Group Main = big buttons at the top. Any other group = a tech column.
; Edit here or with the Edit #s button on the panel.
Main|HC ER|636-947-5111
Main|LSL ER|636-625-5300
Main|HC ICU|
Main|LSL ICU|
HC|ED Charge RN|636-947-7503
HC|Stroke Unit|636-443-7550
HC|House Sup|636-443-7596
HC|CT ED|636-947-5285
HC|CT Street|636-947-5410
HC|MRI|636-947-5606
HC|US|636-947-5441
HC|Rad / XR (ED)|636-443-2855
HC|Nuc Med|636-947-5494
HC|Vascular|636-947-5438
HC|IR RN|
HC|Front Desk (opt 1)|636-947-5444
LSL|Stroke Unit|636-755-3617
LSL|House Sup|636-625-7889
LSL|CT|636-755-3635
LSL|MRI|636-625-5407
LSL|Rad / XR|636-625-7801
LSL|US|636-755-3930
LSL|Nuc Med|636-755-3112
LSL|Vascular|636-625-5275
LSL|IR RN|
LSL|Front Desk (opt 2)|636-625-5303
WZ|ER|636-327-1100
WZ|ER MD|636-327-1102
WZ|CT/Rad|636-327-1140
WZ|CT|636-327-1088
WZ|Rad|636-327-1145
)"

; ================= STATE =================
global QC_Entries := [], QC_Gui := "", QC_BtnMap := Map(), QC_Editor := ""
global QC_Expanded := false, QC_LastCall := "", QC_DialogOpen := 0
global QC_X := "", QC_Y := "", QC_LastExtWin := 0
global QC_Pid := DllCall("GetCurrentProcessId")
global QC_Initialized := false, QC_Enabled := false
global QC_Collapsed := false, QC_W := "", QC_H := "", QC_Ctl := ""   ; panel size / collapse state
global QC_TickMs := 500     ; how often the panel checks it is still on top

; ================= ENABLE / DISABLE =================
QC_Init() {
    global QC_Initialized, QC_X, QC_Y, QC_Expanded, QC_Collapsed, QC_W, QC_H
    if QC_Initialized
        return
    QC_Initialized := true
    QC_LoadBook()
    try QC_X := IniRead(QC_IniFile, "Panel", "X", "")
    try QC_Y := IniRead(QC_IniFile, "Panel", "Y", "")
    try QC_W := IniRead(QC_IniFile, "Panel", "W", "")
    try QC_H := IniRead(QC_IniFile, "Panel", "H", "")
    try QC_Expanded := (IniRead(QC_IniFile, "Panel", "Expanded", "0") = "1")
    try QC_Collapsed := (IniRead(QC_IniFile, "Panel", "Collapsed", "0") = "1")

    Hotkey(QC_PopupHotkey, QC_TogglePanel, "Off")
    Hotkey(QC_DialSelHotkey, QC_DialSelection, "Off")
    Hotkey(QC_LogHotkey, QC_LogCall, "Off")
    OnExit(QC_OnExit)
    OnMessage(0xA3, QC_OnDblClick)      ; double-click title bar
    OnMessage(0x203, QC_OnDblClick)     ; double-click header strip
}

; showPanel: -1 = follow QC_OpenAtStart, 0 = don't open, 1 = open now
QC_Enable(showPanel := -1) {
    global QC_Enabled
    QC_Init()
    if !QC_Enabled {
        QC_Enabled := true
        QC_SetHotkeys("On")
        QC_SetTray(true)
        SetTimer(QC_Tick, QC_TickMs)
    }
    if (showPanel = 1)
        QC_ShowPanel()
    else if (showPanel = -1 && QC_OpenAtStart && !IsObject(QC_Gui))
        QC_BuildPanel(false)    ; at startup: don't steal focus from PowerScribe
}

QC_Disable() {
    global QC_Enabled, QC_Gui
    if !QC_Enabled
        return
    QC_Enabled := false
    SetTimer(QC_Tick, 0)
    QC_SetHotkeys("Off")
    QC_SetTray(false)
    if IsObject(QC_Editor)
        try QC_Editor.Destroy()
    QC_SetEditor("")
    if IsObject(QC_Gui) {
        QC_SavePos()
        try QC_Gui.Destroy()
        QC_Gui := ""
    }
}

QC_SetHotkeys(state) {
    Hotkey(QC_PopupHotkey, state)
    Hotkey(QC_DialSelHotkey, state)
    Hotkey(QC_LogHotkey, state)
}

QC_SetTray(add) {
    for name in ["Quick Call panel", "Edit phone numbers"] {
        try A_TrayMenu.Delete(name)
    }
    if !add
        return
    try {
        ; RadAssist tray: put the items just above Reload
        A_TrayMenu.Insert("Reload", "Quick Call panel", QC_ShowPanel)
        A_TrayMenu.Insert("Reload", "Edit phone numbers", QC_ShowEditor)
    } catch {
        A_TrayMenu.Add("Quick Call panel", QC_ShowPanel)
        A_TrayMenu.Add("Edit phone numbers", QC_ShowEditor)
    }
}

; ================= RIGHT-CLICK MENU HOOK =================
QC_AddPhoneMenu(parentMenu) {
    pm := Menu()
    pm.Add("Show call panel", QC_ShowPanel)
    pm.Add()
    for e in QC_Entries {
        if (e.sec = "Main")
            pm.Add("Call " e.label (e.num = "" ? "  (add #)" : ""), QC_DialEntry.Bind(e))
    }
    pm.Add()
    pm.Add("Dial highlighted number", QC_DialSelection)
    pm.Add("Log last call to report", QC_LogCall)
    pm.Add("Edit phone numbers...", QC_ShowEditor)
    parentMenu.Add("Phone", pm)
}

; ================= PHONE BOOK FILE =================
QC_LoadBook() {
    global QC_Entries
    if !FileExist(QC_BookFile)
        FileAppend(QC_DefaultBook "`n", QC_BookFile, "UTF-8")
    QC_Entries := []
    for line in StrSplit(FileRead(QC_BookFile, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        p := StrSplit(line, "|")
        if (p.Length < 2)
            continue
        QC_Entries.Push({sec: Trim(p[1]), label: Trim(p[2]), num: p.Length >= 3 ? Trim(p[3]) : ""})
    }
}

QC_SaveBook() {
    txt := "; QuickCall phone book. One contact per line: Group|Label|Number`n"
    txt .= "; Group Main = big buttons at the top. Any other group = a tech column.`n"
    for e in QC_Entries
        txt .= e.sec "|" e.label "|" e.num "`n"
    try FileDelete(QC_BookFile)
    FileAppend(txt, QC_BookFile, "UTF-8")
}

QC_SetEntries(arr) {
    global QC_Entries
    QC_Entries := arr
    QC_SaveBook()
}

QC_Groups() {
    main := [], secs := [], grp := Map()
    for e in QC_Entries {
        if (e.sec = "Main") {
            main.Push(e)
            continue
        }
        if !grp.Has(e.sec) {
            grp[e.sec] := []
            secs.Push(e.sec)
        }
        grp[e.sec].Push(e)
    }
    return {main: main, secs: secs, grp: grp}
}

QC_Full(e) => (e.sec = "Main" ? e.label : e.sec " " e.label)

QC_IsValidNum(v) {
    d := RegExReplace(v, "\D")
    return StrLen(d) = 10 || (StrLen(d) = 11 && SubStr(d, 1, 1) = "1")
}

; ================= PANEL =================
; Layout: [+/-] collapse button on top, main numbers (2 columns), "+ Techs" toggle,
; optional tech columns, then Dial / Log / Edit. The window can be resized:
; buttons stretch to the new width and button heights scale to the new height.
QC_BuildPanel(activate := true) {
    global QC_Gui, QC_BtnMap, QC_Ctl
    if IsObject(QC_Gui) {
        QC_SavePos()
        try QC_Gui.Destroy()
        QC_Gui := ""
    }
    QC_BtnMap := Map()
    grps := QC_Groups()

    ; +ToolWindow = floating panel with no taskbar button; it is hidden (not
    ; minimized) by Esc / X and comes back with Ctrl+Alt+P, the menu, or tray.
    g := Gui("+AlwaysOnTop +ToolWindow +Resize -MaximizeBox -MinimizeBox +MinSize150x40", "Quick Call")
    g.BackColor := "202020"
    g.OnEvent("Close", QC_OnPanelClose)
    g.OnEvent("Escape", (*) => (QC_SavePos(), QC_Gui.Hide()))
    g.OnEvent("ContextMenu", QC_PanelContext)
    g.OnEvent("Size", QC_OnSize)

    c := {main: [], heads: [], cols: [], bottom: [], nMain: grps.main.Length}
    g.SetFont("s12 bold", "Segoe UI")
    c.toggle := g.AddButton("x8 y6 w30 h26", QC_Collapsed ? "+" : "-")
    c.toggle.OnEvent("Click", QC_ToggleCollapse)
    g.SetFont("s9 norm c9FC5E8")
    c.hint := g.AddText("x46 y12 w220 h18 BackgroundTrans", QC_Collapsed ? "Quick Call" : "Click a name to call   Ctrl+Alt+P hide")
    c.hint.OnEvent("DoubleClick", QC_ToggleCollapse)      ; double-click the header strip

    g.SetFont("s11 norm cDefault")
    for i, e in grps.main {
        b := g.AddButton("x0 y0 w10 h10", i "   " e.label (e.num = "" ? " (add #)" : ""))
        b.OnEvent("Click", QC_DialEntry.Bind(e))
        QC_BtnMap[b.Hwnd] := e
        c.main.Push(b)
    }
    g.SetFont("s10")
    c.techs := g.AddButton("x0 y0 w10 h10", QC_Expanded ? "-   Techs" : "+   Techs")
    c.techs.OnEvent("Click", QC_ToggleTechs)
    c.maxRows := 0
    if QC_Expanded {
        for k, sec in grps.secs {
            g.SetFont("s10 bold c9FC5E8")
            c.heads.Push(g.AddText("x0 y0 w10 h10 BackgroundTrans", sec))
            g.SetFont("s9 norm cDefault")
            col := []
            for e in grps.grp[sec] {
                b := g.AddButton("x0 y0 w10 h10", e.label (e.num = "" ? " (add #)" : ""))
                b.OnEvent("Click", QC_DialEntry.Bind(e))
                QC_BtnMap[b.Hwnd] := e
                col.Push(b)
            }
            c.cols.Push(col)
            c.maxRows := Max(c.maxRows, col.Length)
        }
    }
    g.SetFont("s9 norm cDefault")
    for item in [["Dial #...", QC_ManualDial], ["Log call", QC_LogCall], ["Edit #s", QC_ShowEditor]] {
        b := g.AddButton("x0 y0 w10 h10", item[1])
        b.OnEvent("Click", item[2])
        c.bottom.Push(b)
    }

    QC_Ctl := c
    QC_Gui := g
    w := (IsNumber(QC_W) && QC_W >= 150) ? QC_W + 0 : QC_DefaultW()
    nat := QC_NaturalH()
    h := (IsNumber(QC_H) && QC_H >= nat * 0.55) ? QC_H + 0 : nat
    if QC_Collapsed {
        QC_SetBodyVisible(false)
        w := QC_CollapsedW(), h := QC_CollapsedH()
        c.hint.Move(46, 12, w - 52)
    } else {
        QC_Layout(w, h)
    }
    opts := (activate ? "" : "NoActivate ") "w" w " h" h
    if QC_ValidPos(QC_X, QC_Y)
        opts .= " x" QC_X " y" QC_Y
    g.Show(opts)
    QC_FitOnScreen()
    QC_RaiseTop(g.Hwnd)
}

; Keep the whole panel on its monitor: move it up, or shrink it if taller than the screen
QC_FitOnScreen() {
    h := QC_Gui.Hwnd
    WinGetPos(&x, &y, &w, &ht, h)
    cx := x + w // 2, cy := y + 10
    l := 0, t := 0, r := A_ScreenWidth, b := A_ScreenHeight
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
        if (cx >= ml && cx < mr && cy >= mt && cy < mb)
            l := ml, t := mt, r := mr, b := mb
    }
    nh := Min(ht, b - t), ny := Max(t, Min(y, b - nh)), nx := Max(l, Min(x, r - w))
    if (nh != ht || ny != y || nx != x)
        WinMove(nx, ny, , nh, h)
}

QC_DefaultW() {
    n := QC_Expanded ? QC_Ctl.cols.Length : 0
    return Max(2 * 150 + 8 + 20, n * 158 - 8 + 20)
}
QC_CollapsedH() => 38
QC_CollapsedW() => 175      ; collapsed = small rectangle: [+] and "Quick Call"

; Double-click on the panel's title bar (or its empty header strip) collapses/expands it
QC_OnDblClick(wParam, lParam, msg, hwnd) {
    if !(IsObject(QC_Gui) && hwnd = QC_Gui.Hwnd)
        return
    if (msg = 0xA3 && wParam = 2) {            ; WM_NCLBUTTONDBLCLK on HTCAPTION
        QC_ToggleCollapse()
        return 0
    }
    if (msg = 0x203 && ((lParam >> 16) & 0xFFFF) < 38) {   ; WM_LBUTTONDBLCLK in the top strip
        QC_ToggleCollapse()
        return 0
    }
}

; Height when nothing is stretched (fixed gaps + natural button heights)
QC_NaturalH() {
    f := QC_HeightParts()
    return Round(f.fixed + f.scalable)
}

QC_HeightParts() {
    c := QC_Ctl
    rows := Ceil(c.nMain / 2)
    fixed := 40 + (rows > 0 ? (rows - 1) * 8 + 12 : 0) + 10 + 10    ; top bar, row gaps, gap before bottom, margin
    scalable := rows * 42 + 30 + 28                                 ; main rows, Techs, bottom row
    if (QC_Expanded && c.cols.Length) {
        fixed += 10 + 22 + (c.maxRows - 1) * 4
        scalable += c.maxRows * 28
    }
    return {fixed: fixed, scalable: scalable}
}

QC_Layout(w, h) {
    c := QC_Ctl
    if !IsObject(c)
        return
    M := 10, G := 8
    f := QC_HeightParts()
    s := (h - f.fixed) / f.scalable
    s := Max(0.55, Min(3, s))
    inner := Max(60, w - 2 * M)
    c.hint.Move(46, 12, Max(10, w - 52))

    y := 40
    bw := Floor((inner - G) / 2), mh := Round(42 * s)
    for i, b in c.main {
        col := Mod(i - 1, 2), row := (i - 1) // 2
        b.Move(M + col * (bw + G), y + row * (mh + G), bw, mh)
    }
    rows := Ceil(c.nMain / 2)
    if rows
        y += rows * mh + (rows - 1) * G + 12
    th := Round(30 * s)
    c.techs.Move(M, y, inner, th)
    y += th
    if (QC_Expanded && c.cols.Length) {
        n := c.cols.Length
        cw := Floor((inner - (n - 1) * G) / n)
        rh := Round(28 * s)
        y += 10
        for k, col in c.cols {
            x := M + (k - 1) * (cw + G)
            c.heads[k].Move(x, y, cw, 20)
            for j, b in col
                b.Move(x, y + 22 + (j - 1) * (rh + 4), cw, rh)
        }
        y += 22 + c.maxRows * rh + (c.maxRows - 1) * 4
    }
    y += 10
    w3 := Floor((inner - 2 * G) / 3), bh := Round(28 * s)
    for i, b in c.bottom
        b.Move(M + (i - 1) * (w3 + G), y, w3, bh)
    ; avoid leftover paint artifacts when shrinking
    DllCall("RedrawWindow", "Ptr", QC_Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
}

QC_SetBodyVisible(v) {
    c := QC_Ctl
    for b in c.main
        b.Visible := v
    c.techs.Visible := v
    for t in c.heads
        t.Visible := v
    for col in c.cols
        for b in col
            b.Visible := v
    for b in c.bottom
        b.Visible := v
}

QC_OnSize(g, minMax, w, h) {
    global QC_W, QC_H
    if (minMax = -1 || !IsObject(QC_Ctl))
        return
    g.GetClientPos(, , &cw, &ch)
    if QC_Collapsed {
        QC_Ctl.hint.Move(46, 12, Max(10, cw - 52))
        return
    }
    QC_W := cw, QC_H := ch
    QC_Layout(cw, ch)
}

; The [+/-] button or a double-click on the header: collapse to a small rectangle, or expand
QC_ToggleCollapse(*) {
    global QC_Collapsed, QC_W, QC_H
    QC_Gui.GetClientPos(, , &cw, &ch)
    if !QC_Collapsed
        QC_W := cw, QC_H := ch
    QC_Collapsed := !QC_Collapsed
    try IniWrite(QC_Collapsed ? 1 : 0, QC_IniFile, "Panel", "Collapsed")
    QC_Ctl.toggle.Text := QC_Collapsed ? "+" : "-"
    QC_Ctl.hint.Text := QC_Collapsed ? "Quick Call" : "Click a name to call   Ctrl+Alt+P hide"
    if QC_Collapsed {
        QC_SetBodyVisible(false)
        QC_Ctl.hint.Move(46, 12, QC_CollapsedW() - 52)
        QC_Gui.Show("NoActivate w" QC_CollapsedW() " h" QC_CollapsedH())
    } else {
        w := (IsNumber(QC_W) && QC_W >= 150) ? QC_W : QC_DefaultW()
        h := (IsNumber(QC_H) && QC_H > QC_CollapsedH() + 20) ? QC_H : QC_NaturalH()
        QC_Layout(w, h)
        QC_SetBodyVisible(true)
        QC_Gui.Show("NoActivate w" w " h" h)
        QC_FitOnScreen()
    }
    QC_SavePos()
}

QC_ShowPanel(*) {
    if !IsObject(QC_Gui) {
        QC_BuildPanel()
        return
    }
    h := QC_Gui.Hwnd
    if (WinGetMinMax(h) = -1)
        QC_Gui.Restore()
    else
        QC_Gui.Show()
    QC_RaiseTop(h)
}

QC_TogglePanel(*) {
    if !IsObject(QC_Gui) {
        QC_BuildPanel()
        return
    }
    h := QC_Gui.Hwnd
    if (!DllCall("IsWindowVisible", "Ptr", h) || WinGetMinMax(h) = -1) {
        QC_ShowPanel()
    } else {
        QC_SavePos()
        QC_Gui.Hide()
    }
}

QC_ToggleTechs(*) {
    global QC_Expanded, QC_H, QC_W
    QC_SavePos()
    QC_Expanded := !QC_Expanded
    try IniWrite(QC_Expanded ? 1 : 0, QC_IniFile, "Panel", "Expanded")
    QC_H := ""                                  ; height follows the new content
    if (QC_Expanded && IsNumber(QC_W))          ; widen enough for the tech columns
        QC_W := Max(QC_W, QC_Groups().secs.Length * 120 + 20)
    QC_BuildPanel()
    QC_SavePos()
}

QC_OnPanelClose(*) {
    QC_SavePos()          ; window hides; reopen with Ctrl+Alt+P, menu, or tray
}

QC_SavePos() {
    global QC_X, QC_Y
    if !IsObject(QC_Gui)
        return
    try {
        h := QC_Gui.Hwnd
        if !DllCall("IsWindowVisible", "Ptr", h) || WinGetMinMax(h) = -1
            return
        WinGetPos(&x, &y, , , h)
        QC_X := x, QC_Y := y
        IniWrite(x, QC_IniFile, "Panel", "X")
        IniWrite(y, QC_IniFile, "Panel", "Y")
        if !QC_Collapsed {
            QC_Gui.GetClientPos(, , &cw, &ch)
            IniWrite(cw, QC_IniFile, "Panel", "W")
            IniWrite(ch, QC_IniFile, "Panel", "H")
        }
    }
}

QC_ValidPos(x, y) {
    if (x = "" || y = "")
        return false
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (x >= l - 50 && x < r - 50 && y >= t - 10 && y < b - 50)
            return true
    }
    return false
}

QC_OnExit(*) {
    QC_SavePos()
}

; Keeps the panel above Sectra/PowerScribe and remembers the last non-browser window
QC_Tick() {
    global QC_LastExtWin
    try {
        a := WinExist("A")
        if (a && WinGetPID(a) != QC_Pid) {
            if !RegExMatch(WinGetProcessName(a), "i)^(chrome|msedge|firefox|brave)\.exe$")
                QC_LastExtWin := a
        }
    }
    if (!IsObject(QC_Gui) || QC_DialogOpen > 0)
        return
    try {
        h := QC_Gui.Hwnd
        if !DllCall("IsWindowVisible", "Ptr", h) || WinGetMinMax(h) = -1
            return
        if (WinGetPID("A") = QC_Pid)   ; one of our own windows or menus is active
            return
        ; Re-assert topmost every tick (cheap, no flicker)
        DllCall("SetWindowPos", "Ptr", h, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        ; Sectra / PowerScribe windows that are themselves topmost can still sit
        ; above us; if anything covers the panel, bump it to the top of the band.
        if QC_IsObscured(h)
            QC_RaiseTop(h)
    }
}

; Move the panel to the very top of the always-on-top band without activating it.
; Toggling NOTOPMOST -> TOPMOST is what lifts it above other topmost windows.
QC_RaiseTop(h) {
    ; 0x13 = SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    try {
        DllCall("SetWindowPos", "Ptr", h, "Ptr", -2, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        DllCall("SetWindowPos", "Ptr", h, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    }
}

; True if another application's window is drawn over part of the panel.
; Shell UI (taskbar, Start, Alt+Tab, menus, tooltips) and our own windows are ignored.
QC_IsObscured(h) {
    static shellCls := "i)^(Shell_TrayWnd|Shell_SecondaryTrayWnd|#32768|tooltips_class32|NotifyIconOverflowWindow"
        . "|TopLevelWindowForOverflowXamlIsland|Windows\.UI\.Core\.CoreWindow|ForegroundStaging"
        . "|MultitaskingViewFrame|XamlExplorerHostIslandWindow|TaskListThumbnailWnd|Progman|WorkerW)$"
    try WinGetPos(&x, &y, &w, &hh, h)
    catch
        return false
    pts := [[x + w // 2, y + hh // 2], [x + 12, y + 12], [x + w - 12, y + 12]
          , [x + 12, y + hh - 12], [x + w - 12, y + hh - 12]]
    for p in pts {
        hit := DllCall("WindowFromPoint", "Int64", (p[2] << 32) | (p[1] & 0xFFFFFFFF), "Ptr")
        if !hit
            continue
        root := DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr")   ; GA_ROOT
        if (!root || root = h)
            continue
        try {
            if (WinGetPID("ahk_id " root) = QC_Pid)
                continue
            if RegExMatch(WinGetClass("ahk_id " root), shellCls)
                continue
        } catch {
            continue
        }
        return true
    }
    return false
}

QC_OwnIfVisible() {
    if !IsObject(QC_Gui)
        return
    try {
        h := QC_Gui.Hwnd
        if DllCall("IsWindowVisible", "Ptr", h) && WinGetMinMax(h) != -1
            QC_Gui.Opt("+OwnDialogs")
    }
}

; Right-click a button on the panel to edit it
QC_PanelContext(GuiObj, Ctrl, Item, IsRightClick, X, Y) {
    if (!IsObject(Ctrl) || !QC_BtnMap.Has(Ctrl.Hwnd))
        return
    e := QC_BtnMap[Ctrl.Hwnd]
    m := Menu()
    m.Add("Edit number for " QC_Full(e) "...", (*) => QC_EditField(e, "num"))
    m.Add("Rename...", (*) => QC_EditField(e, "label"))
    m.Add()
    m.Add("Open phone book editor...", QC_ShowEditor)
    m.Show()
}

QC_EditField(e, field) {
    global QC_DialogOpen
    QC_DialogOpen++
    QC_OwnIfVisible()
    prompt := (field = "num") ? "Phone number for " QC_Full(e) ":" : "New label for " QC_Full(e) ":"
    ib := InputBox(prompt, "Quick Call", "w320 h120", e.%field%)
    QC_DialogOpen--
    if (ib.Result != "OK")
        return
    val := Trim(ib.Value)
    if (field = "num" && val != "" && !QC_IsValidNum(val)) {
        MsgBox("Enter a 10-digit number (e.g. 636-947-5111) or leave it blank.", "Quick Call", "Icon!")
        return
    }
    if (field = "label" && val = "")
        return
    e.%field% := val
    QC_SaveBook()
    QC_BuildPanel()
}

; ================= PHONE BOOK EDITOR =================
QC_SetEditor(g) {
    global QC_Editor, QC_DialogOpen
    if IsObject(g)
        QC_DialogOpen++
    else if IsObject(QC_Editor)
        QC_DialogOpen--
    QC_Editor := g
}

QC_ShowEditor(*) {
    if IsObject(QC_Editor) {
        try {
            QC_Editor.Show()
            return
        }
    }
    work := []
    groups := []
    for e in QC_Entries {
        work.Push({sec: e.sec, label: e.label, num: e.num})
        found := false
        for gname in groups {
            if (gname = e.sec)
                found := true
        }
        if !found
            groups.Push(e.sec)
    }

    eg := Gui("+AlwaysOnTop -MaximizeBox", "Quick Call - Edit Phone Book")
    eg.SetFont("s10", "Segoe UI")
    eg.AddText("xm", "Group Main = big buttons at top. Other groups = tech columns. Type a new group name to add a column.")
    lv := eg.AddListView("xm w560 r16 -Multi Grid", ["Group", "Label", "Number"])
    eg.AddText("xm y+10", "Group")
    cbSec := eg.AddComboBox("x+5 yp-3 w100", groups)
    eg.AddText("x+12 yp+3", "Label")
    edLab := eg.AddEdit("x+5 yp-3 w170")
    eg.AddText("x+12 yp+3", "Number")
    edNum := eg.AddEdit("x+5 yp-3 w130")
    bAdd := eg.AddButton("xm y+12 w90", "Add new")
    bUpd := eg.AddButton("x+6 yp w90", "Update")
    bDel := eg.AddButton("x+6 yp w90", "Delete")
    bUp  := eg.AddButton("x+6 yp w50", "▲")
    bDn  := eg.AddButton("x+6 yp w50", "▼")
    bSave := eg.AddButton("xm y+16 w130", "Save && Close")
    bCan  := eg.AddButton("x+6 yp w90", "Cancel")
    state := {closed: false}

    Refresh(sel := 0) {
        lv.Delete()
        for e in work
            lv.Add(, e.sec, e.label, e.num)
        lv.ModifyCol(1, 90), lv.ModifyCol(2, 260), lv.ModifyCol(3, 180)
        if (sel > 0 && sel <= work.Length)
            lv.Modify(sel, "Select Focus Vis")
    }
    Fill(row) {
        e := work[row]
        cbSec.Text := e.sec
        edLab.Value := e.label
        edNum.Value := e.num
    }
    ReadFields() {
        s := Trim(cbSec.Text), l := Trim(edLab.Value), n := Trim(edNum.Value)
        if (s = "" || l = "") {
            MsgBox("Group and Label are required.", "Quick Call", "Icon! Owner" eg.Hwnd)
            return ""
        }
        if (n != "" && !QC_IsValidNum(n)) {
            MsgBox("Enter a 10-digit number (e.g. 636-947-5111) or leave it blank.", "Quick Call", "Icon! Owner" eg.Hwnd)
            return ""
        }
        return {sec: s, label: l, num: n}
    }
    DoAdd(*) {
        f := ReadFields()
        if !IsObject(f)
            return
        r := lv.GetNext(0)
        if (r = 0) {
            work.Push(f)
            r := work.Length
        } else {
            work.InsertAt(r + 1, f)
            r := r + 1
        }
        Refresh(r)
    }
    DoUpdate(*) {
        r := lv.GetNext(0)
        if (r = 0) {
            MsgBox("Select a row to update.", "Quick Call", "Owner" eg.Hwnd)
            return
        }
        f := ReadFields()
        if !IsObject(f)
            return
        work[r] := f
        Refresh(r)
    }
    DoDelete(*) {
        r := lv.GetNext(0)
        if (r = 0)
            return
        work.RemoveAt(r)
        Refresh(r > work.Length ? work.Length : r)
    }
    DoMove(dir, *) {
        r := lv.GetNext(0)
        t := r + dir
        if (r = 0 || t < 1 || t > work.Length)
            return
        tmp := work[r]
        work[r] := work[t]
        work[t] := tmp
        Refresh(t)
    }
    DoClose(*) {
        if state.closed
            return
        state.closed := true
        QC_SetEditor("")
        try eg.Destroy()
    }
    DoSave(*) {
        QC_SetEntries(work)
        DoClose()
        QC_BuildPanel()
    }

    lv.OnEvent("ItemSelect", (ctrl, item, selected) => (selected ? Fill(item) : 0))
    bAdd.OnEvent("Click", DoAdd)
    bUpd.OnEvent("Click", DoUpdate)
    bDel.OnEvent("Click", DoDelete)
    bUp.OnEvent("Click", DoMove.Bind(-1))
    bDn.OnEvent("Click", DoMove.Bind(1))
    bSave.OnEvent("Click", DoSave)
    bCan.OnEvent("Click", DoClose)
    eg.OnEvent("Close", DoClose)
    eg.OnEvent("Escape", DoClose)

    Refresh()
    QC_SetEditor(eg)
    eg.Show()
}

; ================= DIALING =================
QC_DialEntry(e, *) {
    if (e.num = "") {
        QC_EditField(e, "num")
        return
    }
    QC_Dial(e.num, QC_Full(e))
}

QC_Dial(num, label := "") {
    global QC_LastCall
    d := RegExReplace(num, "\D")
    if (StrLen(d) = 11 && SubStr(d, 1, 1) = "1")
        d := SubStr(d, 2)
    if (StrLen(d) != 10) {
        MsgBox("Can't dial '" num "'. Need a full 10-digit number.", "Quick Call", "Icon! 262144")
        return
    }
    if (QC_DialMode = "tel")
        Run("tel:+1" d)
    else {
        Run("https://voice.google.com/u/" QC_GVAccount "/calls?a=nc,%2B1" d)
        if QC_AutoConfirm
            SetTimer(QC_ConfirmCall, -250)
    }
    QC_LastCall := {label: label != "" ? label : QC_FormatPhone(d), time: A_Now}
    QC_Tip("Calling " QC_LastCall.label "  " QC_FormatPhone(d), 3000)
}

; Google Voice opens a "Call this number?" prompt. Wait for the Voice tab to be
; in front, give the page time to load, then press Enter to confirm. Only fires
; while a browser window titled "...Voice..." is active, so it never types into
; PowerScribe or Sectra.
QC_ConfirmCall() {
    static tries := 0, seenAt := 0
    if (tries = 0)
        seenAt := 0
    tries++
    onVoice := false
    try {
        a := WinExist("A")
        onVoice := RegExMatch(WinGetProcessName(a), "i)^(chrome|msedge|firefox|brave)\.exe$")
            && InStr(WinGetTitle(a), "Voice")
    }
    if (onVoice && !seenAt)
        seenAt := A_TickCount
    if (onVoice && A_TickCount - seenAt >= QC_ConfirmDelayMs) {
        Send("{Enter}")
        tries := 0
        return
    }
    if (tries > 60) {          ; ~15 s: give up quietly
        tries := 0
        return
    }
    SetTimer(QC_ConfirmCall, -250)
}

QC_DialText(txt) {
    if !RegExMatch(txt, "(\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}|\b8[057]-?\d{4}\b", &m) {
        QC_Tip("No phone number found")
        return
    }
    d := RegExReplace(m[0], "\D")
    if (StrLen(d) = 6) {
        pre := SubStr(d, 1, 2), ext := SubStr(d, 3)
        if (pre = "85")
            d := "636947" ext
        else if (pre = "80")
            d := "636327" ext
        else {
            MsgBox("87- extensions are split between 636-625 and 636-755. Dial the full number.", "Quick Call", "Icon! 262144")
            return
        }
    }
    QC_Dial(d)
}

QC_DialSelection(*) {
    Sleep(100)
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(0.5) {
        A_Clipboard := saved
        QC_Tip("Highlight a phone number first")
        return
    }
    txt := A_Clipboard
    A_Clipboard := saved
    QC_DialText(txt)
}

QC_ManualDial(*) {
    global QC_DialogOpen
    QC_DialogOpen++
    QC_OwnIfVisible()
    ib := InputBox("Number to dial (10-digit, or 85-xxxx / 80-xxxx):", "Quick Call", "w320 h120")
    QC_DialogOpen--
    if (ib.Result = "OK" && Trim(ib.Value) != "")
        QC_DialText(ib.Value)
}

QC_FormatPhone(d) => SubStr(d, 1, 3) "-" SubStr(d, 4, 3) "-" SubStr(d, 7)

QC_Tip(msg, ms := 2000) {
    ToolTip(msg, , , 2)
    SetTimer(() => ToolTip(, , , 2), -ms)
}

; ================= CRITICAL RESULT STATEMENT =================
QC_LogCall(*) {
    global QC_DialogOpen
    if !IsObject(QC_LastCall) {
        QC_Tip("No call placed yet this session")
        return
    }
    target := 0
    try {
        a := WinExist("A")
        if (a && WinGetPID(a) != QC_Pid && !RegExMatch(WinGetProcessName(a), "i)^(chrome|msedge|firefox|brave)\.exe$"))
            target := a
    }
    if !target
        target := QC_LastExtWin

    QC_DialogOpen++
    QC_OwnIfVisible()
    ib := InputBox("Spoke with (name / title):", "Critical result: " QC_LastCall.label, "w340 h120")
    QC_DialogOpen--
    if (ib.Result != "OK" || Trim(ib.Value) = "")
        return

    t := FormatTime(QC_LastCall.time, "h:mm tt")
    dt := FormatTime(QC_LastCall.time, "M/d/yyyy")
    s := "These findings were discussed by telephone with " Trim(ib.Value) " (" QC_LastCall.label ") by " QC_RadName " at " t " on " dt "."
    if QC_IncludeReadBack
        s .= " Read-back was performed."

    A_Clipboard := s
    ClipWait(1)
    if (target && WinExist("ahk_id " target)) {
        WinActivate("ahk_id " target)
        if WinWaitActive("ahk_id " target, , 1) {
            Send("^v")
            return
        }
    }
    QC_Tip("Statement copied. Paste it into the report.", 3000)
}
; <<< QUICKCALL END

if (QuickCallEnabled)
    QC_Enable()

TrayAbout(*) {
    MsgBox("RadAssist v2.4`n`nShift+Right-click in PowerScribe or Notepad`nto access radiology calculators.`n`nv2.2 Features:`n- Pause/Resume with backtick key (``)`n- RV/LV macro format for PowerScribe`n- Fleischner inserts after IMPRESSION:`n- OneDrive compatible (auto-fallback path)`n- ASCII chars for encoding compatibility`n`nSmart Parsers:`n- Smart Volume: Organ detection + prostate interpretation`n- Smart RV/LV: ratio with normal/borderline/elevated wording`n- Smart NASCET: Stenosis severity grading`n- Smart Adrenal: Washout percentages`n- Parse Nodules: Fleischner 2017 recommendations`n`nUtilities:`n- Report Header Template`n- Sectra History Copy (Ctrl+Shift+H)", "RadAssist", 0x40040)
}

TrayReload(*) {
    Reload()
}

TrayExit(*) {
    ExitApp()
}
