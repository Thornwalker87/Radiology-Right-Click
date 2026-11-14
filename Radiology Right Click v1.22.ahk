; ==========================================
; Radiologist's Helper Script (No OCR)
; Version: 1.20
; Description: This AutoHotkey script provides various calculation tools and utilities
;              for radiologists, including volume calculations, date estimations,
;              and other analyses, **without** OCR dependencies.
; ==========================================

#NoEnv
#SingleInstance, Force
#IfTimeout 2000   ; right-click check may wait for a briefly busy script (default 1 s let clicks fall through)
SetWorkingDir, %A_ScriptDir%

; -----------------------------------------
; Global User-Modifiable Toggles (read from Preferences)
; -----------------------------------------
global DisplayUnits := true
global DisplayAllValues := true
global ShowEllipsoidVolume := true
global ShowBulletVolume := true
global ShowPSADensity := true
global ShowPregnancyDates := true
global ShowMenstrualPhase := true
global ShowAdrenalWashout := true
global ShowThymusChemicalShift := true
global ShowHepaticSteatosis := true
global ShowMRILiverIron := true
global ShowStatistics := true
global ShowNumberRange := true
global PauseDuration := 180000
global DarkMode := false
global ShowCalciumScorePercentile := true
global ShowCitations := true
global ShowArterialAge := true
global ShowContrastPremedication := true
global ShowFleischnerCriteria := true
global ShowNASCETCalculator := true
global ShowRVLVCalculator := true
global ShowSpellCheck := true
global SP_ShowParse := true, SP_ShowTIRADS := true, SP_ShowORADS := true, SP_ShowBoneAge := false   ; Smart Parse (SmartParse_v1 module)
global SP_ShowLIRADS := false     ; Liver LI-RADS CT/MRI window (off by default)
global QC_PrefDial                ; Preferences: "Place calls from" choice
global QuickCallEnabled := true   ; Quick Call floating phone panel (QuickCall_v1.ahk)

; -------------- NEW/CHANGED CODE --------------
; Menu-sorting-related Globals
global MenuSortingMethod := "frequency"         ; can be "none", "frequency", or "custom"
global DefaultCustomMenuOrder := "CalculateEllipsoidVolume,CalculateBulletVolume,CalculatePSADensity,CompareNoduleSizes,SortNoduleSizes,CalculateStatistics,Range,CalculateCalciumScorePercentile,CalculatePregnancyDates,CalculateMenstrualPhase,CalculateAdrenalWashout,CalculateThymusChemicalShift,CalculateHepaticSteatosis,CalculateIronContent,CalculateContrastPremedication,CalculateFleischnerCriteria,CalculateNASCET,CalculateRVLV"
global CustomMenuOrder := ""  ; comma-separated function-list from .ini
global g_FunctionFrequency := {}  ; stores usage frequency per function

; Some global variables used throughout
global g_SelectedText := ""
global TargetApps := ["ahk_class Notepad", "ahk_exe notepad.exe", "ahk_class PowerScribe", "ahk_exe PowerScribe.exe", "ahk_class PowerScribe360", "ahk_exe Nuance.PowerScribe360.exe", "ahk_class PowerScribe | Reporting"]
global ResultText
global InvisibleControl
global originalMouseX, originalMouseY

; Some global reference variables
global g_References := {}  ; Will store {name: {type: "url|file|mapped", path: "path", uses: 0}}
global g_MaxReferences := 15
global vRefPath
global vRefType
global vRefList
global vRefName
global vRefPat
global RefList

; Some global AI variables
global g_AIPrompts := {}  ; Will store {name: {prompt: "prompt text", uses: 0}}
global g_MaxAIPrompts := 15
global g_PreferredAI := "claude"  ; can be "claude" or "chatgpt"
global vPromptName
global vPromptText
global PromptList
global g_OriginalPromptName := ""
; Default AI prompts
; Initialize the global object.
global DEFAULT_PROMPTS := Object()

; Build the "Edit Report" prompt object.
DEFAULT_PROMPTS["Edit Report"] := Object()
DEFAULT_PROMPTS["Edit Report"].prompt := "Edit this radiology report for clarity while preserving its original meaning. Do not explain your reasoning. Provide two outputs:`n`nVERSION WITH EDITS, in a standard output method:`nShow all changes using:`n- ~~strikethrough~~ for deletions`n- **bold** for additions`n`nFINAL VERSION, in an artifact or code based output window:`n{clean version in a copy-friendly format}`n`nREQUIREMENTS:`n1. Fix all:`n   - Grammar`n   - Punctuation`n   - Sentence structure`n   - Sentence fragments`n2. Maintain report structure:`n   - Keep narrative format if narrative`n   - Keep structured format if structured`n   - Preserve all original sections`n3. Verify presence and accuracy of:`n   - History`n   - Technique (do not modify)`n   - Comparison`n   - Findings`n   - Impression`n4. Flag potential errors in:`n   - Technique descriptions`n   - Comparison dates/studies`n   - Anatomical sidedness`n   - Contextual consistency`n`nALERTS:`n- Flag if technique section appears incorrect relative to the findings and impression (mismatch for billing)`n- Flag if comparison section contains errors`n- Flag any sidedness discrepancies"
DEFAULT_PROMPTS["Edit Report"].uses := 0

; Build the "Generate Impression" prompt object.
DEFAULT_PROMPTS["Generate Impression"] := Object()
DEFAULT_PROMPTS["Generate Impression"].prompt := "Generate a concise radiology report impression following these guidelines:`n`nSTRUCTURE`n- Address emergent findings and clinical questions first`n- Use complete sentences with minimal necessary words`n- Include only clinically significant diagnoses`n- Format for easy copy/paste`n`nREQUIRED STANDARDS`n- Follow established reporting systems where applicable:`n  - BI-RADS for breast imaging`n  - TI-RADS for thyroid nodules`n  - LI-RADS for liver lesions`n  - PI-RADS for prostate`n  - SRU consensus guidelines`n  - Fleischner criteria for pulmonary nodules`n  - Other ACR or society based guidelines.`n`nFOLLOW-UP RECOMMENDATIONS`n- Only recommend follow-up for:`n  - Established guideline-based scenarios`n  - Diagnostic uncertainty`n- Default intervals (unless guidelines specify otherwise):`n  - Concerning findings: 3 months`n  - Equivocal findings: 6 months`n  - Likely benign findings: 12 months`n Do not provide a ""no follow up recommended"" or ""correlate clinically"" recommendation.`n`nSIGNIFICANT INCIDENTALS`nInclude if present:`n- Pulmonary nodules`n- Indeterminate renal lesions`n- Vascular anomalies/aneurysms`n- Coronary artery calcification`n- Other findings requiring follow-up or intervention`n`nEXCLUDE`n- Benign or clinically insignificant findings`n- Chronic unchanged conditions`n- Anatomic variants without clinical impact`n- Normal post-surgical changes`n- Only state something is stable if there is a comparison referenced`n`nExample format:`n1. [Emergent findings/Clinical question answer]`n2. [Major diagnoses in order of clinical significance]`n3. [Relevant incidental findings requiring action]`n4. [Evidence-based follow-up recommendations]"
DEFAULT_PROMPTS["Generate Impression"].uses := 0


; For Fleischner
global g_Nodules := []
global g_FleischnerNodules := []
global g_ShowFleischnerCitation := false
global g_ShowFleischnerExclusions := false
global recommendations := {}

; -------------------------------------------------------------------------
; Load user preferences from an .ini file
; -------------------------------------------------------------------------
LoadPreferencesFromFile() {
    global DisplayUnits, DisplayAllValues, ShowEllipsoidVolume, ShowBulletVolume
    global ShowPSADensity, ShowPregnancyDates, ShowMenstrualPhase, ShowAdrenalWashout
    global ShowThymusChemicalShift, ShowHepaticSteatosis, ShowMRILiverIron
    global ShowStatistics, ShowNumberRange, PauseDuration, DarkMode
    global ShowCalciumScorePercentile, ShowCitations, ShowArterialAge
    global ShowContrastPremedication, ShowFleischnerCriteria, ShowNASCETCalculator, ShowRVLVCalculator
    global MenuSortingMethod, CustomMenuOrder
    global g_FunctionFrequency
	
	; Returns true only when a missing preferences.ini was restored from the backup
	if (CheckPreferencesIntegrity()) {
        MsgBox, Warning: Preferences file was missing and has been restored from backup.
    }

    preferencesFile := A_ScriptDir . "\preferences.ini"
    if (FileExist(preferencesFile)) {
        ; --- [Display] section ---
        IniRead, DisplayUnits, %preferencesFile%, Display, DisplayUnits, 1
        IniRead, DisplayAllValues, %preferencesFile%, Display, DisplayAllValues, 1
        IniRead, DarkMode, %preferencesFile%, Display, DarkMode, 0
        IniRead, ShowCitations, %preferencesFile%, Display, ShowCitations, 1
        IniRead, ShowArterialAge, %preferencesFile%, Display, ShowArterialAge, 1

        ; --- [Calculations] section ---
        IniRead, ShowEllipsoidVolume, %preferencesFile%, Calculations, ShowEllipsoidVolume, 1
        IniRead, ShowBulletVolume, %preferencesFile%, Calculations, ShowBulletVolume, 1
        IniRead, ShowPSADensity, %preferencesFile%, Calculations, ShowPSADensity, 1
        IniRead, ShowPregnancyDates, %preferencesFile%, Calculations, ShowPregnancyDates, 1
        IniRead, ShowMenstrualPhase, %preferencesFile%, Calculations, ShowMenstrualPhase, 1
        IniRead, ShowAdrenalWashout, %preferencesFile%, Calculations, ShowAdrenalWashout, 1
        IniRead, ShowThymusChemicalShift, %preferencesFile%, Calculations, ShowThymusChemicalShift, 1
        IniRead, ShowHepaticSteatosis, %preferencesFile%, Calculations, ShowHepaticSteatosis, 1
        IniRead, ShowMRILiverIron, %preferencesFile%, Calculations, ShowMRILiverIron, 1
        IniRead, ShowStatistics, %preferencesFile%, Calculations, ShowStatistics, 1
        IniRead, ShowNumberRange, %preferencesFile%, Calculations, ShowNumberRange, 1
        IniRead, ShowCalciumScorePercentile, %preferencesFile%, Calculations, ShowCalciumScorePercentile, 1
        IniRead, ShowContrastPremedication, %preferencesFile%, Calculations, ShowContrastPremedication, 1
        IniRead, ShowFleischnerCriteria, %preferencesFile%, Calculations, ShowFleischnerCriteria, 1
        IniRead, ShowNASCETCalculator, %preferencesFile%, Calculations, ShowNASCETCalculator, 1
        IniRead, ShowRVLVCalculator, %preferencesFile%, Calculations, ShowRVLVCalculator, 1

        ; --- [Script] section ---
        IniRead, PauseDuration, %preferencesFile%, Script, PauseDuration, 180000

        ; --- [Menu] or [Sorting] section ---
        IniRead, MenuSortingMethod, %preferencesFile%, Menu, SortingMethod, none
        IniRead, CustomMenuOrder, %preferencesFile%, Menu, CustomMenuOrder, %A_Space%
		
		; --- [References] section ---
		IniRead, referencesList, %preferencesFile%, References, SavedReferences, %A_Space%
		if (referencesList != "") {
			references := StrSplit(referencesList, "|")
			for _, ref in references {
				refData := StrSplit(ref, ":::")
				if (refData.Length() >= 4)
					g_References[refData[1]] := {type: refData[2], path: refData[3], uses: refData[4]}
			}
		}
		
		; --- [AI Prompt] section ---
		IniRead, g_PreferredAI, %preferencesFile%, AIAssistant, PreferredAI, claude
		IniRead, promptsList, %preferencesFile%, AIAssistant, SavedPrompts, %A_Space%
		if (promptsList = "") {
			; Load default prompts
			for name, data in DEFAULT_PROMPTS {
				g_AIPrompts[name] := {prompt: data.prompt, uses: 0}
			}
		}
		if (promptsList != "") {
			prompts := StrSplit(promptsList, "|")
			for _, prompt in prompts {
				promptData := StrSplit(prompt, ":::")
				if (promptData.Length() >= 3) {
					decodedPrompt := StrReplace(promptData[2], "\n", "`n")
					decodedPrompt := StrReplace(decodedPrompt, "\p", "|")
					g_AIPrompts[promptData[1]] := {prompt: decodedPrompt, uses: promptData[3]}
				}
			}
		}
		
		; [Spell Check]
		IniRead, ShowSpellCheck, %preferencesFile%, Calculations, ShowSpellCheck, 1
		IniRead, QuickCallEnabled, %preferencesFile%, QuickCall, Enabled, 1
		

        ; Convert string "1" to boolean true, etc.
        DisplayUnits := (DisplayUnits = "1")
        DisplayAllValues := (DisplayAllValues = "1")
        ShowEllipsoidVolume := (ShowEllipsoidVolume = "1")
        ShowBulletVolume := (ShowBulletVolume = "1")
        ShowPSADensity := (ShowPSADensity = "1")
        ShowPregnancyDates := (ShowPregnancyDates = "1")
        ShowMenstrualPhase := (ShowMenstrualPhase = "1")
        ShowAdrenalWashout := (ShowAdrenalWashout = "1")
        ShowThymusChemicalShift := (ShowThymusChemicalShift = "1")
        ShowHepaticSteatosis := (ShowHepaticSteatosis = "1")
        ShowMRILiverIron := (ShowMRILiverIron = "1")
        ShowStatistics := (ShowStatistics = "1")
        ShowNumberRange := (ShowNumberRange = "1")
        DarkMode := (DarkMode = "1")
        ShowCalciumScorePercentile := (ShowCalciumScorePercentile = "1")
        ShowCitations := (ShowCitations = "1")
        ShowArterialAge := (ShowArterialAge = "1")
        ShowContrastPremedication := (ShowContrastPremedication = "1")
        ShowFleischnerCriteria := (ShowFleischnerCriteria = "1")
        ShowNASCETCalculator := (ShowNASCETCalculator = "1")
        ShowRVLVCalculator := (ShowRVLVCalculator = "1")
        PauseDuration += 0
		ShowSpellCheck := (ShowSpellCheck = "1")
		QuickCallEnabled := (QuickCallEnabled = "1")
        IniRead, SP_ShowParse, %preferencesFile%, SmartParse, ShowMenu, 1
        IniRead, SP_ShowTIRADS, %preferencesFile%, SmartParse, ShowTIRADS, 1
        IniRead, SP_ShowORADS, %preferencesFile%, SmartParse, ShowORADS, 1
        IniRead, SP_ShowBoneAge, %preferencesFile%, SmartParse, ShowBoneAge, 0
        IniRead, SP_ShowLIRADS, %preferencesFile%, SmartParse, ShowLIRADS, 0
        SP_ShowLIRADS := (SP_ShowLIRADS = "1")
        SP_ShowParse := (SP_ShowParse = "1"), SP_ShowTIRADS := (SP_ShowTIRADS = "1")
        SP_ShowORADS := (SP_ShowORADS = "1"), SP_ShowBoneAge := (SP_ShowBoneAge = "1")

        ; Load frequency data
        LoadMenuFrequencies()
    } else {
        ; If no .ini file, do nothing special. Will be created on saving prefs.
    }
}
LoadPreferencesFromFile()
InitializeRecommendations()  ; For Fleischner

; Quick Call floating phone panel (functions are embedded at the end of this file)
if (QuickCallEnabled)
    QC_Enable()
SP_Init()     ; Smart Parse module (functions embedded at the end of this file)

; -------------------------------------------------------------------------
; Load stored frequency data from .ini
; -------------------------------------------------------------------------
LoadMenuFrequencies() {
    global g_FunctionFrequency
    preferencesFile := A_ScriptDir . "\preferences.ini"
    section := "Frequency"
    freqKeys := []

    IniRead, entireSection, %preferencesFile%, %section%
    if (entireSection != "ERROR") {
        Loop, Parse, entireSection, `n, `r
        {
            line := A_LoopField
            if (RegExMatch(line, "^(.*?)=(.*)$", m)) {
                cmd := m1
                val := m2+0
                g_FunctionFrequency[cmd] := val
            }
        }
    }
}

; -------------------------------------------------------------------------
; Save frequency to .ini after increment
; -------------------------------------------------------------------------
IncrementFunctionFrequency(cmd) {
    global g_FunctionFrequency
    preferencesFile := A_ScriptDir . "\preferences.ini"

    if !(g_FunctionFrequency.HasKey(cmd)) {
        g_FunctionFrequency[cmd] := 0
    }
    g_FunctionFrequency[cmd]++

    IniWrite, % g_FunctionFrequency[cmd], %preferencesFile%, Frequency, %cmd%
}

; ------------------------------------------
; HOTKEYS, MENUS, AND SCRIPT LOGIC
; ------------------------------------------
#If IsTargetApp()

; Minor key hook: reset timer if user typed ". " quickly
$Space::
    if (A_PriorKey == "." and A_TimeSincePriorHotkey < 500) {
        lastPeriodTime := 0
    }
    SendInput {Space}
return

; -------------------------------------------------------------------------
; Right-click context menu activation (only in specified apps)
; -------------------------------------------------------------------------
CoordMode, Mouse, Screen
RButton::
{
    ; Store original mouse position
    CoordMode, Mouse, Screen  ; Ensure we're using screen coordinates
    MouseGetPos, originalX, originalY, windowUnderCursor
    ; Never activate one of this script's own tooltips/menus that happens to be under the mouse
    WinGet, underPid, PID, ahk_id %windowUnderCursor%
    if (underPid = DllCall("GetCurrentProcessId"))
        windowUnderCursor := WinActive("A")
    
    if (windowUnderCursor != WinActive("A")) {
        WinActivate, ahk_id %windowUnderCursor%
        Sleep, 50
        ; Restore mouse position after activation
        MouseMove, %originalX%, %originalY%, 0
    }

    ; Grab selected text
    g_SelectedText := GetSelectedText()
    SP_SetTarget(WinExist("A"))   ; Smart Parse pastes back into this window

    ; Build + show menu
    CreateCustomMenu()
    Menu, CustomMenu, Show
    Menu, CustomMenu, DeleteAll
    return
}
#If

; -------------------------------------------------------------------------
; Validate whether the current window is a target app
; -------------------------------------------------------------------------
IsTargetApp() {
    MouseGetPos, , , windowUnderCursor
    WinGetClass, windowClass, ahk_id %windowUnderCursor%
    WinGet, windowExe, ProcessName, ahk_id %windowUnderCursor%
    ; WHY: One of this script's own tooltips/menus can be under the mouse for a moment
    ;      (e.g. "Inserted"); then judge by the active window instead.
    WinGet, underPid, PID, ahk_id %windowUnderCursor%
    if (underPid = DllCall("GetCurrentProcessId") || windowClass = "tooltips_class32") {
        WinGetClass, windowClass, A
        WinGet, windowExe, ProcessName, A
    }

    for index, app in TargetApps {
        if (windowClass == StrReplace(app, "ahk_class ", "")
         || windowExe   == StrReplace(app, "ahk_exe ",   "")) {
            return true
        }
    }
    return false
}

; -------------------------------------------------------------------------
; Build the context (right-click) menu
; -------------------------------------------------------------------------
CreateCustomMenu() {
    global DarkMode

    Menu, CustomMenu, Add
    Menu, CustomMenu, DeleteAll

    ; Set menu colors based on Dark Mode
    ; Dark Mode: real dark menus with white text (the old grey background kept black text)
    SP_SetDarkMenus(DarkMode)
    Menu, CustomMenu, Color, Default

    ; Standard editing items (always at the top)
    Menu, CustomMenu, Add, Cut, MenuCut
    Menu, CustomMenu, Add, Copy, MenuCopy
    Menu, CustomMenu, Add, Paste, MenuPaste
    Menu, CustomMenu, Add, Delete, MenuDelete
	Menu, CustomMenu, Add
    ; Smart Parse: highlight dictation -> auto-detect calculation (SmartParse_v1 module)
    if (SP_ShowParse) {
        SP_AddMenu("CustomMenu", SP_ShowTIRADS, SP_ShowORADS, SP_ShowBoneAge, SP_ShowLIRADS)
        Menu, CustomMenu, Add
    }
	
	; Add spell check suggestion if enabled and text is selected
	if (ShowSpellCheck = 1 && g_SelectedText != "") {
		Menu, CustomMenu, Add, Check Spelling, CheckSpelling
		Menu, CustomMenu, Add  ; Separator
	}
	
	
    ; Build + sort menu items
    menuItems := BuildMenuItemsArray()
    SortMenuItems(menuItems)

    ; Add sorted items
    For _, item in menuItems {
        if (item.show) {
            Menu, CustomMenu, Add, % item.title, % item.command
        }
    }
	
	; Add References submenu
    Menu, CustomMenu, Add  ; Separator
    CreateReferencesMenu()
    Menu, CustomMenu, Add, References, :ReferencesMenu
	
	Menu, CustomMenu, Add
	CreateAIAssistantMenu()
	Menu, CustomMenu, Add, AI Assistant, :AIAssistantMenu

    ; Final items (always at bottom)
    Menu, CustomMenu, Add
    if (QuickCallEnabled)
        Menu, CustomMenu, Add, Quick Call Panel (Ctrl+Alt+P), QC_MenuShow
    Menu, CustomMenu, Add, Pause Script, PauseScript
    Menu, CustomMenu, Add, Preferences, ShowPreferences
}

; -------------------------------------------------------------------------
; Return a list of all possible menu items with relevant data
; -------------------------------------------------------------------------
BuildMenuItemsArray() {
    global ShowCalciumScorePercentile, ShowEllipsoidVolume, ShowBulletVolume, ShowPSADensity
    global ShowPregnancyDates, ShowMenstrualPhase, ShowAdrenalWashout, ShowThymusChemicalShift, ShowHepaticSteatosis
    global ShowMRILiverIron, ShowStatistics, ShowNumberRange, ShowContrastPremedication
    global ShowFleischnerCriteria, ShowNASCETCalculator, ShowRVLVCalculator, g_FunctionFrequency

    items := []
    ; Each entry => {title, command, freq, show, customKey}
    ; customKey is used to see how it matches in the CustomMenuOrder
    ; 'command' must match our label name exactly for the "IncrementFunctionFrequency"

    items.Push({title: "Compare Measurement Sizes", command: "CompareNoduleSizes", freq: g_FunctionFrequency["CompareNoduleSizes"]+0, show: true,  customKey: "CompareNoduleSizes"})
    items.Push({title: "Sort Measurement Sizes", command: "SortNoduleSizes", freq: g_FunctionFrequency["SortNoduleSizes"]+0, show: true,  customKey: "SortNoduleSizes"})

    items.Push({title: "Calculate Calcium Score Percentile", command: "CalculateCalciumScorePercentile", freq: g_FunctionFrequency["CalculateCalciumScorePercentile"]+0, show: ShowCalciumScorePercentile, customKey: "CalculateCalciumScorePercentile"})
    items.Push({title: "Calculate Ellipsoid Volume", command: "CalculateEllipsoidVolume", freq: g_FunctionFrequency["CalculateEllipsoidVolume"]+0, show: ShowEllipsoidVolume, customKey: "CalculateEllipsoidVolume"})
    items.Push({title: "Calculate Bullet Volume", command: "CalculateBulletVolume", freq: g_FunctionFrequency["CalculateBulletVolume"]+0, show: ShowBulletVolume, customKey: "CalculateBulletVolume"})
    items.Push({title: "Calculate PSA Density", command: "CalculatePSADensity", freq: g_FunctionFrequency["CalculatePSADensity"]+0, show: ShowPSADensity, customKey: "CalculatePSADensity"})
    items.Push({title: "Calculate Pregnancy Dates", command: "CalculatePregnancyDates", freq: g_FunctionFrequency["CalculatePregnancyDates"]+0, show: ShowPregnancyDates, customKey: "CalculatePregnancyDates"})
    items.Push({title: "Calculate Menstrual Phase", command: "CalculateMenstrualPhase", freq: g_FunctionFrequency["CalculateMenstrualPhase"]+0, show: ShowMenstrualPhase, customKey: "CalculateMenstrualPhase"})
    items.Push({title: "Calculate Adrenal Washout", command: "CalculateAdrenalWashout", freq: g_FunctionFrequency["CalculateAdrenalWashout"]+0, show: ShowAdrenalWashout, customKey: "CalculateAdrenalWashout"})
    items.Push({title: "Calculate Thymus Chemical Shift", command: "CalculateThymusChemicalShift", freq: g_FunctionFrequency["CalculateThymusChemicalShift"]+0, show: ShowThymusChemicalShift, customKey: "CalculateThymusChemicalShift"})
    items.Push({title: "Calculate Hepatic Steatosis", command: "CalculateHepaticSteatosis", freq: g_FunctionFrequency["CalculateHepaticSteatosis"]+0, show: ShowHepaticSteatosis, customKey: "CalculateHepaticSteatosis"})
    items.Push({title: "MRI Liver Iron Content", command: "CalculateIronContent", freq: g_FunctionFrequency["CalculateIronContent"]+0, show: ShowMRILiverIron, customKey: "CalculateIronContent"})
    items.Push({title: "Calculate Statistics", command: "Statistics", freq: g_FunctionFrequency["Statistics"]+0, show: ShowStatistics, customKey: "Statistics"})
    items.Push({title: "Calculate Number Range", command: "Range", freq: g_FunctionFrequency["Range"]+0, show: ShowNumberRange, customKey: "Range"})
    items.Push({title: "Calculate Contrast Premedication", command: "CalculateContrastPremedication", freq: g_FunctionFrequency["CalculateContrastPremedication"]+0, show: ShowContrastPremedication, customKey: "CalculateContrastPremedication"})
    items.Push({title: "Calculate Fleischner Criteria", command: "CalculateFleischnerCriteria", freq: g_FunctionFrequency["CalculateFleischnerCriteria"]+0, show: ShowFleischnerCriteria, customKey: "CalculateFleischnerCriteria"})
    items.Push({title: "Calculate NASCET", command: "CalculateNASCET", freq: g_FunctionFrequency["CalculateNASCET"]+0, show: ShowNASCETCalculator, customKey: "CalculateNASCET"})
    items.Push({title: "Calculate RV/LV Ratio", command: "CalculateRVLV", freq: g_FunctionFrequency["CalculateRVLV"]+0, show: ShowRVLVCalculator, customKey: "CalculateRVLV"})
	; items.Push({title: "Check Spelling", command: "CheckSpelling", freq: g_FunctionFrequency["CheckSpelling"]+0, show: ShowSpellCheck, customKey: "CheckSpelling"})

    return items
}

; -------------------------------------------------------------------------
; Sort the menu items (by freq or custom)
; -------------------------------------------------------------------------
FrequencySort(a, b) {
    return b.freq - a.freq
}

CustomSort(a, b) {
    global CustomMenuOrder
    static mapOrder := {}

    ; Clear and rebuild mapOrder
    mapOrder := {}
    customList := StrSplit(CustomMenuOrder, ",")
    For i, cmd in customList {
        cmd := Trim(cmd)
        mapOrder[cmd] := i
    }

    aPos := mapOrder.HasKey(a.customKey) ? mapOrder[a.customKey] : 999999
    bPos := mapOrder.HasKey(b.customKey) ? mapOrder[b.customKey] : 999999
    return aPos - bPos
}

SortMenuItems(ByRef items) {
    global MenuSortingMethod, CustomMenuOrder

    if (MenuSortingMethod = "none" || MenuSortingMethod = "") {
        return  ; do nothing
    } else if (MenuSortingMethod = "frequency") {
        tempArray := []
        for index, item in items {
            tempArray.Insert(item)
        }

        tempSorted := []
        while (tempArray.Length() > 0) {
            highestFreq := -1
            highestIndex := 0
            for index, item in tempArray {
                if (item.freq > highestFreq) {
                    highestFreq := item.freq
                    highestIndex := index
                }
            }
            tempSorted.Insert(tempArray[highestIndex])
            tempArray.RemoveAt(highestIndex)
        }
        items := tempSorted
    } else if (MenuSortingMethod = "custom") {
        if (CustomMenuOrder = "") {
            return  ; no custom order specified
        }

        orderMap := {}
        customList := StrSplit(CustomMenuOrder, ",")
        for index, cmd in customList {
            cmd := Trim(cmd)
            orderMap[cmd] := index
        }

        tempArray := []
        for index, item in items {
            tempArray.Insert(item)
        }

        tempSorted := []
        while (tempArray.Length() > 0) {
            lowestOrder := 999999
            lowestIndex := 0
            for index, item in tempArray {
                itemOrder := orderMap.HasKey(item.customKey) ? orderMap[item.customKey] : 999999
                if (itemOrder < lowestOrder) {
                    lowestOrder := itemOrder
                    lowestIndex := index
                }
            }
            tempSorted.Insert(tempArray[lowestIndex])
            tempArray.RemoveAt(lowestIndex)
        }
        items := tempSorted
    }
}

; -------------------------------------------------------------------------
; Basic editing items
; -------------------------------------------------------------------------
MenuCut:
    Send, ^x
return

MenuCopy:
    Send, ^c
return

MenuPaste:
    Send, ^v
return

MenuDelete:
    Send, {Delete}
return

; -------------------------------------------------------------------------
; GetSelectedText: Captures text from the clipboard after Ctrl+C
; -------------------------------------------------------------------------
; WHY: ClipWait used to be 0.1 s - too short for Windows 11 Notepad / PowerScribe,
;      so the highlighted text was often missed. Wait longer and retry once.
GetSelectedText() {
    OldClipboard := ClipboardAll
    SelectedText := ""
    Loop, 2 {
        Clipboard := ""
        if (A_Index = 2) {
            KeyWait, Shift, T1
            KeyWait, Control, T0.5
            Sleep, 50
        }
        Send, {Shift up}^c
        ClipWait, % (A_Index = 1 ? 0.6 : 1.2)
        if (!ErrorLevel) {
            SelectedText := Clipboard
            break
        }
    }
    Clipboard := OldClipboard
    OldClipboard := ""
    return SelectedText
}

; -------------------------------------------------------------------------
; ShowResult( ResultString )
; Displays the text in a small, always-on-top GUI near the mouse pointer.
; -------------------------------------------------------------------------
ShowResult(Result) {
    global DarkMode, originalMouseX, originalMouseY

    CoordMode, Mouse, Screen
    MouseGetPos, originalMouseX, originalMouseY

    ; Which monitor are we on?
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (originalMouseX >= monAreaLeft && originalMouseX <= monAreaRight
         && originalMouseY >= monAreaTop  && originalMouseY <= monAreaBottom) {
            activeMonitor := A_Index
            break
        }
    }

    ; Get monitor area
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop

    ; We'll measure text first
    maxWidth := monitorWidth * 0.5
    maxHeight := monitorHeight * 0.5

    Gui, TempMeasure:New, +AlwaysOnTop
    Gui, TempMeasure:Font, s10, Segoe UI
    Gui, TempMeasure:Add, Text, w%maxWidth% wrap, %Result%
    GuiControlGet, TextSize, TempMeasure:Pos, Static1
    Gui, TempMeasure:Destroy

    requiredWidth := TextSizeW + 40
    requiredHeight := TextSizeH + 80
    guiWidth := (requiredWidth > maxWidth) ? maxWidth : requiredWidth
    guiHeight := (requiredHeight > maxHeight) ? maxHeight : requiredHeight
    guiWidth := (guiWidth < 300) ? 300 : guiWidth
    guiHeight := (guiHeight < 200) ? 200 : guiHeight

    xPos := originalMouseX + 10
    yPos := originalMouseY + 10
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight

    Gui, ResultBox:New, +AlwaysOnTop -SysMenu +Owner
    Gui, ResultBox:Margin, 10, 10

    if (DarkMode) {
        Gui, ResultBox:Color, 0x2C2C2C, 0x2C2C2C
        textColor := "cE0E0E0"
        buttonOptions := "Background333333 c999999"
    } else {
        Gui, ResultBox:Color, 0xF0F0F0, 0xF0F0F0
        textColor := "c000000"
        buttonOptions := "Background777777 cFFFFFF"
    }

    Gui, ResultBox:Font, s10 %textColor%, Segoe UI
    editHeight := guiHeight - 50
    Gui, ResultBox:Add, Edit, vResultText ReadOnly -E0x200 +E0x20000 Wrap VScroll w%guiWidth% h%editHeight%, %Result%

    Gui, ResultBox:Font, s9 bold, Segoe UI
    Gui, ResultBox:Add, Button, gCloseResultBox w90 x10 y+10 %buttonOptions%, Close

    Gui, ResultBox:Add, Text, Hidden vInvisibleControl
    Gui, ResultBox:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Result
    GuiControl, Focus, InvisibleControl

    ; Move mouse over close button to make it easy for user
    GuiControlGet, ClosePos, ResultBox:Pos, Close
    MouseMove, % xPos + ClosePosX + (ClosePosW / 2), % yPos + ClosePosY + (ClosePosH / 2), 0

    ; Copy result to clipboard
    Clipboard := Result
    return
}

CloseResultBox:
    Gui, ResultBox:Destroy
return

; -------------------------------------------------------------------------
; Calculation Functions (menu-driven)
; Each function increments usage frequency
; -------------------------------------------------------------------------
CalculateCalciumScorePercentile:
    IncrementFunctionFrequency("CalculateCalciumScorePercentile")
    Result := CalculateCalciumScorePercentile(g_SelectedText)
    ShowResult(Result)
return

CalculateEllipsoidVolume:
    IncrementFunctionFrequency("CalculateEllipsoidVolume")
    Result := CalculateEllipsoidVolume(g_SelectedText)
    ShowResult(Result)
return

CalculateBulletVolume:
    IncrementFunctionFrequency("CalculateBulletVolume")
    Result := CalculateBulletVolume(g_SelectedText)
    ShowResult(Result)
return

CalculatePSADensity:
    IncrementFunctionFrequency("CalculatePSADensity")
    Result := CalculatePSADensity(g_SelectedText)
    ShowResult(Result)
return

CalculatePregnancyDates:
    IncrementFunctionFrequency("CalculatePregnancyDates")
    Result := CalculatePregnancyDates(g_SelectedText)
    ShowResult(Result)
return

CalculateMenstrualPhase:
    IncrementFunctionFrequency("CalculateMenstrualPhase")
    Result := CalculateMenstrualPhase(g_SelectedText)
    ShowResult(Result)
return

CompareNoduleSizes:
    IncrementFunctionFrequency("CompareNoduleSizes")
    Result := CompareNoduleSizes(g_SelectedText)
    ShowResult(Result)
return

SortNoduleSizes:
    IncrementFunctionFrequency("SortNoduleSizes")
    ProcessedText := ProcessAllNoduleSizes(g_SelectedText)
    if (ProcessedText != g_SelectedText) {
        leadingSpace := (SubStr(g_SelectedText, 1, 1) == " ") ? " " : ""
        trailingSpace := (SubStr(g_SelectedText, 0) == " ") ? " " : ""
        Clipboard := leadingSpace . Trim(ProcessedText) . trailingSpace
        Send, ^v
    }
return

CalculateAdrenalWashout:
    IncrementFunctionFrequency("CalculateAdrenalWashout")
    Result := CalculateAdrenalWashout(g_SelectedText)
    ShowResult(Result)
return

CalculateThymusChemicalShift:
    IncrementFunctionFrequency("CalculateThymusChemicalShift")
    Result := CalculateThymusChemicalShift(g_SelectedText)
    ShowResult(Result)
return

CalculateHepaticSteatosis:
    IncrementFunctionFrequency("CalculateHepaticSteatosis")
    Result := CalculateHepaticSteatosis(g_SelectedText)
    ShowResult(Result)
return

CalculateIronContent:
    IncrementFunctionFrequency("CalculateIronContent")
    Result := EstimateIronContent(g_SelectedText)
    ShowResult(Result)
return

Statistics:
    IncrementFunctionFrequency("Statistics")
    Result := CalculateStatistics(g_SelectedText)
    ShowResult(Result)
return

Range:
    IncrementFunctionFrequency("Range")
    Result := CalculateRange(g_SelectedText)
    ShowResult(Result)
return

CalculateFleischnerCriteria:
    IncrementFunctionFrequency("CalculateFleischnerCriteria")
    Result := ProcessNodules(g_SelectedText)
    ShowResult(Result)
return

CalculateNASCET:
    IncrementFunctionFrequency("CalculateNASCET")
    ; Try text parsing first; if fails or no text, show GUI
    if (g_SelectedText != "") {
        Result := CalculateNASCET(g_SelectedText)
        if (!InStr(Result, "Could not find two diameters")) {
            ShowResult(Result)
            return
        }
    }
    ; Fall back to GUI input
    ShowNASCETGui()
return

CalculateContrastPremedication:
    IncrementFunctionFrequency("CalculateContrastPremedication")
    Result := ""  ; We'll trigger a small UI for premed
    CalculateContrastPremedication()
return

CalculateRVLV:
    IncrementFunctionFrequency("CalculateRVLV")
    CalculateRVLV()
return

CheckSpelling:
    IncrementFunctionFrequency("CheckSpelling")
    selectedWord := Trim(g_SelectedText)
    if (selectedWord = "") {
        return
    }
    
    correctedWord := GoogleAutoCorrect(SanitizePHI(selectedWord))
    
    if (correctedWord != "" && correctedWord != selectedWord) {
        ; Create right-click menu with suggestions
        Menu, SpellSuggestions, Add
        Menu, SpellSuggestions, DeleteAll
        Menu, SpellSuggestions, Add, %correctedWord%, ReplaceWithSuggestion
        Menu, SpellSuggestions, Show
        Menu, SpellSuggestions, DeleteAll
    } else {
        ShowResult("No spelling suggestions found.")
    }
return

ReplaceWithSuggestion:
    Clipboard := A_ThisMenuItem
    Send, ^v
return

; -------------------------------------------------------------------------
; RestoreDefaults: Resets certain fields in the Preferences GUI
; -------------------------------------------------------------------------
RestoreDefaults:
    global DefaultCustomMenuOrder
    GuiControl,, MenuSortingMethodChoice, |none|frequency||custom
    GuiControl,, CustomMenuOrderBox, % DefaultCustomMenuOrder
return

; -------------------------------------------------------------------------
; Script pause/resume
; -------------------------------------------------------------------------
PauseScript() {
    global PauseDuration
    if (PauseDuration < 3600000) {
        pauseMinutes := Floor(PauseDuration / 60000)
        pauseDisplay := pauseMinutes . " minute" . (pauseMinutes != 1 ? "s" : "")
    } else {
        pauseHours := Floor(PauseDuration / 3600000)
        pauseDisplay := pauseHours . " hour" . (pauseHours != 1 ? "s" : "")
    }
    Suspend, On
    SetTimer, ResumeScript, %PauseDuration%
    MsgBox, 0, Script Paused, Script paused for %pauseDisplay%. Click OK to resume immediately.
    Suspend, Off
    SetTimer, ResumeScript, Off
}

ResumeScript:
    Suspend, Off
    SetTimer, ResumeScript, Off
    MsgBox, 0, Script Resumed, The script has been automatically resumed.
return

; -------------------------------------------------------------------------
; Preferences GUI
; -------------------------------------------------------------------------
ShowPreferences() {
    global DisplayUnits, DisplayAllValues, ShowEllipsoidVolume, ShowBulletVolume, ShowPSADensity
    global ShowPregnancyDates, ShowMenstrualPhase, PauseDuration, ShowAdrenalWashout
    global ShowThymusChemicalShift, ShowHepaticSteatosis, ShowMRILiverIron, ShowStatistics
    global ShowNumberRange, DarkMode, ShowCalciumScorePercentile, ShowCitations, ShowArterialAge
    global ShowContrastPremedication, ShowFleischnerCriteria, ShowNASCETCalculator, ShowRVLVCalculator
    global MenuSortingMethod, CustomMenuOrder

    ; Position near mouse
    CoordMode, Mouse, Screen
    MouseGetPos, px, py

    SysGet, monitorCount, MonitorCount
    activeMonitor := 1
    Loop, %monitorCount% {
        SysGet, monArea, Monitor, %A_Index%
        if (px >= monAreaLeft && px <= monAreaRight && py >= monAreaTop && py <= monAreaBottom) {
            activeMonitor := A_Index
            break
        }
    }
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop

    ; Increased height to accommodate new elements
    guiW := 700
    guiH := 545
    xPos := px + 10
    yPos := py + 10
    if (xPos + guiW > workAreaRight)
        xPos := workAreaRight - guiW
    if (yPos + guiH > workAreaBottom)
        yPos := workAreaBottom - guiH

    if (DarkMode) {
        bgColor := "0x2C2C2C"
        textColor := "cE0E0E0"
        buttonOptions := "Background333333 c999999"
    } else {
        bgColor := "0xF0F0F0"
        textColor := "c000000"
        buttonOptions := "Background777777 cFFFFFF"
    }

    if (PauseDuration = 180000)
        currentPauseDuration := "3 minutes"
    else if (PauseDuration = 600000)
        currentPauseDuration := "10 minutes"
    else if (PauseDuration = 1800000)
        currentPauseDuration := "30 minutes"
    else if (PauseDuration = 3600000)
        currentPauseDuration := "1 hour"
    else if (PauseDuration = 36000000)
        currentPauseDuration := "10 hours"
    else
        currentPauseDuration := PauseDuration . " ms"

    Gui, Preferences:New, +AlwaysOnTop +HwndprefHwnd
    Gui, Preferences:Color, %bgColor%, %bgColor%
    Gui, Preferences:Font, s10 %textColor%, Segoe UI

    ; Basic settings section
    Gui, Add, Text, x10 y10 w200, Select functions to display:
    Gui, Add, Checkbox, x10 y30 w200 vDarkMode Checked%DarkMode%, Dark Mode

    ; Calculation functions (two columns - keeps the window short)
    Gui, Add, Checkbox, x10 y60 w205 vShowEllipsoidVolume Checked%ShowEllipsoidVolume%, Ellipsoid Volume
    Gui, Add, Checkbox, x10 y86 w205 vShowBulletVolume Checked%ShowBulletVolume%, Bullet Volume
    Gui, Add, Checkbox, x10 y112 w205 vShowPSADensity Checked%ShowPSADensity%, PSA Density
    Gui, Add, Checkbox, x10 y138 w205 vShowPregnancyDates Checked%ShowPregnancyDates%, Pregnancy Dates
    Gui, Add, Checkbox, x10 y164 w205 vShowMenstrualPhase Checked%ShowMenstrualPhase%, Menstrual Phase
    Gui, Add, Checkbox, x10 y190 w205 vShowAdrenalWashout Checked%ShowAdrenalWashout%, Adrenal Washout
    Gui, Add, Checkbox, x10 y216 w205 vShowThymusChemicalShift Checked%ShowThymusChemicalShift%, Thymus Chemical Shift
    Gui, Add, Checkbox, x10 y242 w205 vShowHepaticSteatosis Checked%ShowHepaticSteatosis%, Hepatic Steatosis
    Gui, Add, Checkbox, x10 y268 w205 vShowMRILiverIron Checked%ShowMRILiverIron%, MRI Liver Iron Content
    Gui, Add, Checkbox, x10 y294 w205 vShowStatistics Checked%ShowStatistics%, Calculate Statistics
    Gui, Add, Checkbox, x225 y60 w205 vShowNumberRange Checked%ShowNumberRange%, Calculate Number Range
    Gui, Add, Checkbox, x225 y86 w205 vShowCalciumScorePercentile Checked%ShowCalciumScorePercentile%, Calcium Score Percentile
    Gui, Add, Checkbox, x225 y112 w205 vShowCitations Checked%ShowCitations%, Show Citations in Output
    Gui, Add, Checkbox, x225 y138 w205 vShowArterialAge Checked%ShowArterialAge%, Show Arterial Age
    Gui, Add, Checkbox, x225 y164 w205 vShowContrastPremedication Checked%ShowContrastPremedication%, Contrast Premedication
    Gui, Add, Checkbox, x225 y190 w205 vShowFleischnerCriteria Checked%ShowFleischnerCriteria%, Fleischner Criteria
    Gui, Add, Checkbox, x225 y216 w205 vShowNASCETCalculator Checked%ShowNASCETCalculator%, NASCET Calculator
    Gui, Add, Checkbox, x225 y242 w205 vShowRVLVCalculator Checked%ShowRVLVCalculator%, RV/LV Ratio Calculator
    Gui, Add, Checkbox, x225 y268 w205 vShowSpellCheck Checked%ShowSpellCheck%, Spell Check

    ; Right column
    Gui, Add, Text, x450 y10 w230, Pause Length (current: %currentPauseDuration%):
    Gui, Add, DropDownList, x450 y30 w220 vPauseDurationChoice, 3 minutes|10 minutes|30 minutes|1 hour|10 hours
    if (PauseDuration = 180000)
        GuiControl, Choose, PauseDurationChoice, 1
    else if (PauseDuration = 600000)
        GuiControl, Choose, PauseDurationChoice, 2
    else if (PauseDuration = 1800000)
        GuiControl, Choose, PauseDurationChoice, 3
    else if (PauseDuration = 3600000)
        GuiControl, Choose, PauseDurationChoice, 4
    else if (PauseDuration = 36000000)
        GuiControl, Choose, PauseDurationChoice, 5
    Gui, Add, Text, x450 y70 w230, Menu Sorting Method:
    Gui, Add, DropDownList, x450 y90 w220 vMenuSortingMethodChoice, none|frequency|custom
    if (MenuSortingMethod = "none")
        GuiControl, Choose, MenuSortingMethodChoice, 1
    else if (MenuSortingMethod = "frequency")
        GuiControl, Choose, MenuSortingMethodChoice, 2
    else if (MenuSortingMethod = "custom")
        GuiControl, Choose, MenuSortingMethodChoice, 3
    Gui, Add, Text, x450 y125 w230, Custom menu order (comma list):
    Gui, Add, Edit, x450 y145 w230 h50 vCustomMenuOrderBox, % CustomMenuOrder

    Gui, Add, GroupBox, x445 y205 w240 h155
    ; title as a Text label: themed group box titles stay black in Dark Mode
    Gui, Add, Text, x455 y198, % " Smart Parse (highlight + right-click) "
    Gui, Add, Checkbox, x455 y225 w225 vSP_ShowParse Checked%SP_ShowParse%, Smart Parse menu (auto-detect)
    Gui, Add, Checkbox, x455 y250 w225 vSP_ShowTIRADS Checked%SP_ShowTIRADS%, Thyroid ACR TI-RADS
    Gui, Add, Checkbox, x455 y275 w225 vSP_ShowORADS Checked%SP_ShowORADS%, Ovarian cyst (O-RADS / SRU)
    Gui, Add, Checkbox, x455 y300 w225 vSP_ShowBoneAge Checked%SP_ShowBoneAge%, Bone Age (Greulich && Pyle) - MSK
    Gui, Add, Checkbox, x455 y325 w225 vSP_ShowLIRADS Checked%SP_ShowLIRADS%, Liver LI-RADS (CT/MRI v2018)

    ; Quick Call: panel on/off and where calls are placed from
    dm := QC_GetDialMode()
    dmIdx := (dm = "cell") ? 2 : (dm = "teams") ? 3 : 1
    Gui, Add, GroupBox, x445 y375 w240 h115
    Gui, Add, Text, x455 y368, % " Quick Call (phone panel) "
    Gui, Add, Checkbox, x455 y393 w225 vQuickCallEnabled Checked%QuickCallEnabled%, Show panel (Ctrl+Alt+P)
    Gui, Add, Text, x455 y420 w225, Place calls from:
    Gui, Add, DropDownList, x455 y440 w225 vQC_PrefDial AltSubmit Choose%dmIdx%, This computer (Google Voice)|My cell phone (Google Voice)|Microsoft Teams
    Gui, Font, s8 c808080
    Gui, Add, Text, x455 y467 w225, Cell: Google Voice rings your cell first.
    Gui, Font, s10 %textColor%

    ; Buttons at the bottom
    Gui, Add, Button, x305 y502 w135 gRestoreDefaults %buttonOptions%, Restore Defaults
    Gui, Add, Button, x450 y502 w135 gSavePreferences %buttonOptions%, Save

    if (DarkMode)
        SP_DarkenGui(prefHwnd)      ; checkbox/group text readable on dark
    Gui, Show, x%xPos% y%yPos% w%guiW% h%guiH%, Preferences
}

; -------------------------------------------------------------------------
; SavePreferences: stores user selection into .ini
; -------------------------------------------------------------------------
SavePreferences:
    Gui, Submit, NoHide
    global DisplayUnits, DisplayAllValues, DarkMode
    global ShowEllipsoidVolume, ShowBulletVolume, ShowPSADensity, ShowPregnancyDates
    global ShowMenstrualPhase, ShowAdrenalWashout, ShowThymusChemicalShift
    global ShowHepaticSteatosis, ShowMRILiverIron, ShowStatistics, ShowNumberRange
    global PauseDuration, ShowCitations, ShowArterialAge
    global ShowCalciumScorePercentile, ShowContrastPremedication
    global ShowFleischnerCriteria, ShowNASCETCalculator, ShowRVLVCalculator
    global MenuSortingMethod, CustomMenuOrder
    global MenuSortingMethodChoice, CustomMenuOrderBox

    if (PauseDurationChoice = "3 minutes")
        PauseDuration := 180000
    else if (PauseDurationChoice = "10 minutes")
        PauseDuration := 600000
    else if (PauseDurationChoice = "30 minutes")
        PauseDuration := 1800000
    else if (PauseDurationChoice = "1 hour")
        PauseDuration := 3600000
    else if (PauseDurationChoice = "10 hours")
        PauseDuration := 36000000

    MenuSortingMethod := MenuSortingMethodChoice
    CustomMenuOrder := CustomMenuOrderBox

    SavePreferencesToFile()
    Gui, Destroy
    QC_ApplyEnabled(QuickCallEnabled)   ; turn the Quick Call panel on/off now
    qcModes := ["url", "cell", "teams"]
    if (QC_PrefDial >= 1 && QC_PrefDial <= 3 && qcModes[QC_PrefDial] != QC_GetDialMode())
        QC_SetDialMode(qcModes[QC_PrefDial])   ; explains the Google Voice setting when switching computer <-> cell
return

PreferencesGuiClose:
PreferencesGuiEscape:
    Gui, Destroy
return

; -------------------------------------------------------------------------
; SavePreferencesToFile: Writes final user preferences to .ini
; -------------------------------------------------------------------------
SavePreferencesToFile() {
    ; Create a backup of current preferences before making changes
    preferencesFile := A_ScriptDir . "\preferences.ini"
    backupFile := A_ScriptDir . "\preferences.backup.ini"
    if (FileExist(preferencesFile))
        FileCopy, %preferencesFile%, %backupFile%, 1

    ; 1. First verify we have valid data before writing
    if (!g_References)
        g_References := {}
    if (!g_AIPrompts) {
        g_AIPrompts := {}
        ; Load default prompts if empty
        for name, data in DEFAULT_PROMPTS {
            g_AIPrompts[name] := {prompt: data.prompt, uses: 0}
        }
    }

    ; 2. Build the references string with validation
    referencesList := ""
    for name, data in g_References {
        if (name && data.type && data.path) {  ; Validate required fields
            if (referencesList != "")
                referencesList .= "|"
            referencesList .= name . ":::" . data.type . ":::" . data.path . ":::" . (data.uses ? data.uses : 0)
        }
    }

    ; 3. Build the prompts string with validation
    promptsList := ""
    for name, data in g_AIPrompts {
        if (name && data.prompt) {  ; Validate required fields
            if (promptsList != "")
                promptsList .= "|"
            encodedPrompt := StrReplace(data.prompt, "`n", "\n")
            encodedPrompt := StrReplace(encodedPrompt, "|", "\p")
            promptsList .= name . ":::" . encodedPrompt . ":::" . (data.uses ? data.uses : 0)
        }
    }

    ; 4. Write to a temporary file first
    tempFile := A_ScriptDir . "\preferences.tmp"
    
    ; Write display settings
    IniWrite, %DisplayUnits%, %tempFile%, Display, DisplayUnits
    IniWrite, %DisplayAllValues%, %tempFile%, Display, DisplayAllValues
    IniWrite, %DarkMode%, %tempFile%, Display, DarkMode
    IniWrite, %ShowCitations%, %tempFile%, Display, ShowCitations
    IniWrite, %ShowArterialAge%, %tempFile%, Display, ShowArterialAge

    ; Write calculation settings
    IniWrite, %ShowEllipsoidVolume%, %tempFile%, Calculations, ShowEllipsoidVolume
    IniWrite, %ShowBulletVolume%, %tempFile%, Calculations, ShowBulletVolume
    IniWrite, %ShowPSADensity%, %tempFile%, Calculations, ShowPSADensity
    IniWrite, %ShowPregnancyDates%, %tempFile%, Calculations, ShowPregnancyDates
    IniWrite, %ShowMenstrualPhase%, %tempFile%, Calculations, ShowMenstrualPhase
    IniWrite, %ShowAdrenalWashout%, %tempFile%, Calculations, ShowAdrenalWashout
    IniWrite, %ShowThymusChemicalShift%, %tempFile%, Calculations, ShowThymusChemicalShift
    IniWrite, %ShowHepaticSteatosis%, %tempFile%, Calculations, ShowHepaticSteatosis
    IniWrite, %ShowMRILiverIron%, %tempFile%, Calculations, ShowMRILiverIron
    IniWrite, %ShowStatistics%, %tempFile%, Calculations, ShowStatistics
    IniWrite, %ShowNumberRange%, %tempFile%, Calculations, ShowNumberRange
    IniWrite, %ShowCalciumScorePercentile%, %tempFile%, Calculations, ShowCalciumScorePercentile
    IniWrite, %ShowContrastPremedication%, %tempFile%, Calculations, ShowContrastPremedication
    IniWrite, %ShowFleischnerCriteria%, %tempFile%, Calculations, ShowFleischnerCriteria
    IniWrite, %ShowNASCETCalculator%, %tempFile%, Calculations, ShowNASCETCalculator
    IniWrite, %ShowRVLVCalculator%, %tempFile%, Calculations, ShowRVLVCalculator
    IniWrite, %ShowSpellCheck%, %tempFile%, Calculations, ShowSpellCheck
    IniWrite, %QuickCallEnabled%, %tempFile%, QuickCall, Enabled
    IniWrite, %SP_ShowParse%, %tempFile%, SmartParse, ShowMenu
    IniWrite, %SP_ShowTIRADS%, %tempFile%, SmartParse, ShowTIRADS
    IniWrite, %SP_ShowORADS%, %tempFile%, SmartParse, ShowORADS
    IniWrite, %SP_ShowBoneAge%, %tempFile%, SmartParse, ShowBoneAge
    IniWrite, %SP_ShowLIRADS%, %tempFile%, SmartParse, ShowLIRADS

    ; Write script settings
    IniWrite, %PauseDuration%, %tempFile%, Script, PauseDuration

    ; Write menu settings
    IniWrite, %MenuSortingMethod%, %tempFile%, Menu, SortingMethod
    IniWrite, %CustomMenuOrder%, %tempFile%, Menu, CustomMenuOrder

    ; Write references with validation
    if (referencesList != "")
        IniWrite, %referencesList%, %tempFile%, References, SavedReferences

    ; Write AI settings with validation
    if (g_PreferredAI)
        IniWrite, %g_PreferredAI%, %tempFile%, AIAssistant, PreferredAI
    if (promptsList != "")
        IniWrite, %promptsList%, %tempFile%, AIAssistant, SavedPrompts

    ; 5. Verify the temporary file was written successfully
    if (!FileExist(tempFile)) {
        ; If temp file creation failed, restore from backup
        if (FileExist(backupFile))
            FileCopy, %backupFile%, %preferencesFile%, 1
        return
    }

    ; 6. Replace the actual preferences file with the temporary file
    FileCopy, %tempFile%, %preferencesFile%, 1
    FileDelete, %tempFile%
    
    ; 7. Keep latest backup
    FileCopy, %preferencesFile%, %backupFile%, 1
}

; Add this function to check preferences integrity
CheckPreferencesIntegrity() {
    ; WHY: A fresh install has no preferences.ini and no backup - that is normal, not
    ;      corruption. Only report (return true) when the file was actually restored.
    preferencesFile := A_ScriptDir . "\preferences.ini"
    backupFile := A_ScriptDir . "\preferences.backup.ini"

    if (!FileExist(preferencesFile)) {
        if (FileExist(backupFile)) {
            FileCopy, %backupFile%, %preferencesFile%, 1
            return true
        }
        return false
    }

    ; Saved references/prompts vanished but the backup still has them: restore quietly
    IniRead, references, %preferencesFile%, References, SavedReferences, %A_Space%
    IniRead, prompts, %preferencesFile%, AIAssistant, SavedPrompts, %A_Space%
    if (references = "" && prompts = "" && FileExist(backupFile)) {
        IniRead, bRefs, %backupFile%, References, SavedReferences, %A_Space%
        IniRead, bPrompts, %backupFile%, AIAssistant, SavedPrompts, %A_Space%
        if (bRefs != "" || bPrompts != "")
            FileCopy, %backupFile%, %preferencesFile%, 1
    }
    return false
}


; ------------------------------------------
; "Actual" Calculation Code
; ------------------------------------------

; -------------------------------------------------------------
; 1) CalculateEllipsoidVolume
; -------------------------------------------------------------
CalculateEllipsoidVolume(input) {
    RegExNeedle := "\s*(\d+(?:\.\d+)?)\s*[x,]\s*(\d+(?:\.\d+)?)\s*[x,]\s*(\d+(?:\.\d+)?)\s*"
    if (RegExMatch(input, RegExNeedle, match)) {
        dimensions := [match1, match2, match3]
        dimensions := SortDimensions(dimensions)

        ; mm vs cm check
        isMillimeters := ((InStr(dimensions[1], ".") = 0)
                       && (InStr(dimensions[2], ".") = 0)
                       && (InStr(dimensions[3], ".") = 0))
        if (isMillimeters) {
            dimensions[1] := dimensions[1] / 10
            dimensions[2] := dimensions[2] / 10
            dimensions[3] := dimensions[3] / 10
        }

        volume := (1/6) * 3.141592653589793 * dimensions[1] * dimensions[2] * dimensions[3]
        volumeRounded := (volume < 1) ? Round(volume, 3) : Round(volume, 1)
        result := input . " (" . volumeRounded . (DisplayUnits ? " cc" : "") . ")"
        return result
    } else {
        return "Invalid input format for ellipsoid volume.`nExample: 3 x 2 x 1 cm"
    }
}

; -------------------------------------------------------------
; 2) CalculateBulletVolume
; -------------------------------------------------------------
CalculateBulletVolume(input) {
    RegExNeedle := "\s*(\d+(?:\.\d+)?)\s*[x,]\s*(\d+(?:\.\d+)?)\s*[x,]\s*(\d+(?:\.\d+)?)\s*"
    if (RegExMatch(input, RegExNeedle, match)) {
        dimensions := [match1, match2, match3]
        dimensions := SortDimensions(dimensions)

        isMillimeters := ((InStr(dimensions[1], ".") = 0)
                       && (InStr(dimensions[2], ".") = 0)
                       && (InStr(dimensions[3], ".") = 0))
        if (isMillimeters) {
            dimensions[1] := dimensions[1] / 10
            dimensions[2] := dimensions[2] / 10
            dimensions[3] := dimensions[3] / 10
        }

        volume := dimensions[1] * dimensions[2] * dimensions[3] * (5 * 3.141592653589793 / 24)
        volumeRounded := (volume < 1) ? Round(volume, 3) : Round(volume, 1)
        return input . " (" . volumeRounded . (DisplayUnits ? " cc" : "") . ")"
    } else {
        return "Invalid input format for bullet volume.`nExample: 3 x 2 x 1 cm"
    }
}

; -------------------------------------------------------------
; 3) CalculatePSADensity
; -------------------------------------------------------------
CalculatePSADensity(input) {
    volNotGiven := 1
    volumeMethod := "User Supplied"

    PSARegEx := "i)PSA\s*(?:level|value)?:?\s*(\d+(?:\.\d+)?)(?:\s*(?:ng\/ml|ng/mL|ng\/cc|ng/cc)?)"
    VolumeRegEx := "i)(?:(?:volume:?\s*(\d+(?:\.\d+)?)(?:\s*(?:cc|cm3|mL|ml)))|(?:Prostate )?Size:?.*?\((\d+(?:\.\d+?)\s*cc\)|(\d+(?:\.\d+)?)(?:\s*x\s*\d+(?:\.\d+)?\s*x\s*\d+(?:\.\d+)?\s*cm\s*\((\d+(?:\.\d+?)\s*cc\)))"

    if (RegExMatch(input, PSARegEx, PSAMatch)) {
        PSALevel := PSAMatch1
    } else {
        return "Invalid format for PSA density.`nExample:`nPSA: 5.6 ng/mL`nSize: 3.5 x 5.4 x 2.5 cm"
    }

    if (RegExMatch(input, VolumeRegEx, VolumeMatch)) {
        if (VolumeMatch1 != "")
            ProstateVolume := VolumeMatch1
        else if (VolumeMatch2 != "")
            ProstateVolume := VolumeMatch2
        else if (VolumeMatch4 != "")
            ProstateVolume := VolumeMatch4
    } else {
        volNotGiven := 0
        bulletResult := CalculateBulletVolume(input)
        if (!InStr(bulletResult, "Invalid input")) {
            ProstateVolume := RegExReplace(bulletResult, "s).*?(\d+(?:\.\d+)?)(?:\s*cc)?\).*", "$1")
            volumeMethod := "Bullet Volume"

            if (ProstateVolume >= 55) {
                ellipsoidResult := CalculateEllipsoidVolume(input)
                volumeMethod := "Ellipsoid Volume"
                if (!InStr(ellipsoidResult, "Invalid input")) {
                    ProstateVolume := RegExReplace(ellipsoidResult, "s).*?(\d+(?:\.\d+)?)(?:\s*cc)?\).*", "$1")
                }
            }
        } else {
            return "Prostate volume not found.`nExample:`nPSA: 5.6 ng/mL`nSize: 3.5 x 5.4 x 2.5 cm"
        }
    }

    PSADensity := PSALevel / ProstateVolume
    PSADensity := Round(PSADensity, 3)

    if (volNotGiven = 0) {
        result := input . "`nProstate volume: " . ProstateVolume . " cc (" . volumeMethod . ")`n"
        result .= "PSA Density: " . PSADensity . (DisplayUnits ? " ng/mL/cc" : "")
    } else {
        result := input . "`nPSA Density: " . PSADensity . (DisplayUnits ? " ng/mL/cc" : "")
    }
    return result
}

; -------------------------------------------------------------
; 4) CalculatePregnancyDates
; -------------------------------------------------------------
CalculatePregnancyDates(input) {
    LMPRegEx := "i)(?:LMP|Last\s*Menstrual\s*Period).*?(\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4})"
    GARegEx := "i)(\d+)(?:\s*(?:weeks?|w))?\s*(?:and|&|,|-)?\s*(\d+)?(?:\s*(?:days?|d))?(?:.*?(?:as of|on)\s+(today|\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4}))?"

    if (RegExMatch(input, LMPRegEx, LMPMatch)) {
        LMPDate := ParseDate(LMPMatch1)
        if (LMPDate = "Invalid Date") {
            return "Invalid LMP date. Please use MM/DD/YYYY or DD/MM/YYYY."
        }
        return CalculateDatesFromLMP(LMPDate)
    } else if (RegExMatch(input, GARegEx, GAMatch)) {
        WeeksGA := GAMatch1+0
        DaysGA := (GAMatch2 != "") ? GAMatch2+0 : 0
        ReferenceDate := (GAMatch3 != "") ? (GAMatch3 = "today" ? A_Now : ParseDate(GAMatch3)) : A_Now
        return CalculateDatesFromGA(WeeksGA, DaysGA, ReferenceDate)
    } else {
        return "Invalid format for pregnancy date calculation.`nExample:`nLMP: 01/15/2023 or GA: 12 weeks and 3 days as of today"
    }
}

; -------------------------------------------------------------
; 5) CalculateMenstrualPhase
; -------------------------------------------------------------
CalculateMenstrualPhase(input) {
    LMPRegEx := "i)(?:LMP|Last\s*Menstrual\s*Period)\s*:?\s*(\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4})"
    if (RegExMatch(input, LMPRegEx, LMPMatch)) {
        LMPDate := ParseDate(LMPMatch1)
        if (LMPDate = "Invalid Date") {
            return "Invalid LMP date. Use MM/DD/YYYY or DD/MM/YYYY."
        }
        return DetermineMenstrualPhase(LMPDate)
    } else {
        return "Invalid format for menstrual phase calculation.`nExample: LMP: 05/01/2023"
    }
}

; -------------------------------------------------------------
; 6) Compare / sort nodule sizes
; -------------------------------------------------------------
CompareNoduleSizes(input) {
    static RegExNeedle := "i)(?:(\d{1,2}/\d{1,2}/\d{2,4})[:.]?\s*)?(\d+(?:\.\d+)?(?:\s*(?:x|\*)\s*\d+(?:\.\d+)?){0,2})\s*(cm|mm)?.*?(?:previous(?:ly)?|prior|before|old|initial).*?(?:(\d{1,2}/\d{1,2}/\d{2,4})[:.]?\s*)?(\d+(?:\.\d+)?(?:\s*(?:x|\*)\s*\d+(?:\.\d+)?){0,2})\s*(cm|mm)?(?:\s*(?:on|dated?)\s*(\d{1,2}/\d{1,2}/\d{2,4}))?"
    
    if (!RegExMatch(input, RegExNeedle, match)) {
        RegExNeedle := "i)(?:previous(?:ly)?|prior|before|old|initial).*?(?:(\d{1,2}/\d{1,2}/\d{2,4})[:.]?\s*)?(\d+(?:\.\d+)?(?:\s*(?:x|\*)\s*\d+(?:\.\d+)?){0,2})\s*(cm|mm)?(?:\s*(?:on|dated?)\s*(\d{1,2}/\d{1,2}/\d{2,4}))?.*?(?:now|current(?:ly)?|present|new|recent(?:ly)?|follow[- ]?up).*?(?:(\d{1,2}/\d{1,2}/\d{2,4})[:.]?\s*)?(\d+(?:\.\d+)?(?:\s*(?:x|\*)\s*\d+(?:\.\d+)?){0,2})\s*(cm|mm)?"
        if (!RegExMatch(input, RegExNeedle, match)) {
            return "Invalid input format. Please provide both current and previous measurements."
        }
        current := match6 . " " . match7, previous := match2 . " " . match3
        currentDate := match5, previousDate := match1 ? match1 : match4
    } else {
        current := match2 . " " . match3, previous := match5 . " " . match6
        currentDate := match1, previousDate := match4 ? match4 : match7
    }
    
    return CompareMeasurements(previous, current, previousDate, currentDate, input)
}

ProcessAllNoduleSizes(input) {
    RegExNeedleComma3 := "\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*"
    RegExNeedleX3 := "\s*(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*"
    RegExNeedleComma2 := "\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*"
    RegExNeedleX2 := "\s*(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*"

    input := ProcessPattern(input, RegExNeedleComma3, 3)
    input := ProcessPattern(input, RegExNeedleX3, 3)
    input := ProcessPattern(input, RegExNeedleComma2, 2)
    input := ProcessPattern(input, RegExNeedleX2, 2)

    return input
}

ProcessPattern(input, RegExNeedle, dimensions) {
    pos := 1
    while (pos := RegExMatch(input, RegExNeedle, match, pos)) {
        if (dimensions == 3)
            processed := ProcessNoduleSizes(match1, match2, match3)
        else
            processed := ProcessNoduleSizes(match1, match2)

        if (processed != match) {
            input := SubStr(input, 1, pos-1) . processed . SubStr(input, pos+StrLen(match))
        }
        pos += StrLen(processed)
    }
    return input
}

ProcessNoduleSizes(a, b, c := "") {
    aNum := a+0, bNum := b+0
    cNum := (c != "") ? c+0 : ""

    if (c != "") {
        if (aNum < bNum) {
            temp := a, a := b, b := temp
            tempNum := aNum, aNum := bNum, bNum := tempNum
        }
        if (bNum < cNum) {
            temp := b, b := c, c := temp
            tempNum := bNum, bNum := cNum, cNum := tempNum
        }
        if (aNum < bNum) {
            temp := a, a := b, b := temp
            tempNum := aNum, aNum := bNum, bNum := tempNum
        }
        return " " . Trim(a) . " x " . Trim(b) . " x " . Trim(c) . " "
    } else {
        if (aNum < bNum) {
            temp := a, a := b, b := temp
        }
        return " " . Trim(a) . " x " . Trim(b) . " "
    }
}

; -------------------------------------------------------------
; 7) Basic Statistics
; -------------------------------------------------------------
CalculateStatistics(input) {
    numbers := ExtractNumbers(input)
    count := numbers.Length()
    if (count = 0) {
        return "No numbers found in text."
    }

    result := "Statistics:`n"
    result .= "Count: " . count . "`n"
    result .= "Sum: " . Round(CalculateSum(numbers), 1) . "`n"
    result .= "Mean: " . Round(CalculateMean(numbers), 1) . "`n"
    result .= "Median: " . Round(CalculateMedian(numbers), 1) . "`n"
    result .= "Min: " . Round(Min(numbers*), 1) . "`n"
    result .= "Max: " . Round(Max(numbers*), 1) . "`n"

    if (count >= 9) {
        Q1 := Round(CalculateQuartile(numbers, 0.25), 1)
        Q3 := Round(CalculateQuartile(numbers, 0.75), 1)
        IQR := Q3 - Q1
        median := Round(CalculateMedian(numbers), 1)
        result .= "Q1: " . Q1 . "`n"
        result .= "Q3: " . Q3 . "`n"
        result .= "IQR: " . Round(IQR, 1) . "`n"
        result .= "IQR/Median: " . Round(IQR / median, 2) . "`n"
        result .= "Standard Deviation: " . Round(CalculateStandardDeviation(numbers), 1) . "`n"
    }
    return result
}

ExtractNumbers(input) {
    numbers := []
    input := RegExReplace(input, "i)(?:^|\n|\s)(?:slice|observation|sample|number|#|no\.?)\s*\d+:?\s*", "`n")
    RegExNeedle := "(-?\d+(?:\.\d+)?)(?:\s*(?:cm|mm)?)"
    pos := 1
    while (pos := RegExMatch(input, RegExNeedle, match, pos)) {
        numbers.Push(match1+0)
        pos += StrLen(match)
    }
    return numbers
}

CalculateSum(arr) {
    total := 0
    for index, value in arr {
        total += value
    }
    return total
}

CalculateMean(numbers) {
    sum := 0
    for i, num in numbers {
        sum += num
    }
    return (sum / numbers.Length())
}

CalculateMedian(numbers) {
    sortedNumbers := SortArray(numbers)
    count := sortedNumbers.Length()

    if (count = 0)
        return 0
    else if (Mod(count, 2) = 0) {
        middle1 := sortedNumbers[count//2]
        middle2 := sortedNumbers[(count//2)+1]
        return (middle1 + middle2) / 2
    } else {
        return sortedNumbers[Floor(count/2)+1]
    }
}

SortArray(numbers) {
    sortedNumbers := []
    for index, value in numbers {
        sortedNumbers.Push(value)
    }
    sortedNumbers.Sort()
    return sortedNumbers
}

CalculateQuartile(numbers, percentile) {
    sortedNumbers := SortArray(numbers)
    count := sortedNumbers.Length()
    position := (count - 1) * percentile + 1
    lower := Floor(position)
    upper := Ceil(position)
    if (lower = upper) {
        return sortedNumbers[lower]
    } else {
        return sortedNumbers[lower] + (position - lower)*(sortedNumbers[upper] - sortedNumbers[lower])
    }
}

CalculateStandardDeviation(numbers) {
    mean := CalculateMean(numbers)
    sumSquaredDiff := 0
    for i, num in numbers {
        diff := num - mean
        sumSquaredDiff += diff*diff
    }
    variance := sumSquaredDiff / (numbers.Length()-1)
    return Sqrt(variance)
}

; -------------------------------------------------------------
; 8) Number Range
; -------------------------------------------------------------
CalculateRange(input) {
    numbers := []
    unit := ""
    RegExNeedle := "(-?\d+(?:\.\d+)?)(?:\s*((?:cm/s|mm/s|m/s|km/h|mph|cm|mm|Hz|T|mg|m|ml|mL|cc|s|min|hr|days?|weeks?|months?|years?|g|ng|ng/ml|ng/mL|mmol/L|µmol/L|°F|°C)(?:/(?:day|week|month|year))?))?"
    pos := 1
    while (pos := RegExMatch(input, RegExNeedle, match, pos)) {
        numbers.Push(match1+0)
        if (match2 != "" && unit = "")
            unit := match2
        pos += StrLen(match)
    }
    if (numbers.Length() = 0) {
        return "No numbers found."
    }
    minValue := Min(numbers*)
    maxValue := Max(numbers*)
    result := Round(minValue,1) . " - " . Round(maxValue,1)
    if (unit != "")
        result .= " " . unit
    return result
}

; -------------------------------------------------------------
; 9) Adrenal Washout
; -------------------------------------------------------------
CalculateAdrenalWashout(input) {
	global ShowCitations
	
    RegExNeedle := "i)(?:(?:unenhanced|non-?enhanced|intrinsic|pre-?contrast|baseline|native)(?:\s+CT)?(?:\s+density|\s+HU|\s+hounsfield\s+units?)?[\s:]*(-?\d+(?:\.\d+)?)\s*(?:HU|hounsfield\s+units?)?).*?(?:(?:enhanced|post-?contrast|arterial|portal\s+venous?|60-?75\s*(?:second|sec)|1-?2\s*min(?:ute)?)(?:\s+CT)?(?:\s+density|\s+HU|\s+hounsfield\s+units?)?[\s:]*(-?\d+(?:\.\d+)?)\s*(?:HU|hounsfield\s+units?)?).*?(?:(?:delayed|late|15\s*min(?:ute)?|10-?15\s*min(?:ute)?|post-?contrast)(?:\s+CT)?(?:\s+density|\s+HU|\s+hounsfield\s+units?)?[\s:]*(-?\d+(?:\.\d+)?)\s*(?:HU|hounsfield\s+units?)?)"

    if (RegExMatch(input, RegExNeedle, match)) {
        unenhanced := match1
        enhanced := match2
        delayed := match3

        absoluteWashout := ((enhanced - delayed) / (enhanced - unenhanced)) * 100
        relativeWashout := ((enhanced - delayed) / enhanced) * 100

        result := input . "`n`n"
        result .= "Absolute Washout: " . Round(absoluteWashout, 1) . "% ... (Ref adenomas: >=60%)" . "`n"
        result .= "Relative Washout: " . Round(relativeWashout, 1) . "% ... (Ref adenomas: >=40%)" . "`n`n"
		
		if(ShowCitations=1){
				result .= "`nMayo-Smith WW, Song JH, Boland GL, Francis IR, Israel GM, Mazzaglia PJ, Berland LL, Pandharipande PV. Management of Incidental Adrenal Masses: A White Paper of the ACR Incidental Findings Committee. J Am Coll Radiol. 2017 Aug;14(8):1038-1044.`n`n"
		}
		
        result .= InterpretAdrenalWashout(absoluteWashout, relativeWashout, unenhanced, enhanced, delayed)
        return result
    } else {
        RegExNeedle := "i)(?:(?:enhanced|post-?contrast|arterial|portal\s+venous?|60-?75\s*(?:second|sec)|1-?2\s*min(?:ute)?)(?:\s+CT)?(?:\s+density|\s+HU|\s+hounsfield\s+units?)?[\s:]*(-?\d+(?:\.\d+)?)\s*(?:HU|hounsfield\nits?)?).*?(?:(?:delayed|late|15\s*min(?:ute)?|10-?15\s*min(?:ute)?|post-?contrast)(?:\s+CT)?(?:\s+density|\s+HU|\s+hounsfield\s+units?)?[\s:]*(-?\d+(?:\.\d+)?)\s*(?:HU|hounsfield\s+units?)?)"

        if (RegExMatch(input, RegExNeedle, match)) {
            enhanced := match1
            delayed := match2

            relativeWashout := ((enhanced - delayed) / enhanced) * 100

            result := input . "`n`n"
            result .= "Relative Washout: " . Round(relativeWashout, 1) . "%`n`n"
            result .= InterpretAdrenalWashout(0, relativeWashout, unenhanced, enhanced, delayed)
			
			if(ShowCitations=1){
				result .= "`n`n`nMayo-Smith WW, Song JH, Boland GL, Francis IR, Israel GM, Mazzaglia PJ, Berland LL, Pandharipande PV. Management of Incidental Adrenal Masses: A White Paper of the ACR Incidental Findings Committee. J Am Coll Radiol. 2017 Aug;14(8):1038-1044.`n`n"
			}
            return result
        } else {
            return "Invalid input format for adrenal washout calculation.`nSample syntax: Unenhanced: 10 HU, Enhanced: 80 HU, Delayed: 40 HU"
        }
    }
}

InterpretAdrenalWashout(absoluteWashout, relativeWashout, unenhanced, enhanced, delayed) {
    result := ""

    ; Check if unenhanced is null or empty
    if (unenhanced = "" or unenhanced = "NULL") {
        unenhanced := "N/A"
        isUnenhancedAvailable := false
    } else {
        isUnenhancedAvailable := true
        unenhanced += 0  ; Convert to number
    }

    ; Check for enhancing mass
    if (isUnenhancedAvailable) {
        enhancedChange := CheckEnhancement(enhanced, unenhanced)
        delayedChange := CheckEnhancement(delayed, unenhanced)
		
         ; Add interpretation based on unenhanced HU
        if (unenhanced <= 10) {
            result .= "Unenhanced HU less than 10 is typically suggestive of a benign adrenal adenoma. "
        } else if (unenhanced > 43) {
            result .= "Unenhanced HU >43 in a noncalcified, nonhemorrhagic lesion is suspicious for malignancy, regardless of washout characteristics. "
        }
		
        if (Abs(enhancedChange) >= 10 or Abs(delayedChange) >= 10) {
            if (enhancedChange < 0 or delayedChange < 0) {
                result .= "The adrenal mass demonstrates unexpected de-enhancement (decrease in HU in enhanced or delayed phase). This is an atypical finding. "
                result .= "Caution: Standard washout calculations may not be applicable in this case. "
            } else {
                result .= "The adrenal mass demonstrates enhancement. "
                
                ; Interpret washout only if there's positive enhancement
                if (absoluteWashout >= 60 or relativeWashout >= 40) {
                    result .= "Adrenal washout characteristics are suggestive of a benign adrenal adenoma. "
                } else {
                    result .= "Washout characteristics are indeterminate. "
                }
            }
        } else {
            result .= "The adrenal mass does not demonstrate significant enhancement (<10 HU change in both enhanced and delayed phases compared to unenhanced). This may represent a cyst, hemorrhage, or other non-enhancing lesion. Further characterization with additional imaging may be necessary. "
        }

    } else {
        result .= "Unenhanced HU value is not available. "
        
        if (absoluteWashout >= 60 or relativeWashout >= 40) {
            result .= "Based on the provided washout values alone, characteristics are suggestive of a benign adrenal adenoma. However, this interpretation is limited without the unenhanced HU value. "
        } else {
			result .= "Washout characteristics are indeterminate. "
		}
    }

    return Trim(result)
}
; Function to check enhancement
CheckEnhancement(value, baseline) {
    if (value = "" or value = "NULL" or baseline = "N/A")
        return 0
    return (value - baseline)
}

; -------------------------------------------------------------
; 10) Thymus Chemical Shift
; -------------------------------------------------------------
CalculateThymusChemicalShift(input) {
    RegExNeedle := "i)thymus.*?((?:in[- ]?phase|IP|T1IP)).*?(\d+).*?((?:out[- ]?of[- ]?phase|OP|OOP|T1OP)).*?(\d+)(?:.*?paraspinous.*?((?:in[- ]?phase|IP|T1IP)).*?(\d+).*?((?:out[- ]?of[- ]?phase|OP|OOP|T1OP)).*?(\d+))?"

    if (RegExMatch(input, RegExNeedle, match)) {
        thymusInPhase := match2
        thymusOutOfPhase := match4
        paraspinousInPhase := match6
        paraspinousOutOfPhase := match8

        signalIntensityIndex := ((thymusInPhase-thymusOutOfPhase)/thymusInPhase)*100

        result := input
        if (paraspinousInPhase && paraspinousOutOfPhase) {
            outOfPhaseSignalRatio := (thymusOutOfPhase) / paraspinousOutOfPhase
            inPhaseSignalRatio := (thymusInPhase) / paraspinousInPhase
            chemicalShiftRatio := outOfPhaseSignalRatio / inPhaseSignalRatio

            if (DisplayAllValues) {
                result .= "`n`nChemical Shift Ratio: " . Round(chemicalShiftRatio, 3) . " (hyperplasia < 0.849)`n"    
                result .= "Thymus Signal Intensity Index (SII): " . round(signalIntensityIndex, 2) . "% (hyperplasia > 8.92)`n"
            }
            result .= "`n" . InterpretThymusChemicalShift(chemicalShiftRatio, signalIntensityIndex)
        } else {
            if (DisplayAllValues) {
                result .= "`nThymus Signal Intensity Index (SII): " . round(signalIntensityIndex, 2) . "%`n"
            }
            result .= "`n" . InterpretThymusChemicalShift("", signalIntensityIndex)
        }
        return result
    } else {
        return "Invalid input format for thymus chemical shift calculation.`nSample syntax: Thymus IP: 100, OP: 80, Paraspinous IP: 90, OP: 85`nOr for thymus only: Thymus IP: 100, OP: 80"
    }
}

InterpretThymusChemicalShift(chemicalShiftRatio := "", signalIntensityIndex := "") {
    global ShowCitations
    result := ""

    if (chemicalShiftRatio != "" && signalIntensityIndex != "") {
        ; Both chemical shift ratio and signal intensity index are provided
        if (chemicalShiftRatio > 0.849 && signalIntensityIndex > 8.92) {
            result := "Interpretation: Chemical Shift Ratio is greater than 0.849 and Signal Intensity Index is greater than 8.92%. Calculations are in conflict and therefore indeterminate, though probably consistent with thymic hyperplasia with single dual echo technique.`n`n"
        } else if (chemicalShiftRatio <= 0.849 && signalIntensityIndex > 8.92) {
            result := "Interpretation: Chemical Shift Ratio is less than or equal to 0.849 and Signal Intensity Index is greater than 8.92%. Findings are consistent with thymic hyperplasia with single dual echo technique. `n`n"
        } else if (chemicalShiftRatio > 0.849 && signalIntensityIndex <= 8.92) {
            result := "Interpretation: Chemical Shift Ratio is greater than 0.849 and Signal Intensity Index is less than or equal to 8.92%. Findings are not consistent with with typical thymic hyperplasia with single dual echo technique.`n`n"
        } else {  ; chemicalShiftRatio <= 0.849 && signalIntensityIndex <= 8.92
            result := "Interpretation: Chemical Shift Ratio is less than or equal to 0.849 and Signal Intensity Index is less than or equal to 8.92%. Calculations are in conflict and therefore indeterminate, possibly thymic hyperplasia with single dual echo technique.`n`n"
        }
    } else if (chemicalShiftRatio != "" && signalIntensityIndex == "") {
        ; Only chemical shift ratio is provided
        result := "Interpretation: Chemical Shift Ratio is " . (chemicalShiftRatio > 0.849 ? "greater than" : "less than or equal to") . " 0.849 with single dual echo technique.`n`n"
    } else if (chemicalShiftRatio == "" && signalIntensityIndex != "") {
        ; Only signal intensity index is provided
        if (signalIntensityIndex > 8.92) {
            result := "Interpretation: Signal Intensity Index is greater than 8.92%. This suggests thymic hyperplasia with single dual echo technique.`n`n"
        } else {
            result := "Interpretation: Signal Intensity Index is less than or equal to 8.92%. Findings are not consistent with typical thymic hyperplasia with single dual echo technique.`n`n"
        }
    } else {
        ; Neither chemical shift ratio nor signal intensity index is provided
        result := "Error: Both Chemical Shift Ratio and Signal Intensity Index are missing. At least one value is required for interpretation.`n`n"
    }

    if (ShowCitations = 1) {
        result .= "Citation: Priola AM, Priola SM, Ciccone G, Evangelista A, Cataldi A, Gned D, Pazè F, Ducco L, Moretti F, Brundu M, Veltri A. Differentiation of rebound and lymphoid thymic hyperplasia from anterior mediastinal tumors with dual-echo chemical-shift MR imaging in adulthood: reliability of the chemical-shift ratio and signal intensity index. Radiology. 2015 Jan;274(1):238-49. doi: 10.1148/radiol.14132665. Epub 2014 Aug 7. PMID: 25105246.`n"
    }

    return result
}

; -------------------------------------------------------------
; 11) Hepatic Steatosis
; -------------------------------------------------------------
CalculateHepaticSteatosis(inputText) {
    global ShowCitations
    RegExNeedleLocal := "i)liver.*?((?:in[- ]?phase|IP|T1IP)).*?(\d+).*?((?:out[- ]?of[- ]?phase|OP|OOP|T1OP)).*?(\d+)"
    RegExNeedleSpleenLocal := "i)spleen.*?((?:in[- ]?phase|IP|T1IP)).*?(\d+).*?((?:out[- ]?of[- ]?phase|OP|OOP|T1OP)).*?(\d+)"
    
    if (RegExMatch(inputText, RegExNeedleLocal, matchLocal)) {
        liverInPhaseLocal := matchLocal2
        liverOutOfPhaseLocal := matchLocal4
        
        ; Calculate Fat fraction
        fatFractionLocal := 100 * (liverInPhaseLocal - liverOutOfPhaseLocal) / (2 * liverInPhaseLocal)
        
        resultLocal := inputText . " (Fat Fraction: " . Round(fatFractionLocal, 1) . "%)"
        resultLocal .= "`n`nFat Fraction " . InterpretHepaticSteatosis(fatFractionLocal) . "`n"
        
        ; Check if spleen values are provided
        if (RegExMatch(inputText, RegExNeedleSpleenLocal, matchSpleenLocal)) {
            spleenInPhaseLocal := matchSpleenLocal2
            spleenOutOfPhaseLocal := matchSpleenLocal4
            
            ; Calculate Fat percentage
            fatPercentageLocal := 100 * ((liverInPhaseLocal / spleenInPhaseLocal) - (liverOutOfPhaseLocal / spleenOutOfPhaseLocal)) / (2 * (liverInPhaseLocal / spleenInPhaseLocal))
            
            resultLocal := StrReplace(resultLocal, ")", ", Fat Percentage: " . Round(fatPercentageLocal, 1) . "%)")
            resultLocal .= "Fat Percentage " . InterpretHepaticSteatosis(fatPercentageLocal) . "`n"
        }
        
        if (ShowCitations = 1) {
            resultLocal .= "`n`nSirlin CB. Invited Commentary on Image-based quantification of hepatic fat: methods and clinical applications. Radiographics 2009; 29:1277-80`n"
        }
        
        return resultLocal
    } else {
        return "Invalid input format for hepatic steatosis calculation.`nSample syntax: Liver IP: 100, OP: 80, Spleen IP: 90, OP: 88"
    }
}

InterpretHepaticSteatosis(hepaticFatFraction) {
    if (hepaticFatFraction < 5) {
        return "Interpretation: No significant hepatic steatosis."
    } else if (hepaticFatFraction < 15) {
        return "Interpretation: Mild hepatic steatosis."
    } else if (hepaticFatFraction < 30) {
        return "Interpretation: Moderate hepatic steatosis."
    } else {
        return "Interpretation: Severe hepatic steatosis."
    }
}
; -------------------------------------------------------------
; 12) MRI Liver Iron Content
; -------------------------------------------------------------
EstimateIronContent(input) {
	global ShowCitations

    RegExMatch(input, "i)(?:\b|^)(1[.,]5|3[.,]0|1\.5|3\.0|2\.89)(?:\s*-?\s*)?T(?:esla)?", fieldStrength)
    if (!fieldStrength1) {
        return "Error: Magnetic field strength (1.5T, 2.89T or 3.0T) not found in the input."
    }
    fieldStrength1 := StrReplace(fieldStrength1, ",", ".")

    R2StarPattern := "i)R2\*?\s*(?:value|reading|measurement)?(?:[\s:=]+of)?\s*[:=]?\s*(\d+(?:[.,]\d+)?)\s*(?:Hz|hertz|s(?:ec(?:ond)?)?Ã¢ÂÂ»Ã‚Â¹|1/s)"
    RegExMatch(input, R2StarPattern, R2Star)
    if (!R2Star1) {
        return "Error: R2* value not found in the input.`nSample syntax: 1.5T, R2*: 50 Hz"
    }
    R2StarValue := StrReplace(R2Star1, ",", ".")
    R2StarValue += 0

    if (fieldStrength1 == "1.5") {
		ironContent :=  0.02603 * R2StarValue - 0.16
    } else if (fieldStrength1 == "2.89") {
	    ironContent := 0.01400 * R2StarValue - 0.03
	} else if (fieldStrength1 == "3.0") {
        ironContent := 0.01349 * R2StarValue - 0.03
    } else { 
	    ironContent := 0
	}

    result := input . "`nEstimated Iron Content: " . Round(ironContent, 1) . " mg Fe/g dry liver`n"
	
	if (ShowCitations=1){
		result .= "`nGuglielmo FF, Barr RG, Yokoo T, Ferraioli G, Lee JT, Dillman JR, Horowitz JM, Jhaveri KS, Miller FH, Modi RY, Mojtahed A, Ohliger MA, Pirasteh A, Reeder SB, Shanbhogue K, Silva AC, Smith EN, Surabhi VR, Taouli B, Welle CL, Yeh BM, Venkatesh SK. Liver Fibrosis, Fat, and Iron Evaluation with MRI and Fibrosis and Fat Evaluation with US: A Practical Guide for Radiologists. Radiographics. 2023 Jun;43(6):e220181. doi: 10.1148/rg.220181. PMID: 37227944.`n"
	}
    return result
}

; -------------------------------------------------------------
; 13) Calcium Score Percentile (no OCR)
; -------------------------------------------------------------
CalculateCalciumScorePercentile(input) {
    ; Extract age, sex, race, and calcium score from input
    RegExMatch(input, "i)Age:\s*(\d+)", age)
    RegExMatch(input, "i)Sex:\s*(Male|Female)", sex)
    RegExMatch(input, "i)Race:\s*(White|Black|Hispanic|Chinese|[A-Za-z]+)", race)
    RegExMatch(input, "i)(?:your\s+)?(?:coronary\s+artery\s+)?calcium\s+score(?:\s+is)?:?\s*(\d+(?:\.\d+)?)\s*(?:\(?\s*Agatston\s*\)?)?|(?:total\s+)?calcium\s+score:?\s*(\d+(?:\.\d+)?)", score)
	
	if (!age1) {
        return input . "`n`nError: Age not found or invalid. Please provide age in the format 'Age: 55'."
    }
    if (!sex1) {
        return input . "`n`nError: Sex not found or invalid. Please specify either Male or Female."
    }
    if (!score1 && score1 !=0 ) {
        return input . "`n`nError: Calcium score not found or invalid. Please ensure the score is provided in the format 'YOUR CORONARY ARTERY CALCIUM SCORE: 0.0 (Agatston)'."
    }

    age := age1
    sex := sex1
    race := race1 ? race1 : "Unspecified"
    score := score1

    result := ""
    if (age >= 45 && age <= 84 && (race = "White" || race = "Black" || race = "Hispanic" || race = "Chinese")) {
        result := CalculateMESAScore(age, race, sex, score)
    } else if (age >= 30) {
        result := CalculateHoffScore(age, sex, score, race)
    } else {
        result := "Error: The calcium score calculators are only valid for ages 30 and above."
    }

    return input . "`n`nCONTEXT:`n" . result
}

CalculateMESAScore(age, race, sex, score) {
	global ShowCitations
	global ShowArterialAge

    url := "https://www.mesa-nhlbi.org/Calcium/input.aspx"
    
    ; First, we need to get the initial page to retrieve some hidden values
    initialResponse := DownloadToString(url)
    if (InStr(initialResponse, "Error:")) {
        return "Initial page load failed: " . initialResponse
    }
    
    ; Extract necessary hidden values
    RegExMatch(initialResponse, "id=""__VIEWSTATE"" value=""([^""]+)""", viewState)
    RegExMatch(initialResponse, "id=""__VIEWSTATEGENERATOR"" value=""([^""]+)""", viewStateGenerator)
    RegExMatch(initialResponse, "id=""__EVENTVALIDATION"" value=""([^""]+)""", eventValidation)
    
    ; Prepare the post data
    postData := "__VIEWSTATE=" . UrlEncode(viewState1)
              . "&__VIEWSTATEGENERATOR=" . viewStateGenerator1
              . "&__EVENTVALIDATION=" . UrlEncode(eventValidation1)
              . "&Age=" . age
              . "&gender=" . GetSexValue(sex)
              . "&Race=" . GetRaceValue(race)
              . "&Score=" . score
              . "&Calculate=Calculate"

    ; Send the calculation request
    response := DownloadToString(url, postData)
    if (InStr(response, "Error:")) {
        return "Calculation request failed: " . response
    }
    
    ; Extract the results
    RegExMatch(response, "id=""Label10""[^>]*>([^<]+)</span>", probability)
    RegExMatch(response, "id=""scoreLabel""[^>]*>([^<]+)</span>", observedScore)
    RegExMatch(response, "id=""percLabel""[^>]*>([^<]+)</span>", percentile)
    
    if (probability1 || observedScore1 || percentile1) {
        result := "Probability of non-zero calcium score: " . probability1 . "`n`n"
        
        result .= "Plaque Burden: " . DeterminePlaqueBurden(score) . "`n`n"
        
        percentileNum := percentile1 + 0
        comparison := DetermineComparison(percentileNum)
        
        result .= "Comparison to people of the same age, race and sex: " . comparison . "`n`n"
        result .= "Observed calcium score of " . score . " Agatston is at percentile " . percentile1 . " for age, race and sex`n`n"
        
        if(ShowArterialAge=1){
			result .= "Arterial Age: " . CalculateCoronaryAge(score) . " years" . "`n`n"
        }
		if(ShowCitations=1) {
			result .= "Citation 1: McClelland RL, et al. Distribution of coronary artery calcium by race, gender, and age: results from the Multi-Ethnic Study of Atherosclerosis (MESA). Circulation. 2006 Jan 3;113(1):30-7.`n`n"
			result .= "Citation 2: McClelland RL, Nasir K, Budoff M, Blumenthal RS, Kronmal RA. Arterial age as a function of coronary artery calcium (from the Multi-Ethnic Study of Atherosclerosis [MESA]). Am J Cardiol. 2009 Jan 1;103(1):59-63."
        }
		
		return result
		
	} else {
		; Save the response for debugging
		FileAppend, %response%, %A_Desktop%\mesa_debug_response.html
		return "Error: Unable to retrieve result from MESA calculator. The response has been saved to your desktop as 'mesa_debug_response.html' for further investigation."
	}
}

CalculateHoffScore(age, sex, score, race) {
	global ShowCitations
	global ShowArterialAge

    ageGroup := GetAgeGroup(age)
    percentile := GetHoffPercentile(ageGroup, sex, score)
    
    result := "Plaque Burden: " . DeterminePlaqueBurden(score) . "`n`n"
    
    comparison := DetermineComparison(percentile)
    result .= "Comparison to people of the same age and sex: " . comparison . "`n`n"
    
    if(ShowArterialAge=1){
		result .= "Arterial Age: " . CalculateCoronaryAge(score) . " years" . "`n`n"
    }
    if(ShowCitations=1){
		result .= "Citation 1: Hoff JA, et al. Age and gender distributions of coronary artery calcium detected by electron beam tomography in 35,246 adults. Am J Cardiol. 2001 Jun 15;87(12):1335-9.`n`n"
		result .= "Citation 2: McClelland RL, Nasir K, Budoff M, Blumenthal RS, Kronmal RA. Arterial age as a function of coronary artery calcium (from the Multi-Ethnic Study of Atherosclerosis [MESA]). Am J Cardiol. 2009 Jan 1;103(1):59-63."
    }
	
    return result
}

GetAgeGroup(age) {
    if (age < 40)
        return "<40"
    else if (age < 45)
        return "40-44"
    else if (age < 50)
        return "45-49"
    else if (age < 55)
        return "50-54"
    else if (age < 60)
        return "55-59"
    else if (age < 65)
        return "60-64"
    else if (age < 70)
        return "65-69"
    else if (age <= 74)
        return "70-74"
    else
        return ">74"
}

GetHoffPercentile(ageGroup, sex, score) {
    percentiles := {"<40": {}, "40-44": {}, "45-49": {}, "50-54": {}, "55-59": {}, "60-64": {}, "65-69": {}, "70-74": {}, ">74": {}}
    
    ; Male percentiles
    percentiles["<40"]["Male"] := [0, 1, 3, 14]
    percentiles["40-44"]["Male"] := [0, 1, 9, 59]
    percentiles["45-49"]["Male"] := [0, 3, 36, 154]
    percentiles["50-54"]["Male"] := [1, 15, 103, 332]
    percentiles["55-59"]["Male"] := [4, 48, 215, 554]
    percentiles["60-64"]["Male"] := [13, 113, 410, 994]
    percentiles["65-69"]["Male"] := [32, 180, 566, 1299]
    percentiles["70-74"]["Male"] := [64, 310, 892, 1774]
    percentiles[">74"]["Male"] := [166, 473, 1071, 1982]
    
    ; Female percentiles
    percentiles["<40"]["Female"] := [0, 0, 1, 3]
    percentiles["40-44"]["Female"] := [0, 0, 1, 4]
    percentiles["45-49"]["Female"] := [0, 0, 2, 22]
    percentiles["50-54"]["Female"] := [0, 0, 5, 55]
    percentiles["55-59"]["Female"] := [0, 1, 23, 121]
    percentiles["60-64"]["Female"] := [0, 3, 57, 193]
    percentiles["65-69"]["Female"] := [1, 24, 145, 410]
    percentiles["70-74"]["Female"] := [3, 52, 210, 631]
    percentiles[">74"]["Female"] := [9, 75, 241, 709]
    
    agePercentiles := percentiles[ageGroup][sex]
    
    if (score <= agePercentiles[1])
        return 25
    else if (score <= agePercentiles[2])
        return 50
    else if (score <= agePercentiles[3])
        return 75
    else if (score <= agePercentiles[4])
        return 90
    else
        return 99
}

DeterminePlaqueBurden(score) {
    if (score = 0)
        return "None. Risk of coronary artery disease is very low, generally less than 5 percent."
    else if (score > 0 && score <= 10)
        return "Minimal identifiable plaque. Risk of coronary artery disease is very unlikely, less than 10 percent."
    else if (score > 10 && score <= 100)
        return "At least mild atherosclerotic plaque. Mild or minimal coronary narrowings likely."
    else if (score > 100 && score <= 400)
        return "At least moderate atherosclerotic plaque. Mild coronary artery disease highly likely, significant narrowings possible."
    else
        return "Extensive atherosclerotic plaque. High likelihood of at least one significant coronary narrowing."
}

DetermineComparison(percentile) {
    if (percentile<=25)
        return "Low (≤25%)"
    else if (percentile<=50)
        return "Average (25-50%)"
    else if (percentile<=75)
        return "Average (50-75%)"
    else if (percentile<=90)
        return "High (75-90%)"
    else
        return "Very high (>90%)"
}

CalculateCoronaryAge(score) {
    logScore := Ln(score+1)
    effectiveAge := Round(39.1 + 7.25*logScore, 0)
    return effectiveAge
}

; -------------------------------------------------------------
; 14) CalculateNASCET
; -------------------------------------------------------------
CalculateNASCET(input) {
    global ShowCitations
    raw := input
    input := RegExReplace(input, "`r?\n", " ")

    RegExNeedle := "i)(?:distal.*?(\d+(?:\.\d+)?)(?:mm|cm)).*?(?:stenosis.*?(\d+(?:\.\d+)?)(?:mm|cm))"
    if (!RegExMatch(input, RegExNeedle, match)) {
        RegExNeedle2 := "i)(?:stenosis.*?(\d+(?:\.\d+)?)(?:mm|cm)).*?(?:distal.*?(\d+(?:\.\d+)?)(?:mm|cm))"
        if (!RegExMatch(input, RegExNeedle2, match2)) {
            numbers := []
            patternAny := "(\d+(?:\.\d+)?)(?:mm|cm)?"
            pos := 1
            while (pos := RegExMatch(input, patternAny, m, pos)) {
                numbers.Push(m1+0)
                pos += StrLen(m)
            }
            if (numbers.Length()<2)
                return "Could not find two diameters for NASCET. Example: 'Distal ICA = 6 mm, Stenosis = 2 mm'"
            distal := Max(numbers*)
            stenosis := Min(numbers*)
        } else {
            stenosis := match21+0
            distal := match22+0
        }
    } else {
        distal := match1+0
        stenosis := match2+0
    }

    nascetVal := (distal - stenosis)/distal*100
    nascetVal := Round(nascetVal,1)

    result := raw . "`n`nNASCET Calculation:`nDistal: " . distal . " mm`nStenosis: " . stenosis . " mm`nNASCET: " . nascetVal . "%"

    if (nascetVal<50)
        result .= "`nMild (<50%)"
    else if (nascetVal<70)
        result .= "`nModerate (50-69%)"
    else
        result .= "`nSevere (≥70%)"

    if (ShowCitations=1) {
        result .= "`nCitation: NASCET (N Engl J Med 1991;325:445-53)."
    }
    return result
}

; -------------------------------------------------------------
; NASCET GUI - Direct input GUI for easier measurement entry
; WHY: Original text parsing requires specific format; GUI allows direct entry.
; ARCHITECTURE: Mirrors ContrastPremedication GUI pattern for consistency.
; -------------------------------------------------------------
ShowNASCETGui() {
    global ShowCitations

    ; Get current mouse position for GUI placement
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY

    ; Determine which monitor the mouse is on
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom)
        {
            activeMonitor := A_Index
            break
        }
    }

    ; Get dimensions of the active monitor
    SysGet, workArea, MonitorWorkArea, %activeMonitor%

    ; Calculate GUI dimensions and position
    guiWidth := 320
    guiHeight := 200
    xPos := mouseX + 10
    yPos := mouseY + 10

    ; Ensure the GUI doesn't go off-screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight

    ; Create GUI
    Gui, NASCETCalc:New, +AlwaysOnTop
    Gui, NASCETCalc:Add, Text, x10 y10 w300, NASCET Carotid Stenosis Calculator
    Gui, NASCETCalc:Add, Text, x10 y35 w300, (North American Symptomatic Carotid Endarterectomy Trial)
    Gui, NASCETCalc:Add, Text, x10 y65, Distal ICA diameter (normal segment):
    Gui, NASCETCalc:Add, Edit, x10 y85 w80 vNASCETDistal
    Gui, NASCETCalc:Add, Text, x95 y88, mm
    Gui, NASCETCalc:Add, Text, x10 y115, Stenosis diameter (narrowest point):
    Gui, NASCETCalc:Add, Edit, x10 y135 w80 vNASCETStenosis
    Gui, NASCETCalc:Add, Text, x95 y138, mm
    Gui, NASCETCalc:Add, Button, x10 y170 w100 gCalculateNASCETFromGui, Calculate
    Gui, NASCETCalc:Add, Button, x120 y170 w80 gNASCETGuiClose, Cancel
    Gui, NASCETCalc:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, NASCET Calculator

    return
}

NASCETGuiClose:
    Gui, NASCETCalc:Destroy
return

CalculateNASCETFromGui:
    Gui, NASCETCalc:Submit, NoHide
    global ShowCitations

    ; Validate inputs
    if (NASCETDistal = "" || NASCETStenosis = "") {
        MsgBox, 0, Error, Please enter both distal ICA and stenosis diameters.
        return
    }

    distal := NASCETDistal + 0
    stenosis := NASCETStenosis + 0

    if (distal <= 0) {
        MsgBox, 0, Error, Distal ICA diameter must be greater than 0.
        return
    }

    if (stenosis < 0) {
        MsgBox, 0, Error, Stenosis diameter cannot be negative.
        return
    }

    if (stenosis >= distal) {
        MsgBox, 0, Error, Stenosis diameter should be less than distal ICA diameter.
        return
    }

    ; Calculate NASCET
    nascetVal := (distal - stenosis) / distal * 100
    nascetVal := Round(nascetVal, 1)

    ; Build result string
    result := "NASCET Calculation:`n"
    result .= "Distal ICA: " . distal . " mm`n"
    result .= "Stenosis: " . stenosis . " mm`n"
    result .= "NASCET: " . nascetVal . "%`n`n"

    ; Clinical interpretation
    if (nascetVal < 50) {
        result .= "Interpretation: Mild stenosis (<50%)`n"
        result .= "- Medical management typically recommended."
    } else if (nascetVal < 70) {
        result .= "Interpretation: Moderate stenosis (50-69%)`n"
        result .= "- Consider intervention in symptomatic patients."
    } else {
        result .= "Interpretation: Severe stenosis (≥70%)`n"
        result .= "- Strong indication for CEA/CAS in symptomatic patients."
    }

    if (ShowCitations = 1) {
        result .= "`n`nCitation: NASCET (N Engl J Med 1991;325:445-53)."
    }

    ; Close GUI and show result
    Gui, NASCETCalc:Destroy
    ShowResult(result)
return

; -------------------------------------------------------------
; 15) CalculateRVLV - RV/LV Ratio Calculator for CTPA/PE
; WHY: RV/LV ratio is a key prognostic marker for pulmonary embolism severity.
;      Ratio >= 1.0 is elevated (RV dilatation); 0.9-0.99 borderline.
; ARCHITECTURE: GUI-based input for direct measurement entry with clinical interpretation.
; -------------------------------------------------------------
CalculateRVLV() {
    global ShowCitations

    ; Get current mouse position for GUI placement
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY

    ; Determine which monitor the mouse is on
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom)
        {
            activeMonitor := A_Index
            break
        }
    }

    ; Get dimensions of the active monitor
    SysGet, workArea, MonitorWorkArea, %activeMonitor%

    ; Calculate GUI dimensions and position
    guiWidth := 300
    guiHeight := 200
    xPos := mouseX + 10
    yPos := mouseY + 10

    ; Ensure the GUI doesn't go off-screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight

    ; Create GUI
    Gui, RVLVCalc:New, +AlwaysOnTop
    Gui, RVLVCalc:Add, Text, x10 y10 w280, RV/LV Ratio Calculator (4-chamber axial)
    Gui, RVLVCalc:Add, Text, x10 y35, Right Ventricle (RV) diameter:
    Gui, RVLVCalc:Add, Edit, x10 y55 w80 vRVDiameter
    Gui, RVLVCalc:Add, Text, x95 y58, mm
    Gui, RVLVCalc:Add, Text, x10 y85, Left Ventricle (LV) diameter:
    Gui, RVLVCalc:Add, Edit, x10 y105 w80 vLVDiameter
    Gui, RVLVCalc:Add, Text, x95 y108, mm
    Gui, RVLVCalc:Add, Button, x10 y140 w100 gCalculateRVLVRatio, Calculate
    Gui, RVLVCalc:Add, Button, x120 y140 w80 gRVLVGuiClose, Cancel
    Gui, RVLVCalc:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, RV/LV Ratio

    return
}

RVLVGuiClose:
    Gui, RVLVCalc:Destroy
return

CalculateRVLVRatio:
    Gui, RVLVCalc:Submit, NoHide
    global ShowCitations

    ; Validate inputs
    if (RVDiameter = "" || LVDiameter = "") {
        MsgBox, 0, Error, Please enter both RV and LV diameters.
        return
    }

    rv := RVDiameter + 0
    lv := LVDiameter + 0

    if (lv <= 0) {
        MsgBox, 0, Error, LV diameter must be greater than 0.
        return
    }

    ; Calculate ratio
    ratio := rv / lv
    ratio := Round(ratio, 2)

    ; Build result string
    result := "RV/LV Ratio Calculation:`n"
    result .= "RV diameter: " . rv . " mm`n"
    result .= "LV diameter: " . lv . " mm`n"
    result .= "RV/LV Ratio: " . ratio . "`n`n"

    ; Clinical interpretation based on user-provided thresholds
    ; WHY: No validated mild/moderate/severe grading exists for the CT RV/LV ratio;
    ;      state only what the number shows (no "severe" / strain diagnosis).
    if (ratio >= 1.0) {
        result .= "Interpretation: Elevated (1.0 or greater), compatible with right ventricular dilatation.`n"
        result .= "- Correlate clinically and with echocardiography for right heart strain."
    } else if (ratio >= 0.9) {
        result .= "Interpretation: Borderline (0.9-0.99)."
    } else {
        result .= "Interpretation: Normal (less than 0.9)."
    }

    if (ShowCitations = 1) {
        result .= "`n`nReferences:`n"
        result .= "- Meinel et al. Radiology 2015;275:583-591`n"
        result .= "- Defined on axial images at level of maximum chamber diameter"
    }

    ; Close GUI and show result
    Gui, RVLVCalc:Destroy
    ShowResult(result)
return

; ------------------------------------------
; Utility Subfunctions
; ------------------------------------------
; -------------------------------------------------------------
; GoogleAutoCorrect: Checks spelling via Google search
; -------------------------------------------------------------
GoogleAutoCorrect(Word) {
    ; Sanitize and encode the word before sending to Google
    Word := Trim(Word)
    
    ; Use the Google search "Did you mean" feature
    try {
        OutputVar := URLDownloadToVarWithHeader("https://www.google.com/search?q=" Word)
        
        pos := InStr(OutputVar, "spell=1")
        if (pos) {
            cut := SubStr(OutputVar, 1, pos-1)
            equalSign := InStr(cut, "=",, 0)
            
            if (equalSign) {
                equalSignString := SubStr(cut, equalSign+1)
                
                lengthOfOptional := 0
                if (SubStr(equalSignString, -4) = "&amp;") {
                    lengthOfOptional := 5
                }
                
                autocorrected := SubStr(equalSignString, 1, StrLen(equalSignString) - lengthOfOptional)
                return StrReplace(autocorrected, "+" , " ")
            }
        }
    } catch {}
    
    ; If no suggestion found, return empty string to indicate no correction
    return ""
}

URLDownloadToVarWithHeader(url){
    hObject:=ComObjCreate("WinHttp.WinHttpRequest.5.1")
    hObject.Open("GET",url)
    hObject.SetRequestHeader("User-Agent", "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)")

    hObject.Send()
    return hObject.ResponseText
}

; ==

SortDimensions(dimensions) {
    if (dimensions[1] < dimensions[2]) {
        temp := dimensions[1], dimensions[1] := dimensions[2], dimensions[2] := temp
    }
    if (dimensions[2] < dimensions[3]) {
        temp := dimensions[2], dimensions[2] := dimensions[3], dimensions[3] := temp
    }
    if (dimensions[1] < dimensions[2]) {
        temp := dimensions[1], dimensions[1] := dimensions[2], dimensions[2] := temp
    }
    return dimensions
}

ParseDate(dateStr) {
    dateStr := StrReplace(dateStr, ".", "/")
    dateStr := StrReplace(dateStr, "-", "/")
    if (RegExMatch(dateStr, "(\d{1,2})/(\d{1,2})/(\d{2,4})", match)) {
        month := match1
        day := match2
        year := match3
        if (StrLen(year) == 2)
            year := "20" . year
        if (month > 12) {
            temp := month
            month := day
            day := temp
        }
        if (day > 31 || month > 12)
            return "Invalid Date"
        month := SubStr("0" . month, -1)
        day := SubStr("0" . day, -1)
        return year . month . day
    }
    return "Invalid Date"
}

CalculateDatesFromLMP(LMPDate) {
    FormatTime, LMPFormatted, %LMPDate%, MM/dd/yyyy
    EDDDate := DateCalc(LMPDate, 280)
    FormatTime, EDDFormatted, %EDDDate%, MM/dd/yyyy
    GA := DateCalc(A_Now, 0)
    GA -= LMPDate, days
    GAWeeks := Floor(GA / 7)
    GADays := Mod(GA, 7)
    return % "LMP: " . LMPFormatted . "`n"
        . "Estimated Delivery Date: " . EDDFormatted . "`n"
        . "Current Gestational Age: " . GAWeeks . " weeks " . GADays . " days"
}

CalculateDatesFromGA(WeeksGA, DaysGA, ReferenceDate) {
    FetusAgeDays := (WeeksGA * 7) + DaysGA
    LMPDate := DateCalc(ReferenceDate, -FetusAgeDays)
    FormatTime, LMPFormatted, %LMPDate%, MM/dd/yyyy
    EDDDate := DateCalc(LMPDate, 280)
    FormatTime, EDDFormatted, %EDDDate%, MM/dd/yyyy
    CurrentGA := DateCalc(A_Now, 0)
    CurrentGA -= LMPDate, days
    CurrentGAWeeks := Floor(CurrentGA / 7)
    CurrentGADays := Mod(CurrentGA, 7)
    FormatTime, ReferenceDateFormatted, %ReferenceDate%, MM/dd/yyyy
    return % "LMP: " . LMPFormatted . "`n"
        . "Estimated Delivery Date: " . EDDFormatted . "`n"
        . "Gestational Age as of " . ReferenceDateFormatted . ": " . WeeksGA . " weeks " . DaysGA . " days`n"
        . "Current Gestational Age: " . CurrentGAWeeks . " weeks " . CurrentGADays . " days"
}

DetermineMenstrualPhase(LMPDate) {
    DaysSinceLMP := A_Now
    DaysSinceLMP -= LMPDate, days
    CycleDay := Mod(DaysSinceLMP, 28) + 1
    FormatTime, LMPFormatted, %LMPDate%, MM/dd/yyyy
    Result := "LMP: " . LMPFormatted . "`n"
    Result .= "Current Cycle Day: " . CycleDay . "/28`n`n"
    if (CycleDay >= 1 && CycleDay <= 5) {
        Result .= "Menstrual Phase`nExpected endometrial stripe thickness: 1-4 mm"
    } else if (CycleDay >= 6 && CycleDay <= 13) {
        Result .= "Early Proliferative Phase`nExpected endometrial stripe thickness: 5-7 mm"
    } else if (CycleDay == 14) {
        Result .= "Ovulation`nExpected endometrial appearance: Trilaminar, approximately 11 mm"
    } else if (CycleDay >= 15 && CycleDay <= 28) {
        Result .= "Secretory Phase`nExpected endometrial stripe thickness: 7-16 mm"
    } else {
        Result .= "Error: Invalid cycle day calculated"
    }
    return Result
}

DateCalc(date, days) {
    date += %days%, days
    FormatTime, out, %date%, yyyyMMdd
    return out
}

; -------------------------------------------------------------
; CompareMeasurements: single function to compare old vs new
; -------------------------------------------------------------
CompareMeasurements(previous, current, previousDate, currentDate, input) {
    ; Process measurements
    prev := ProcessMeasurement(previous)
    curr := ProcessMeasurement(current)
    
    ; Check for dimension mismatch
    if (prev.dimensions.MaxIndex() != curr.dimensions.MaxIndex()) {
        return "Error: Mismatch in number of dimensions between previous and current measurements.`nPrevious: " . previous . "`nCurrent: " . current
    }

    ; Initialize result string
    result := input . "`n`n"
    result .= "Previous Date: " . (previousDate ? previousDate : "Not provided") . "`n"
    result .= "Current Date: " . (currentDate ? currentDate : "Assumed as today") . "`n`n"

    ; Process dimensions
    prevLongestDim := 0
    currLongestDim := 0
    
    Loop, % prev.dimensions.MaxIndex()
    {
        prevDim := prev.dimensions[A_Index]
        currDim := curr.dimensions[A_Index]
        
        ; Convert to cm if necessary
        prevDimCm := (prev.unit == "mm") ? prevDim / 10 : prevDim
        currDimCm := (curr.unit == "mm") ? currDim / 10 : currDim
        
        ; Track longest dimension
        prevLongestDim := (prevDimCm > prevLongestDim) ? prevDimCm : prevLongestDim
        currLongestDim := (currDimCm > currLongestDim) ? currDimCm : currLongestDim
        
        ; Calculate change
        change := (currDimCm / prevDimCm - 1) * 100
        
        ; Append to result
        result .= "Dimension " . A_Index . ": " 
                . Round(prevDim, 2) . " " . prev.unit 
                . " -> " 
                . Round(currDim, 2) . " " . curr.unit 
                . " (" . (change >= 0 ? "+" : "") . Round(change, 1) . "%)`n"
    }
    
    ; Calculate longest dimension change
    longestDimChange := (currLongestDim / prevLongestDim - 1) * 100
    result .= "`nLongest dimension change: " . (longestDimChange >= 0 ? "+" : "") . Round(longestDimChange, 1) . "%`n"
    
    ; Calculate volumes
    prevVolumeNum := CalculateVolume(prev.dimensions, prev.unit)
    currVolumeNum := CalculateVolume(curr.dimensions, curr.unit)
    
    ; Process volume calculations if valid
    if (prevVolumeNum != "Invalid input" and currVolumeNum != "Invalid input") {
        volumeChange := (currVolumeNum / prevVolumeNum - 1) * 100
        result .= "Volume change: " . (volumeChange >= 0 ? "+" : "") . Round(volumeChange, 1) . "%`n"
        result .= "Previous volume: " . FormatVolume(prevVolumeNum) . "`n"
        result .= "Current volume: " . FormatVolume(currVolumeNum) . "`n"
        
        ; Process dates and calculate time-based metrics
        if (previousDate) {
            parsedPreviousDate := ParseDate(previousDate)
            if (parsedPreviousDate == "Invalid Date") {
                return result . "`nError: Invalid previous date format."
            }
            
            if (!currentDate) {
                FormatTime, currentDate, , MM/dd/yyyy
            }
            parsedCurrentDate := ParseDate(currentDate)
            if (parsedCurrentDate == "Invalid Date") {
                return result . "`nError: Invalid current date format."
            }
            
            ; Calculate time difference
            timeDiff := DateDiff(parsedPreviousDate, parsedCurrentDate) / 365.25
            result .= "Time difference: " . Round(timeDiff, 2) . " years`n"
            
            ; Calculate growth metrics if time difference is positive
            if (timeDiff > 0) {
                ; Calculate doubling time in days
                doublingTime := CalculateDoublingTime(prevVolumeNum, currVolumeNum, timeDiff)
                doublingTimeDays := doublingTime * 365.25
                result .= "Doubling time: " . (doublingTime != "N/A" ? Round(doublingTimeDays, 0) . " days" : doublingTime) . "`n"
                
                ; Calculate exponential growth rate in % per year
                growthRate := CalculateExponentialGrowth(prevVolumeNum, currVolumeNum, timeDiff)
                result .= "Exponential Growth Rate: " . Round(growthRate * 100, 2) . "% per year"
            } else {
                result .= "Note: Doubling time and Growth Rate not calculated due to invalid time difference."
            }
        } else {
            result .= "Note: Doubling time and Growth Rate not calculated due to missing previous date."
        }
    } else {
        result .= "Error: Unable to calculate volume for one or both measurements."
    }
    
    return result
}

ProcessMeasurement(input) {
    dimensions := []
    RegExMatch(input, "i)(\d+(?:\.\d+)?)(?:\s*(?:x|\*)\s*(\d+(?:\.\d+)?))?(?:\s*(?:x|\*)\s*(\d+(?:\.\d+)?))?(?=\s*(cm|mm)?)", match)
    dimensions.Push(match1 + 0)  ; Convert to number to preserve all decimal places
    if (match2 != "")
        dimensions.Push(match2 + 0)
    if (match3 != "")
        dimensions.Push(match3 + 0)
    unit := (match4 != "") ? match4 : ((InStr(match1, ".") > 0 || InStr(match2, ".") > 0 || InStr(match3, ".") > 0) ? "cm" : "mm")
    return {dimensions: dimensions, unit: unit}
}

CalculateVolume(dimensions, unit) {
    static PI := 3.14159265358979
    
    if (dimensions.MaxIndex() == 1)
        volume := (4/3) * PI * (dimensions[1] / 2) ** 3  ; Sphere
    else if (dimensions.MaxIndex() == 2)
        volume := (4/3) * PI * (dimensions[1] / 2) * (dimensions[2] / 2) * ((dimensions[1] + dimensions[2]) / 4)  ; Ellipsoid with 3rd dim as average
    else if (dimensions.MaxIndex() == 3)
        volume := CalculateEllipsoidVolumeNumeric(dimensions[1] . " x " . dimensions[2] . " x " . dimensions[3], unit)
    else
        return "Invalid input"
    
    return (unit == "mm") ? volume / 1000 : volume  ; Convert to cm³ if necessary
}

FormatVolume(volume) {
    return (volume < 1) ? Round(volume * 1000, 1) . " cu-mm" : Round(volume, 1) . " cc"
}

CalculateDoublingTime(initialVolume, finalVolume, time) {
    growthRate := (finalVolume / initialVolume) ** (1 / time) - 1
    return (growthRate > 0) ? (Ln(2) / Ln(1 + growthRate)) : "N/A"
}

CalculateExponentialGrowth(initialVolume, finalVolume, time) {
    growthRate := Ln(finalVolume/initialVolume) / time
    return growthRate  ; Return as a decimal, will be converted to percentage in the main function
}

DateDiff(date1, date2) {
    EnvSub, date2, %date1%, Days
    return date2
}

CalculateEllipsoidVolumeNumeric(input, unit) {
    RegExNeedle := "\s*(\d+(?:\.\d+)?)\s*[x,]\s*(\d+(?:\.\d+)?)\s*[x,]\s*(\d+(?:\.\d+)?)\s*"
    if (RegExMatch(input, RegExNeedle, match)) {
        dimensions := [match1 + 0, match2 + 0, match3 + 0]  ; Convert to numbers
        dimensions := SortDimensions(dimensions)

        volume := (1/6) * 3.14159265358979323846 * (dimensions[1]) * (dimensions[2]) * (dimensions[3])
        return volume
    } else {
        return "Invalid input format"
    }
}
JoinDimensions(dimensions) {
    return Round(dimensions[1], 1) . (dimensions.Length() > 1 ? " x " . Round(dimensions[2], 1) : "") . (dimensions.Length() > 2 ? " x " . Round(dimensions[3], 1) : "")
}
; -------------------------------------------------------------------------
; 15) Contrast Premedication
; -------------------------------------------------------------------------
CalculateContrastPremedication() {
    defaultDateTime := GetDefaultDateTime()
    FormatTime, defaultDate, %defaultDateTime%, yyyyMMdd
    FormatTime, defaultTime, %defaultDateTime%, HH:mm

    ; Get current mouse position (relative to the entire desktop)
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY

    ; Determine which monitor the mouse is on
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom)
        {
            activeMonitor := A_Index
            break
        }
    }

    ; Get dimensions of the active monitor
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop

    ; Calculate GUI dimensions and position
    guiWidth := 250
    guiHeight := 160
    xPos := mouseX + 10
    yPos := mouseY + 10

    ; Ensure the GUI doesn't go off-screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight

    ; Create GUI with AlwaysOnTop option and position it near the mouse
    Gui, ContrastPremed:New, +AlwaysOnTop
    Gui, ContrastPremed:Add, Text, x10 y10, Scan Date:
    Gui, ContrastPremed:Add, DateTime, x10 y30 w120 vScanDate Choose%defaultDate%
    Gui, ContrastPremed:Add, Text, x140 y10, Scan Time:
    Gui, ContrastPremed:Add, DropDownList, x140 y30 w100 vScanTime, % CreateTimeList(defaultTime)
    Gui, ContrastPremed:Add, Radio, x10 y60 w200 vPremedProtocol Checked, Prednisone (13-7-1 hour)
    Gui, ContrastPremed:Add, Radio, x10 y80 w200, Methylprednisolone (12-2 hour)
    Gui, ContrastPremed:Add, Checkbox, x10 y100 w200 vIncludeDiphenhydramine Checked, Include Diphenhydramine
    Gui, ContrastPremed:Add, Button, x10 y130 w100 gCalculatePremedTiming, Calculate
    Gui, ContrastPremed:Add, Button, x120 y130 w100 gShowPremedDosages, Show Dosages
    Gui, ContrastPremed:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Contrast Premedication

    return
}

GetDefaultDateTime() {
    defaultDateTime := A_Now
    EnvAdd, defaultDateTime, 13, Hours
    
    ; Extract hours and minutes
    FormatTime, hours, %defaultDateTime%, HH
    FormatTime, minutes, %defaultDateTime%, mm
    
    ; Round up to nearest 5 minutes
    minutes := Ceil(minutes / 5) * 5
    if (minutes = 60) {
        minutes := 0
        hours := hours + 1
    }
    
    ; Handle day change if hours exceed 23
    if (hours >= 24) {
        hours := Mod(hours, 24)
        EnvAdd, defaultDateTime, 1, Days
    }
    
    ; Format the time back into the datetime
    formattedTime := Format("{:02d}{:02d}00", hours, minutes)
    FormatTime, formattedDate, %defaultDateTime%, yyyyMMdd
    return formattedDate . formattedTime
}

CreateTimeList(defaultTime) {
    timeList := ""
    Loop, 24 {
        hour := A_Index - 1
        Loop, 12 {
            minute := (A_Index - 1) * 5
            time := Format("{:02d}:{:02d}", hour, minute)
            timeList .= time . "|"
        }
    }
    ; Remove the trailing pipe
    timeList := RTrim(timeList, "|")
    
    ; Set the default time
    if (defaultTime) {
        timeList := StrReplace(timeList, defaultTime, defaultTime . "||")
    }
    
    return timeList
}

GetScanDateTime(scanDate, scanTime) {
    if (scanDate = "" || scanTime = "") {
        return GetDefaultDateTime()
    }
    return CombineDateTime(scanDate, scanTime)
}

CalculatePremedTiming:
    Gui, ContrastPremed:Submit, NoHide
    scanDateTime := GetScanDateTime(ScanDate, ScanTime)
    if (!scanDateTime) {
        MsgBox, 0, Error, Please enter a valid date and time.
        return
    }
    CalculateAndShowPremedResult(scanDateTime, PremedProtocol, IncludeDiphenhydramine)
return

CombineDateTime(scanDate, scanTime) {
    FormatTime, formattedDate, %scanDate%, yyyyMMdd
    formattedTime := StrReplace(scanTime, ":")
    fullDateTime := formattedDate . formattedTime . "00"
    
    if (!IsValidDateTime(fullDateTime)) {
        return false
    }
    
    return fullDateTime
}

CalculateAndShowPremedResult(scanDateTime, premedProtocol, includeDiphenhydramine) {
    FormatTime, scanDateTimeFormatted, %scanDateTime%, MM/dd/yyyy hh:mm tt
    
    result := "Scan time: " . scanDateTimeFormatted . " Contrast Premedication Schedule:`n`n"
    
    if (premedProtocol = 1) {
        ; Prednisone-based protocol
        result .= FormatPremedTime(scanDateTime, -13, "13", premedProtocol, includeDiphenhydramine)
        result .= FormatPremedTime(scanDateTime, -7, "7", premedProtocol, includeDiphenhydramine)
        result .= FormatPremedTime(scanDateTime, -1, "1", premedProtocol, includeDiphenhydramine)
    } else {
        ; Methylprednisolone-based protocol
        result .= FormatPremedTime(scanDateTime, -12, "12", premedProtocol, includeDiphenhydramine)
        result .= FormatPremedTime(scanDateTime, -2, "2", premedProtocol, includeDiphenhydramine)
    }
    
    result .= "`nNote: Premedication regimens less than 4-5 hours in duration (oral or IV) have not been shown to be effective.`n"
    result .= "If a patient is unable to take oral medication, 200 mg hydrocortisone IV may be substituted for each dose of oral prednisone in the 13-7-1 premedication regimen.`n"
    
    if (ShowCitations) {
        result .= "`nCitation: ACR Manual on Contrast Media. 2023 American College of Radiology. https://www.acr.org/Clinical-Resources/Contrast-Manual`n"
    }
    
    ShowResult(result)
}

FormatPremedTime(scanTime, hoursOffset, label, protocol, includeDiphenhydramine) {
    premedTime := DateAdd(scanTime, hoursOffset, "hours")
    FormatTime, premedTimeFormatted, %premedTime%, MM/dd/yyyy hh:mm tt
    
    medication := GetMedicationInfo(label, protocol, includeDiphenhydramine)
    
    return label . " hours before (" . premedTimeFormatted . "):`n" . medication . "`n`n"
}

GetMedicationInfo(label, protocol, includeDiphenhydramine) {
    if (protocol = 1) {  ; Prednisone-based protocol
        medication := "- Prednisone 50 mg PO"
        if (label = "1" && includeDiphenhydramine) {
            medication .= "`n- Diphenhydramine 50 mg IV, IM, or PO"
        }
    } else {  ; Methylprednisolone-based protocol
        medication := "- Methylprednisolone 32 mg PO"
        if (label = "2" && includeDiphenhydramine) {
            medication .= "`n- Diphenhydramine 50 mg IV, IM, or PO"
        }
    }
    return medication
}

IsValidDateTime(dateTimeStr) {
    try {
        FormatTime, test, %dateTimeStr%, yyyy-MM-dd HH:mm:ss
        return true
    } catch {
        return false
    }
}

ShowPremedDosages:
    Gui, ContrastPremed:Submit, NoHide
    ShowPremedDosages(PremedProtocol, IncludeDiphenhydramine)
return

ShowPremedDosages(premedProtocol, includeDiphenhydramine) {
    dosages := "Contrast Premedication Dosages:`n`n"
    
    if (premedProtocol = 1) {
        dosages .= "Prednisone-based Protocol (13-7-1 hour):`n`n"
        dosages .= "13 hours before:`n- Prednisone 50 mg PO`n`n"
        dosages .= "7 hours before:`n- Prednisone 50 mg PO`n`n"
        dosages .= "1 hour before:`n- Prednisone 50 mg PO`n"
        if (includeDiphenhydramine) {
            dosages .= "- Diphenhydramine 50 mg IV, IM, or PO`n"
        }
    } else {
        dosages .= "Methylprednisolone-based Protocol (12-2 hour):`n`n"
        dosages .= "12 hours before:`n- Methylprednisolone 32 mg PO`n`n"
        dosages .= "2 hours before:`n- Methylprednisolone 32 mg PO`n"
        if (includeDiphenhydramine) {
            dosages .= "- Diphenhydramine 50 mg IV, IM, or PO`n"
        }
    }
    
    dosages .= "`nNotes:`n"
    dosages .= "- Premedication regimens less than 4-5 hours in duration (oral or IV) have not been shown to be effective.`n"
    dosages .= "- If a patient is unable to take oral medication, 200 mg hydrocortisone IV may be substituted for each dose of oral prednisone in the 13-7-1 premedication regimen.`n"
    dosages .= "- Diphenhydramine is considered optional. If a patient is allergic to diphenhydramine, an alternate anti-histamine without cross-reactivity may be considered, or the anti-histamine may be omitted.`n"
    dosages .= "- These dosages are based on the ACR Manual on Contrast Media. Please consult with a healthcare professional for patient-specific recommendations.`n"
    
    if (ShowCitations) {
        dosages .= "`nCitation: ACR Manual on Contrast Media. 2023 American College of Radiology. https://www.acr.org/Clinical-Resources/Contrast-Manual`n"
    }
    
    ShowResult(dosages)
}

DateAdd(datetime, value, unit) {
    EnvAdd, datetime, %value%, %unit%
    return datetime
}

; -------------------------------------------------------------------------
; 16) Fleischner Code
; -------------------------------------------------------------------------
class Nodule {
    __New(nString) {
        this.Description := nString
        this.Composition := ""
        this.Calcified := false
        this.mString := ""
        this.Units := ""
        this.Measurements := []
        this.HighRisk := false
        this.Location := ""
        this.Multiplicity := "single"
        this.Perifissural := false
        this.Morphology := ""
        this.GlobalHighRisk := false

        if (!this.ContainsNoduleReference(nString))
            throw Exception("No nodule reference", -1)
        
        this.ParseNoduleProperties(nString)
        this.ExtractMeasurements(nString)

        ; Handle cases where only the largest measurement is given for multiple nodules
        if (InStr(nString, "up to") and InStr(nString, "multiple")) {
            this.Multiplicity := "multiple"
        }
    }

    ContainsNoduleReference(nString) {
        noduleTerms := ["nodule", "nodules", "mass", "masses", "opacity", "opacities", "lesion", "lesions", "micronodule", "micronodules"]
        for _, term in noduleTerms {
            if (InStr(nString, term))
                return true
        }
        return false
    }

    ParseNoduleProperties(nString) {
        words := StrSplit(nString, A_Space)
        for index, word in words {
            if (this.IsMultiplicityWord(word))
                this.Multiplicity := "multiple"
            
            if (this.FuzzyMatch(word, "solid")) {
                if (this.Composition = "")
                    this.Composition := "solid"
                else if (this.Composition = "ground glass")
                    this.Composition := "part solid"
            }
            
            if (this.FuzzyMatch(word, "ground") and index < words.Length() and this.FuzzyMatch(words[index+1], "glass")) {
                if (this.Composition = "")
                    this.Composition := "ground glass"
                else if (this.Composition = "solid")
                    this.Composition := "part solid"
            }
            
            if (this.FuzzyMatch(word, "groundglass")) {
                if (this.Composition = "")
                    this.Composition := "ground glass"
                else if (this.Composition = "solid")
                    this.Composition := "part solid"
            }
            
            if ((this.FuzzyMatch(word, "part") and index < words.Length() and this.FuzzyMatch(words[index+1], "solid")) 
                or this.FuzzyMatch(word, "part-solid") or this.FuzzyMatch(word, "partsolid")) {
                this.Composition := "part solid"
            }
            
            if (this.FuzzyMatch(word, "calcified") or this.FuzzyMatch(word, "calcification") or this.FuzzyMatch(word, "calcifications"))
                this.Calcified := true
            
            if (this.FuzzyMatch(word, "noncalcified") or this.FuzzyMatch(word, "non-calcified"))
                this.Calcified := false

            if (this.FuzzyMatch(word, "emphysema") or this.FuzzyMatch(word, "fibrosis"))
                this.GlobalHighRisk := true

            lobeKeywords := ["upper", "middle", "lower", "lingula", "apical", "basal"]
            for _, keyword in lobeKeywords {
                if (this.FuzzyMatch(word, keyword)) {
                    this.Location .= " " . word
                }
            }
            if (this.FuzzyMatch(word, "right") or this.FuzzyMatch(word, "left")) {
                this.Location .= " " . word
            }

            if (this.FuzzyMatch(word, "perifissural") or this.FuzzyMatch(word, "fissure"))
                this.Perifissural := true

            morphologyKeywords := ["spiculated", "lobulated", "irregular", "smooth"]
            for _, keyword in morphologyKeywords {
                if (this.FuzzyMatch(word, keyword)) {
                    this.Morphology := keyword
                    break
                }
            }
        }
        this.Location := Trim(this.Location)

        if (InStr(nString, "multiple") or InStr(nString, "several") or InStr(nString, "numerous"))
            this.Multiplicity := "multiple"
    }

    IsMultiplicityWord(word) {
        multiplicityWords := ["nodules", "multiple", "several", "few", "numerous", "masses", "opacities", "lesions", "micronodules"]
        for _, w in multiplicityWords {
            if (this.FuzzyMatch(word, w))
                return true
        }
        return false
    }

    FuzzyMatch(word1, word2, threshold := 2) {
        return (LevenshteinDistance(word1, word2) <= threshold)
    }

	ExtractMeasurements(nString) {
	needle := "i)(?:up to|approximately|about|~)?\s*((?:\d*\.)?\d+)\s*(?:x\s*((?:\d*\.)?\d+))?\s*(?:x\s*((?:\d*\.)?\d+))?\s*([cm]m)"
		if (RegExMatch(nString, needle, match)) {
			this.mString := match
			this.Units := match4
			Loop, 3 {
				if (match%A_Index% != "")
					this.Measurements.Push(match%A_Index%)
			}
		}
		else {
			needle := "i)(?:up to|approximately|about|~)?\s*((?:\d*\.)?\d+)\s*([cm]m)"
			if (RegExMatch(nString, needle, match)) {
				this.mString := match
				this.Units := match2
				this.Measurements.Push(match1)
			}
			else if (InStr(nString, "micronodule") or InStr(nString, "micronodules")) {
				; Default size for micronodules when no measurement is given
				this.mString := "5 mm"
					this.Units := "mm"
						this.Measurements.Push(5)
				}
				else {
					; If no specific measurement found, look for any number followed by units
					needle := "i)((?:\d*\.)?\d+)\s*([cm]m)"
					if (RegExMatch(nString, needle, match)) {
						this.mString := match
						this.Units := match2
						this.Measurements.Push(match1)
					}
					else {
					throw Exception("No measurements found", -2)
					}
				}
			}
		; Store original measurements
		this.OriginalMeasurements := this.Measurements.Clone()
		this.OriginalUnits := this.Units
	}

    Size() {
        if (this.Measurements.Length() = 0)
            return 0
        
        totalSize := 0
        for _, measurement in this.Measurements {
            totalSize += measurement
        }
        averageSize := totalSize / this.Measurements.Length()

        ; Convert to mm if necessary
        if (this.Units = "cm")
            return averageSize * 10  ; Convert cm to mm
        return averageSize  ; Already in mm
    }
	
    UpdateMString() {
        if (this.OriginalMeasurements.Length() = 0)
            return

        sizes := []
        for _, measurement in this.OriginalMeasurements {
            sizes.Push(Format("{:.1f}", measurement))
        }
        
        this.mString := Join(sizes, " x ") . " " . this.OriginalUnits
    }

    Category() {
        s := this.Size()  ; s is now always in mm
        
        if (this.Composition == "solid" or this.Composition == "") {
            if (this.Multiplicity == "multiple") {
                if (s < 6)
                    return "multiple_solid_small"
                else if (s >= 6 and s <= 8)
                    return "multiple_solid_medium"
                else
                    return "multiple_solid_large"
            } else {
                if (s < 6)
                    return "single_solid_small"
                else if (s >= 6 and s <= 8)
                    return "single_solid_medium"
                else
                    return "single_solid_large"
            }
        } else if (this.Composition == "ground glass") {
            if (this.Multiplicity == "multiple") {
                if (s < 6)
                    return "multiple_subsolid_small"
                else
                    return "multiple_subsolid_large"
            } else {
                if (s < 6)
                    return "single_gg_small"
                else
                    return "single_gg_large"
            }
        } else if (this.Composition == "part solid") {
            if (this.Multiplicity == "multiple") {
                if (s < 6)
                    return "multiple_subsolid_small"
                else
                    return "multiple_subsolid_large"
            } else {
                if (s < 6)
                    return "single_ps_small"
                else
                    return "single_ps_large"
            }
        }
    }

    Recommendation() {
        category := this.Category()
        risk := this.HighRisk ? "high" : "low"
        
        if (recommendations.HasKey(category)) {
            if (IsObject(recommendations[category]))
                return recommendations[category][risk]
            else
                return recommendations[category]
        }
        return "Unable to determine recommendation."
    }
}

InitializeRecommendations() {
    ObjRawSet(recommendations, "single_solid_small", {low: "No routine follow-up.", high: "Optional CT at 12 months."})
    ObjRawSet(recommendations, "single_solid_medium", {low: "CT at 6-12 months, then consider CT at 18-24 months.", high: "CT at 6-12 months, then CT at 18-24 months."})
    ObjRawSet(recommendations, "single_solid_large", {low: "Consider CT at 3 months, PET/CT, or tissue sampling.", high: "Consider CT at 3 months, PET/CT, or tissue sampling."})
    ObjRawSet(recommendations, "multiple_solid_small", {low: "No routine follow-up.", high: "Optional CT at 12 months."})
    ObjRawSet(recommendations, "multiple_solid_medium", {low: "CT at 3-6 months, then consider CT at 18-24 months.", high: "CT at 3-6 months, then at 18-24 months."})
    ObjRawSet(recommendations, "multiple_solid_large", {low: "CT at 3-6 months, then consider CT at 18-24 months.", high: "CT at 3-6 months, then at 18-24 months."})
    ObjRawSet(recommendations, "single_gg_small", "No routine follow-up.")
    ObjRawSet(recommendations, "single_gg_large", "CT at 6-12 months to confirm persistence, then every 2 years until 5 years.")
    ObjRawSet(recommendations, "single_ps_small", "No routine follow-up.")
    ObjRawSet(recommendations, "single_ps_large", "CT at 3-6 months to confirm persistence. If unchanged and solid component remains <6mm, annual CT should be performed for 5 years.")
    ObjRawSet(recommendations, "multiple_subsolid_small", "CT at 3-6 months. If stable, consider CT at 2 and 4 years.")
	ObjRawSet(recommendations, "multiple_subsolid_large", "CT at 3-6 months. Subsequent management based on the most suspicious nodule(s).")
}

Join(arr, sep) {
    result := ""
    for index, element in arr {
        if (index > 1)
            result .= sep
        result .= element
    }
    return result
}

PreprocessTextNodules(text) {
    sentences := []
    lines := StrSplit(text, "`n", "`r")
    for _, line in lines {
        ; Remove bullet points
        line := RegExReplace(line, "^\s*[\*\-•]\s*", "")
        
        ; Split by periods, but be careful with measurements
        parts := StrSplit(line, ".")
        for index, part in parts {
            part := Trim(part)
            ; Check if this part is a continuation of a measurement
            if (index > 1 && RegExMatch(parts[index-1], "\d+$") && RegExMatch(part, "^\d+"))
                sentences[sentences.Length()] .= "." . part
            else if (part != "")
                sentences.Push(part)
        }
    }
    return sentences
}

ProcessNodules(text) {
    result := ""
    sentences := PreprocessTextNodules(text)
    nodules := []
    globalHighRisk := CheckHighRiskConditions(text)
    isMultiple := false

    for _, sentence in sentences {
        multipleNodulesProbability := CalculateMultipleNodulesProbability(sentence)
        isMultiple := (multipleNodulesProbability >= 0.45) or isMultiple  ; Adjusted threshold and accumulate

        noduleDescriptions := SplitNoduleDescriptions(sentence)
        for _, description in noduleDescriptions {
            try {
                nodule := new Nodule(description)
                nodule.GlobalHighRisk := globalHighRisk
                nodule.Multiplicity := isMultiple ? "multiple" : "single"
                nodules.Push(nodule)
            } catch e {
                ; Skip invalid nodule descriptions
            }
        }
    }

    if (nodules.Length() = 0) {
        ; Check for general mention of micronodules or multiple nodules
        if (InStr(text, "micronodule") or InStr(text, "micronodules") or (InStr(text, "multiple") and InStr(text, "nodule"))) {
            nodule := new Nodule("Multiple nodules measuring up to 5 mm")
            nodule.GlobalHighRisk := globalHighRisk
            nodule.Multiplicity := "multiple"
            nodules.Push(nodule)
        } else {
            result := "Error: No valid nodules found."
            return result
        }
    }

    ; Find the most significant nodule
    mostSignificantNodule := nodules[1]
    for _, nodule in nodules {
        nodule.UpdateMString()  ; Update mString for each nodule
        if (nodule.Size() > mostSignificantNodule.Size() or (nodule.Size() = mostSignificantNodule.Size() and IsMoreSignificant(nodule, mostSignificantNodule))) {
            mostSignificantNodule := nodule
        }
    }

    ; Ensure multiplicity is set correctly
    if (nodules.Length() > 1 or isMultiple or InStr(text, "multiple") or InStr(text, "micronodules")) {
        mostSignificantNodule.Multiplicity := "multiple"
    }

    ; Generate result string
    result := text . "`n`n"  ; Preserve input text at the top
    result .= "Fleischner 2017 assessment:`n"
    if (mostSignificantNodule.Multiplicity == "multiple") {
        result .= "Multiple pulmonary nodules are present. The most significant nodule forming the basis of follow-up:`n"
    } else {
        result .= "A solitary pulmonary nodule is described forming the basis of follow-up:`n"
    }
    result .= "- Location: " . (mostSignificantNodule.Location ? mostSignificantNodule.Location : "Not specified") . "`n"
    result .= "- Extracted (or inferred) Size: " . mostSignificantNodule.mString . "`n"
    result .= "- Fleischner Size (mm): " . Format("{:.1f} mm", mostSignificantNodule.Size()) . "`n"
    result .= "- Composition (or inferred): " . (mostSignificantNodule.Composition ? mostSignificantNodule.Composition : "solid") . "`n"
    if (mostSignificantNodule.Calcified)
        result .= "- Calcification: Present`n"
    if (mostSignificantNodule.Morphology)
        result .= "- Morphology: " . mostSignificantNodule.Morphology . "`n"
		
    currentDate := A_Now

    result .= "`nFLEISCHNER SOCIETY RECOMMENDATION:`n"
    if ((globalHighRisk || mostSignificantNodule.Morphology == "spiculated") && !mostSignificantNodule.Calcified) {
        mostSignificantNodule.HighRisk := true
        recommendation := mostSignificantNodule.Recommendation()
        result .= AddFollowUpDates(recommendation, currentDate)
    } else {
        if (!mostSignificantNodule.Calcified && mostSignificantNodule.Composition == "solid" || mostSignificantNodule.Composition == "") {
            lowRiskRec := mostSignificantNodule.Recommendation()
            result .= "For low-risk patients: " . AddFollowUpDates(lowRiskRec, currentDate) . "`n"
            mostSignificantNodule.HighRisk := true
            highRiskRec := mostSignificantNodule.Recommendation()
            result .= "`nFor high-risk patients: " . AddFollowUpDates(highRiskRec, currentDate) . "`n"
		} else if (!mostSignificantNodule.Calcified && (mostSignificantNodule.Composition == "part solid" || mostSignificantNodule.Composition == "ground glass")) {
			recommendation := mostSignificantNodule.Recommendation()
			result .= AddFollowUpDates(recommendation, currentDate)
		} else {
            result .= "Incidental calcified nodules do not typically require routine follow up.`n"
        }
    }

    result .= "`n`nSSM lung nodule"

    if (globalHighRisk || mostSignificantNodule.Morphology == "spiculated")
        result .= "`n`nNote: Patient has risk factors or morphologic characteristics that may increase the risk of lung cancer."

    if (ShowCitations)
        result .= "`n`nCitation: MacMahon H, Naidich DP, Goo JM, et al. Guidelines for Management of Incidental Pulmonary Nodules Detected on CT Images: From the Fleischner Society 2017. Radiology. 2017;284(1):228-243. doi:10.1148/radiol.2017161659"
   
    return result
}

IsMoreSignificant(nodule1, nodule2) {
    ; Order of significance: solid > part solid > ground glass
    compositionOrder := {"solid": 3, "part solid": 2, "ground glass": 1}
    return compositionOrder[nodule1.Composition] > compositionOrder[nodule2.Composition]
}

SplitNoduleDescriptions(text) {
    descriptions := []
    ; Modified regex to capture nodule descriptions more accurately, including cases where size appears before location and "nodule"
    needle := "i)(?:(?:\d+(?:\.\d+)?\s*(?:x\s*\d+(?:\.\d+)?)*\s*(?:mm|cm))\s*(?:[a-z\s]+\s+)?(?:pulmonary\s+)?(?:nodule|mass|opacity|lesion)s?|(?:(?:multiple\s+)?(?:nodule|mass|opacity|lesion)s?(?:\s+(?:up to|approximately|about|~)?)?\s*(?:\d+(?:\.\d+)?\s*(?:x\s*\d+(?:\.\d+)?)*\s*(?:mm|cm))?|(?:(?:up to|approximately|about|~)?\s*\d+(?:\.\d+)?\s*(?:x\s*\d+(?:\.\d+)?)*\s*(?:mm|cm))?\s*(?:(?:solid|ground glass|part[- ]solid|calcified|noncalcified|spiculated|lobulated|irregular|smooth)?\s*(?:pulmonary\s+)?(?:nodule|mass|opacity|lesion)s?)))(?:\s*\([^)]+\))?"
    
    ; Split the text into lines
    lines := StrSplit(text, "`n", "`r")
    for _, line in lines {
        pos := 1
        while (pos := RegExMatch(line, needle, match, pos)) {
            descriptions.Push(Trim(match))
            pos += StrLen(match)
        }
    }
    
    ; If no specific nodule descriptions found, check for general mentions of nodules
    if (descriptions.Length() = 0) {
        if (RegExMatch(text, "i)(?:multiple\s+)?nodules?.*(?:measure|up to).*(\d+(?:\.\d+)?)\s*(?:x\s*\d+(?:\.\d+)?)*\s*(mm|cm)", match)) {
            descriptions.Push(match)
        } else if (InStr(text, "micronodule") or InStr(text, "micronodules")) {
            descriptions.Push("Multiple micronodules")
        } else if (InStr(text, "multiple") and InStr(text, "nodule")) {
            descriptions.Push("Multiple nodules")
        }
    }
    
    ; If still no descriptions found, return the entire text
    if (descriptions.Length() = 0) {
        descriptions.Push(text)
    }
    
    return descriptions
}

AddFollowUpDates(recommendation, currentDate) {
    followUpPeriods := []
    
    if (InStr(recommendation, "3 months"))
        followUpPeriods.Push({min: 90, max: 90, text: "3 months"})
	if (InStr(recommendation, "3-6 months"))
        followUpPeriods.Push({min: 90, max: 183, text: "3-6 months"})
    if (InStr(recommendation, "6-12 months"))
        followUpPeriods.Push({min: 180, max: 365, text: "6-12 months"})
    if (InStr(recommendation, "18-24 months"))
        followUpPeriods.Push({min: 540, max: 730, text: "18-24 months"})
	if (InStr(recommendation, "2 years until 5 years"))
        followUpPeriods.Push({min: 1095, max: 1825, text: "2 years until 5 years"})
    
    if (followUpPeriods.Length() > 0) {
        recommendation .= "`nFollow-up dates:"
        for _, period in followUpPeriods {
            minDate := DateCalc(currentDate, period.min)
            maxDate := DateCalc(currentDate, period.max)
            FormatTime, formattedMinDate, %minDate%, MMMM yyyy
            FormatTime, formattedMaxDate, %maxDate%, MMMM yyyy
			FormatTime, formattedCurrentDate, %currentDate%, MMMM yyyy
            if (formattedMinDate != formattedMaxDate)
                recommendation .= " " . period.text . " is " . formattedMinDate . " to " . formattedMaxDate . " from " . formattedCurrentDate . ". "
            else
                recommendation .= " " . period.text . " is " . formattedMinDate . " from " . formattedCurrentDate . ". "
        }
    }
    
    return recommendation
}

CheckHighRiskConditions(text) {
    StringLower text, text ; Convert to lowercase
    highRiskTerms := ["emphysema", "fibrosis", "fibrotic", "emphysematous"]
    
    for _, term in highRiskTerms {
        words := StrSplit(text, A_Space)
        for _, word in words {
            if (FuzzyMatchGlobal(word, term))
                return true
        }
    }
    return false
}

FuzzyMatchGlobal(word1, word2, threshold := 2) {
    return (LevenshteinDistance(word1, word2) <= threshold)
}

CalculateMultipleNodulesProbability(text) {
    probability := 0
    
    ; Check for explicit mentions of multiple nodules
    if (InStr(text, "nodules") or InStr(text, "multiple") or InStr(text, "several") or InStr(text, "few"))
        probability += 0.7
    
    ; Check for scattered micronodules
    if (InStr(text, "scattered") and InStr(text, "micronodules"))
        probability += 0.6
    
    ; Check for multiple measurements
    measurementCount := 0
    pos := 1
    while (pos := RegExMatch(text, "i)(\d+(?:\.\d+)?\s*(mm|cm))", match, pos + StrLen(match)))
        measurementCount++
    
    if (measurementCount > 1)
        probability += 0.5  ; Increased weight for multiple measurements
    
    ; Check for multiple locations
    lobeKeywords := ["upper", "middle", "lower", "lingula", "apical", "basal", "right", "left"]
    uniqueLocations := {}
    for _, keyword in lobeKeywords {
        if (InStr(text, keyword))
            uniqueLocations[keyword] := true
    }
    
    if (uniqueLocations.Count() > 1)
        probability += 0.3  ; Increased weight for multiple locations
    
    ; Count number of times "nodule" (singular) is mentioned
    noduleCount := 0
    pos := 1
    while (pos := InStr(text, "nodule", false, pos))
    {
        noduleCount++
        pos += 6  ; length of "nodule"
    }
    
    if (noduleCount > 1)
        probability += 0.4  ; Add probability if "nodule" is mentioned multiple times
    
    return (probability > 1) ? 1 : probability
}
; ------------------------------------------
; Go to MESA website and get informatoin
; ------------------------------------------
DownloadToString(url, postData := "") {
    static INTERNET_FLAG_RELOAD := 0x80000000
    static INTERNET_FLAG_SECURE := 0x00800000
    static SECURITY_FLAG_IGNORE_UNKNOWN_CA := 0x00000100
    
    hModule := DllCall("LoadLibrary", "Str", "wininet.dll", "Ptr")
    if (!hModule)
        return "Error: Failed to load wininet.dll. Error code: " . A_LastError
    
    hInternet := DllCall("wininet\InternetOpenA", "Str", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", "UInt", 1, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr")
    if (!hInternet) {
        DllCall("FreeLibrary", "Ptr", hModule)
        return "Error: InternetOpen failed. Error code: " . A_LastError
    }
    
    hConnect := DllCall("wininet\InternetConnectA", "Ptr", hInternet, "Str", "www.mesa-nhlbi.org", "UShort", 443, "Ptr", 0, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
    if (!hConnect) {
        DllCall("wininet\InternetCloseHandle", "Ptr", hInternet)
        DllCall("FreeLibrary", "Ptr", hModule)
        return "Error: InternetConnect failed. Error code: " . A_LastError
    }
    
    flags := INTERNET_FLAG_RELOAD | INTERNET_FLAG_SECURE | SECURITY_FLAG_IGNORE_UNKNOWN_CA
    hRequest := DllCall("wininet\HttpOpenRequestA", "Ptr", hConnect, "Str", (postData ? "POST" : "GET"), "Str", "/Calcium/input.aspx", "Str", "HTTP/1.1", "Ptr", 0, "Ptr", 0, "UInt", flags, "Ptr", 0, "Ptr")
    if (!hRequest) {
        DllCall("wininet\InternetCloseHandle", "Ptr", hConnect)
        DllCall("wininet\InternetCloseHandle", "Ptr", hInternet)
        DllCall("FreeLibrary", "Ptr", hModule)
        return "Error: HttpOpenRequest failed. Error code: " . A_LastError
    }
    
    headers := "Content-Type: application/x-www-form-urlencoded`r`n"
             . "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36`r`n"
             . "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9`r`n"
             . "Accept-Language: en-US,en;q=0.9`r`n"
    DllCall("wininet\HttpAddRequestHeadersA", "Ptr", hRequest, "Str", headers, "UInt", -1, "UInt", 0x10000000, "Int")
    
    VarSetCapacity(buffer, 8192, 0)
    if (postData) {
        VarSetCapacity(postDataBuffer, StrLen(postData), 0)
        StrPut(postData, &postDataBuffer, "UTF-8")
        result := DllCall("wininet\HttpSendRequestA", "Ptr", hRequest, "Ptr", 0, "UInt", 0, "Ptr", &postDataBuffer, "UInt", StrLen(postData), "Int")
    } else {
        result := DllCall("wininet\HttpSendRequestA", "Ptr", hRequest, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "Int")
    }
    
    if (!result) {
        errorCode := A_LastError
        DllCall("wininet\InternetCloseHandle", "Ptr", hRequest)
        DllCall("wininet\InternetCloseHandle", "Ptr", hConnect)
        DllCall("wininet\InternetCloseHandle", "Ptr", hInternet)
        DllCall("FreeLibrary", "Ptr", hModule)
        return "Error: HttpSendRequest failed. Error code: " . errorCode
    }
    
    VarSetCapacity(responseText, 1024*1024)  ; Allocate 1MB for the response
    bytesRead := 0
    totalBytesRead := 0
    
    Loop {
        result := DllCall("wininet\InternetReadFile", "Ptr", hRequest, "Ptr", &buffer, "UInt", 8192, "Ptr", &bytesRead, "Int")
        bytesRead := NumGet(bytesRead, 0, "UInt")
        if (bytesRead == 0)
            break
        DllCall("RtlMoveMemory", "Ptr", &responseText + totalBytesRead, "Ptr", &buffer, "Ptr", bytesRead)
        totalBytesRead += bytesRead
    }
    
    responseText := StrGet(&responseText, totalBytesRead, "UTF-8")
    
    DllCall("wininet\InternetCloseHandle", "Ptr", hRequest)
    DllCall("wininet\InternetCloseHandle", "Ptr", hConnect)
    DllCall("wininet\InternetCloseHandle", "Ptr", hInternet)
    DllCall("FreeLibrary", "Ptr", hModule)
    
    return responseText
}


GetRaceValue(race) {
    switch race {
        case "White": return 3
        case "Black": return 0
        case "Hispanic": return 2
        case "Chinese": return 1
    }
}

GetSexValue(sex) {
    switch sex {
        case "Male": return 1
        case "Female": return 0
    }
}

GetLastErrorMessage(errorCode) {
    VarSetCapacity(msg, 1024)
    DllCall("FormatMessage"
        , "UInt", 0x1000      ; FORMAT_MESSAGE_FROM_SYSTEM
        , "Ptr", 0
        , "UInt", errorCode
        , "UInt", 0           ; Default language
        , "Str", msg
        , "UInt", 1024
        , "Ptr", 0)
    return msg
}

SendHttpRequest(url, postData := "") {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open(postData ? "POST" : "GET", url, true)
        whr.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        whr.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36")
        whr.Send(postData)
        whr.WaitForResponse()
        return whr.ResponseText
    }
    catch e {
        return "Error: " . e.message
    }
}

UrlEncode(str) {
    oldFormat := A_FormatInteger
    SetFormat, Integer, Hex
    VarSetCapacity(var, StrPut(str, "UTF-8"), 0)
    StrPut(str, &var, "UTF-8")
    StringLower, str, str
    Loop
    {
        code := NumGet(var, A_Index - 1, "UChar")
        If (!code)
            break
        If (code >= 0x30 && code <= 0x39 ; 0-9
            || code >= 0x41 && code <= 0x5A ; A-Z
            || code >= 0x61 && code <= 0x7A) ; a-z
            result .= Chr(code)
        Else
            result .= "%" . SubStr(code + 0x100, -1)
    }
    SetFormat, Integer, %oldFormat%[]
    return result
}
; ------------------------------------------
; Levenshtein Distance for Fleischner
; ------------------------------------------
LevenshteinDistance(s, t) {
    m := StrLen(s)
    n := StrLen(t)
    d := []

    Loop, % m + 1
    {
        d[A_Index] := []
        d[A_Index, 1] := A_Index - 1
    }

    Loop, % n + 1
        d[1, A_Index] := A_Index - 1

    Loop, % m
    {
        i := A_Index
        Loop, % n
        {
            j := A_Index
            cost := (SubStr(s, i, 1) = SubStr(t, j, 1)) ? 0 : 1
            d[i+1, j+1] := Min(d[i, j+1] + 1, d[i+1, j] + 1, d[i, j] + cost)
        }
    }

    return d[m+1, n+1]
}

; -------------------------------------------------------------
; References Management
; -------------------------------------------------------------
CreateReferencesMenu() {
    Menu, ReferencesMenu, Add
    Menu, ReferencesMenu, DeleteAll
    
    ; Add management options at top
    Menu, ReferencesMenu, Add, Add Reference..., AddReference
    Menu, ReferencesMenu, Add, Remove References..., RemoveReferences
    Menu, ReferencesMenu, Add  ; Separator
    
    ; Create sorted array of references
    refs := []
    for name, data in g_References {
        refs.Push({name: name, uses: data.uses})
    }
    
    ; Sort references by usage count (descending)
    SortReferencesByUse(refs)
    
    ; Add sorted references to menu
    count := 0
    for _, ref in refs {
        if (count >= g_MaxReferences)
            break
        Menu, ReferencesMenu, Add, % ref.name, OpenReference
        count++
    }
}

; Helper function to sort references by usage count
SortReferencesByUse(ByRef refs) {
    ; Create temporary arrays for sorting
    tempArray := []
    sortedArray := []
    
    ; Copy all items to temp array
    for index, ref in refs {
        tempArray.Push(ref)
    }
    
    ; Sort by uses (descending)
    while (tempArray.Length() > 0) {
        highestUses := -1
        highestIndex := 0
        for index, ref in tempArray {
            if (ref.uses > highestUses) {
                highestUses := ref.uses
                highestIndex := index
            }
        }
        sortedArray.Push(tempArray[highestIndex])
        tempArray.RemoveAt(highestIndex)
    }
    
    ; Clear and repopulate refs with sorted items
    refs := []
    for _, ref in sortedArray {
        refs.Push(ref)
    }
    
    return refs
}

AddReference() {
    global RefName, RefPath
    
    ; Get current mouse position
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    
    ; Determine which monitor the mouse is on
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom)
        {
            activeMonitor := A_Index
            break
        }
    }
    
    ; Get dimensions of the active monitor
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop
    
    ; Calculate GUI dimensions and position
    guiWidth := 300
    guiHeight := 150
    xPos := mouseX + 10
    yPos := mouseY + 10
    
    ; Ensure the GUI doesn't go off-screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight
    
    Gui, AddRef:New, +AlwaysOnTop
    Gui, AddRef:Add, Text,, Enter reference details:
    Gui, AddRef:Add, Edit, vRefName w280, Reference Name
    Gui, AddRef:Add, Edit, vRefPath w280, Location (URL or File Path)
    Gui, AddRef:Add, Button, gBrowseReference w90, Browse...
    Gui, AddRef:Add, Button, gSaveReference w90, Save
    Gui, AddRef:Add, Button, x+10 w90 gAddRefGuiClose, Cancel
    Gui, AddRef:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Add Reference
}

BrowseReference() {
    FileSelectFile, filePath, 3, , Select File, Documents (*.pdf; *.doc; *.docx; *.xls; *.xlsx, *.ppt, *.pptx)
    if (filePath) {
        GuiControl, AddRef:, RefPath, %filePath%
        SplitPath, filePath, fileName
        GuiControl, AddRef:, RefName, %fileName%
    }
}

SaveReference() {
    global RefName, RefPath, g_References
    Gui, AddRef:Submit, NoHide
    
    RefName := Trim(RefName)  ; Trim any whitespace
    RefPath := Trim(RefPath)  ; Trim any whitespace
    
    if (RefName = "") {
        MsgBox, Please enter a reference name.
        return
    }
    
    if (RefPath = "") {
        MsgBox, Please enter a URL or file path.
        return
    }

    ; Automatically determine if it's a file or URL
    if (FileExist(RefPath)) {
        ; It's a file
        SplitPath, RefPath, fileName, , fileExt
        if !IsValidFileType(fileExt) {
            MsgBox, Invalid file type. Only PDF, PPT, PPTX, XLS, XLSX, DOC, and DOCX files are allowed.
            return
        }
        
        referencesDir := A_ScriptDir . "\References"
        if (!FileExist(referencesDir))
            FileCreateDir, %referencesDir%
        
        destPath := referencesDir . "\" . fileName
        if (FileExist(destPath)) {
            MsgBox, 4, File Exists, File already exists. Would you like to create a new copy?
            IfMsgBox Yes
            {
                destPath := GetUniqueFilePath(referencesDir, fileName)
                FileCopy, %RefPath%, %destPath%
            }
        } else {
            FileCopy, %RefPath%, %destPath%
        }
        
        g_References[RefName] := {type: "file", path: destPath, uses: 0}
    } else if (IsValidURL(RefPath)) {
        ; It's a URL
        g_References[RefName] := {type: "url", path: RefPath, uses: 0}
    } else {
        MsgBox, The location must be either a valid file path or URL.
        return
    }
    
    SavePreferencesToFile()
    CreateReferencesMenu()  ; Refresh the menu after adding new reference
    Gui, AddRef:Destroy
}

MapReference() {
    ; Get current mouse position
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    
    ; Determine which monitor the mouse is on
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom)
        {
            activeMonitor := A_Index
            break
        }
    }
    
    ; Get dimensions of the active monitor
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop
    
    ; Calculate GUI dimensions and position
    guiWidth := 300
    guiHeight := 180
    xPos := mouseX + 10
    yPos := mouseY + 10
    
    ; Ensure the GUI doesn't go off-screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight
    
    Gui, MapRef:New, +AlwaysOnTop
    Gui, MapRef:Add, Text,, Select file to map:
    Gui, MapRef:Add, Edit, vRefName w280, Reference Name
    Gui, MapRef:Add, Edit, vRefPath w280, File Path
    Gui, MapRef:Add, Button, gBrowseMapReference w90, Browse...
    Gui, MapRef:Add, Button, gSaveMapReference w90, Save
    Gui, MapRef:Add, Button, x+10 w90 gMapRefGuiClose, Cancel
    Gui, MapRef:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Map Reference
}

SaveMapReference() {
    Gui, MapRef:Submit, NoHide
    
    if (RefName = "") {
        MsgBox, Please enter a reference name.
        return
    }
    
    if (!FileExist(RefPath)) {
        MsgBox, File does not exist.
        return
    }
    
    SplitPath, RefPath, , , fileExt
    if !IsValidFileType(fileExt) {
        MsgBox, Invalid file type. Only PDF, XLS, XLSX, DOC, and DOCX files are allowed.
        return
    }
    
    g_References[RefName] := {type: "mapped", path: RefPath}
    SavePreferencesToFile()
    Gui, MapRef:Destroy
}

RemoveReferences() {
    global RefType, RefName, RefPath
    
    ; Get current mouse position
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    
    ; Determine which monitor the mouse is on
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount%
    {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom)
        {
            activeMonitor := A_Index
            break
        }
    }
    
    ; Get dimensions of the active monitor
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop
    
    ; Calculate GUI dimensions and position
    guiWidth := 400
    guiHeight := 300
    xPos := mouseX + 10
    yPos := mouseY + 10
    
    ; Ensure the GUI doesn't go off-screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight
    
    Gui, RemoveRef:New, +AlwaysOnTop
    Gui, RemoveRef:Add, ListView, vRefList w380 h230 gRefListHandler -Multi, Reference|Type|Path
    
    ; In v1.1, objects are handled with key-value pairs
    for name, data in g_References {
        LV_Add("", name, data.type, data.path)
    }
    
    Gui, RemoveRef:Add, Button, w120 gRemoveSelectedReferences, Remove Selected
    Gui, RemoveRef:Add, Button, x+10 w120 gRemoveRefGuiClose, Close
    Gui, RemoveRef:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Remove References
}

RemoveSelectedReferences() {
    ; Get the position of the Remove References GUI
    Gui, RemoveRef:+LastFound
    WinGetPos, guiX, guiY, guiW, guiH
    
    selectedRows := []
    row := 0
    
    ; Collect all selected rows first
    while (row := LV_GetNext(row)) {
        selectedRows.Insert(row)
    }
    
    removedCount := 0
    
    ; Process selected rows in reverse order to maintain correct indices
    Loop % selectedRows.MaxIndex() {
        row := selectedRows[selectedRows.MaxIndex() - A_Index + 1]
        LV_GetText(name, row, 1)
        
        ; Calculate position for the MsgBox relative to the GUI
        msgBoxX := guiX + (guiW / 2) - 150
        msgBoxY := guiY + (guiH / 2) - 50
        
        ; Ensure message box stays on screen
        SysGet, workArea, MonitorWorkArea
        if (msgBoxX < workAreaLeft)
            msgBoxX := workAreaLeft
        if (msgBoxX + 300 > workAreaRight)
            msgBoxX := workAreaRight - 300
        if (msgBoxY < workAreaTop)
            msgBoxY := workAreaTop
        if (msgBoxY + 100 > workAreaBottom)
            msgBoxY := workAreaBottom - 100
        
        ; Position and set AlwaysOnTop for the message box
        SetTimer, MoveMsgBoxTop, 50
        MsgBox, 4, Confirm Removal, Are you sure you want to remove "%name%"?
        SetTimer, MoveMsgBoxTop, Off
        
        IfMsgBox Yes
        {
            g_References.Delete(name)
            removedCount++
        }
    }
    
    if (removedCount > 0) {
        SavePreferencesToFile()
        Gui, RemoveRef:Destroy
        RemoveReferences()  ; Refresh the list
    }
}

MoveMsgBoxTop:
    WinGetPos, guiX, guiY, guiW, guiH, Remove References
    if WinExist("Confirm Removal") {
        msgBoxX := guiX + (guiW / 2) - 150
        msgBoxY := guiY + (guiH / 2) - 50
        WinMove, Confirm Removal,, msgBoxX, msgBoxY
        WinSet, AlwaysOnTop, On, Confirm Removal
        ; Also activate the window to ensure focus
        WinActivate, Confirm Removal
    }
return

OpenReference(ItemName) {
    if (g_References.HasKey(ItemName)) {
        thisRef := g_References[ItemName]
        refType := thisRef["type"]
        refPath := thisRef["path"]
        
        if (refType = "url") {
            ; Ensure URL has proper protocol
            if (!RegExMatch(refPath, "^https?://")) {
                refPath := "https://" . refPath
            }
            Run, %refPath%  ; Direct browser launch
            thisRef["uses"] += 1
            SavePreferencesToFile()
        } else {  ; file or mapped
            if (FileExist(refPath)) {
                Run, %refPath%
                thisRef["uses"] += 1
                SavePreferencesToFile()
            } else {
                MsgBox, File not found: %refPath%
            }
        }
    }
}

IsValidURL(url) {
    return RegExMatch(url, "i)^(?:(?:https?|ftp)://)?(?:\w+\.)?\w+\.\w+(?:/|$)")
}

IsValidFileType(ext) {
    static validTypes := {pdf: 1, xls: 1, xlsx: 1, doc: 1, docx: 1}
    StringLower, ext, ext
    return validTypes.HasKey(ext)
}

GetUniqueFilePath(dir, fileName) {
    SplitPath, fileName, , , ext, nameNoExt
    newPath := dir . "\" . fileName
    counter := 1
    
    while (FileExist(newPath)) {
        newPath := dir . "\" . nameNoExt . " (" . counter . ")." . ext
        counter++
    }
    
    return newPath
}

AddRefGuiClose:
    Gui, Destroy
return
MapRefGuiClose:
RemoveRefGuiClose:
    Gui, Destroy
return

RefListHandler:
return

; ------------------------------------------
; AI Prompt
; ------------------------------------------

CreateAIAssistantMenu() {
    Menu, AIAssistantMenu, Add
    Menu, AIAssistantMenu, DeleteAll
    
    ; Add management options at top
    Menu, AIAssistantMenu, Add, Add Prompt..., AddAIPrompt
    Menu, AIAssistantMenu, Add, Manage Prompts..., ManageAIPrompts
    Menu, AIAssistantMenu, Add, AI Settings..., AISettings
    Menu, AIAssistantMenu, Add  ; Separator
    
    ; Create sorted array of prompts
    prompts := []
    for name, data in g_AIPrompts {
        prompts.Push({name: name, uses: data.uses})
    }
    
    ; Sort prompts by usage count (descending)
    SortPromptsByUse(prompts)
    
    ; Add sorted prompts to menu
    count := 0
    for _, prompt in prompts {
        if (count >= g_MaxAIPrompts)
            break
        Menu, AIAssistantMenu, Add, % prompt.name, ExecuteAIPrompt
        count++
    }
}

SortPromptsByUse(ByRef prompts) {
    tempArray := []
    sortedArray := []
    
    for index, prompt in prompts {
        tempArray.Push(prompt)
    }
    
    while (tempArray.Length() > 0) {
        highestUses := -1
        highestIndex := 0
        for index, prompt in tempArray {
            if (prompt.uses > highestUses) {
                highestUses := prompt.uses
                highestIndex := index
            }
        }
        sortedArray.Push(tempArray[highestIndex])
        tempArray.RemoveAt(highestIndex)
    }
    
    prompts := []
    for _, prompt in sortedArray {
        prompts.Push(prompt)
    }
    
    return prompts
}

AddAIPrompt() {
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    
    ; Get active monitor
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount% {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom) {
            activeMonitor := A_Index
            break
        }
    }
    
    ; Get monitor work area
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    monitorWidth := workAreaRight - workAreaLeft
    monitorHeight := workAreaBottom - workAreaTop
    
    ; Calculate GUI position
    guiWidth := 400
    guiHeight := 200
    xPos := mouseX + 10
    yPos := mouseY + 10
    
    ; Ensure GUI stays on screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight
    
    Gui, AddPrompt:New, +AlwaysOnTop
    Gui, AddPrompt:Add, Text,, Prompt Name:
    Gui, AddPrompt:Add, Edit, vvPromptName w380
    Gui, AddPrompt:Add, Text,, Prompt Text:
    Gui, AddPrompt:Add, Edit, vvPromptText w380 h80
    Gui, AddPrompt:Add, Button, gSaveAIPrompt w90, Save
    Gui, AddPrompt:Add, Button, x+10 w90 gAddPromptGuiClose, Cancel
    Gui, AddPrompt:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Add AI Prompt
}

SaveAIPrompt() {
    global vPromptName, vPromptText, g_AIPrompts
    Gui, AddPrompt:Submit, NoHide
    
    if (vPromptName = "" || vPromptText = "") {
        MsgBox, Please fill in both fields.
        return
    }
    
    g_AIPrompts[vPromptName] := {prompt: vPromptText, uses: 0}
    SavePreferencesToFile()
    CreateAIAssistantMenu()
    Gui, AddPrompt:Destroy
}

ManageAIPrompts() {
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    
    ; Get active monitor
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount% {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom) {
            activeMonitor := A_Index
            break
        }
    }
    
    ; Get monitor work area
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    
    ; Calculate GUI position
    guiWidth := 500
    guiHeight := 400
    xPos := mouseX + 10
    yPos := mouseY + 10
    
    ; Ensure GUI stays on screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight
    
    Gui, ManagePrompts:New, +AlwaysOnTop
    Gui, ManagePrompts:Add, ListView, vPromptList w480 h330 gPromptListHandler -Multi, Prompt Name|Prompt Text|Uses
    
    for name, data in g_AIPrompts {
        LV_Add("", name, data.prompt, data.uses)
    }
    
    ; Add three buttons with equal spacing
    Gui, ManagePrompts:Add, Button, w120 gEditSelectedPrompt, Edit
    Gui, ManagePrompts:Add, Button, x+10 w120 gRemoveSelectedPrompts, Remove Selected
    Gui, ManagePrompts:Add, Button, x+10 w120 gManagePromptsGuiClose, Close
    Gui, ManagePrompts:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, Manage AI Prompts
}

RemoveSelectedPrompts() {
    selectedRows := []
    row := 0
    
    while (row := LV_GetNext(row)) {
        selectedRows.Insert(row)
    }
    
    removedCount := 0
    
    Loop % selectedRows.MaxIndex() {
        row := selectedRows[selectedRows.MaxIndex() - A_Index + 1]
        LV_GetText(name, row, 1)
        
        MsgBox, 4, Confirm Removal, Are you sure you want to remove "%name%"?
        IfMsgBox Yes
        {
            g_AIPrompts.Delete(name)
            removedCount++
        }
    }
    
    if (removedCount > 0) {
        SavePreferencesToFile()
        Gui, ManagePrompts:Destroy
        ManageAIPrompts()
    }
}

AISettings() {
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    
    ; Get active monitor
    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount% {
        SysGet, monArea, Monitor, %A_Index%
        if (mouseX >= monAreaLeft && mouseX <= monAreaRight && mouseY >= monAreaTop && mouseY <= monAreaBottom) {
            activeMonitor := A_Index
            break
        }
    }
    
    ; Get monitor work area
    SysGet, workArea, MonitorWorkArea, %activeMonitor%
    
    ; Calculate GUI position
    guiWidth := 400
    guiHeight := 200
    xPos := mouseX + 10
    yPos := mouseY + 10
    
    ; Ensure GUI stays on screen
    if (xPos + guiWidth > workAreaRight)
        xPos := workAreaRight - guiWidth
    if (yPos + guiHeight > workAreaBottom)
        yPos := workAreaBottom - guiHeight
    
    ; Create GUI with better spacing and organization
    ;Gui, AISettings:New, +AlwaysOnTop
    
    ; Add a header
    ; Gui, AISettings:Font, s12 bold
    Gui, AISettings:Add, Text, x20 y20 w360 h30, AI Assistant Settings
    
    ; Reset font for rest of controls
    ;Gui, AISettings:Font, s10 normal
    
    ; Add section for AI selection
    ; , AISettings:Add, GroupBox, x20 y60 w360 h70, AI Service Selection
    Gui, AISettings:Add, Text, x35 y85, Select your preferred AI service:
    Gui, AISettings:Add, DropDownList, x35 y105 w330 vg_PreferredAI, claude||chatgpt
    GuiControl, Choose, g_PreferredAI, %g_PreferredAI%
    
    ; Add buttons with proper spacing and grouping
    Gui, AISettings:Add, Button, x20 y150 w110 h30 gRestoreAIDefaults, Restore Prompts
    Gui, AISettings:Add, Button, x240 y150 w70 h30 gSaveAISettings, Save
    Gui, AISettings:Add, Button, x310 y150 w70 h30 gAISettingsGuiClose, Cancel
    
    ; Show the GUI
    Gui, AISettings:Show, x%xPos% y%yPos% w%guiWidth% h%guiHeight%, AI Assistant Settings
}

SaveAISettings() {
    Gui, AISettings:Submit, NoHide
    SavePreferencesToFile()
    Gui, AISettings:Destroy
}

RestoreAIDefaults() {
    global g_AIPrompts, DEFAULT_PROMPTS
    
    MsgBox, 4, Confirm Restore, Warning: This will delete all your current prompts and restore the default prompts. Continue?
    IfMsgBox No
        return
        
    ; Clear existing prompts and copy defaults
    g_AIPrompts := {}
    for name, data in DEFAULT_PROMPTS {
        g_AIPrompts[name] := {prompt: data.prompt, uses: 0}
    }
    
    SavePreferencesToFile()
    CreateAIAssistantMenu()
    
    MsgBox, Default prompts have been restored.
}

ExecuteAIPrompt(ItemName) {
    if (!g_AIPrompts.HasKey(ItemName))
        return
    
    
    selectedText := g_SelectedText
    if (!selectedText) {
        MsgBox, No text selected.
        return
    }
    
    promptData := g_AIPrompts[ItemName]
    promptText := promptData.prompt
	
	; First update the clipboard with the new content
    Clipboard := promptText . "`n`n" . SanitizePHI(selectedText)
	; ShowResult(promptText . "`n`n" . SanitizePHI(selectedText)) ; debug
    ClipWait, 2  ; Wait for the clipboard to be ready

	MsgBox, 4, Warning, IMPORTANT: Do not send protected health information (PHI) to external AI services. Continue?
    IfMsgBox No
        return
    
    if (g_PreferredAI = "claude") {
        Run, https://claude.ai
        Sleep, 4000  ; Wait for Claude to load
        Send, ^v  ; Paste into input box
        Send, {Enter}  ; Send the message
    } else {
        Run, https://chat.openai.com
        Sleep, 4000  ; Wait for ChatGPT to load
        Send, ^v  ; Paste into input box
        Send, {Enter}  ; Send the message
    }
       
    ; Increment usage counter
    promptData.uses += 1
    SavePreferencesToFile()
}

; Add these new functions to your script
EditSelectedPrompt() {
    row := LV_GetNext(0)
    if (!row) {
        MsgBox, Please select a prompt to edit.
        return
    }

    ; Get the current prompt data
    LV_GetText(originalName, row, 1)
    LV_GetText(originalPrompt, row, 2)
    LV_GetText(usageCount, row, 3)

    ; Store original name for later comparison
    g_OriginalPromptName := originalName

    ; Get the current GUI position
    Gui, ManagePrompts:+LastFound
    WinGetPos, currentX, currentY, currentW, currentH

    ; Calculate position for edit window
    editWidth := 400
    editHeight := 200
    editX := currentX + (currentW - editWidth) / 2
    editY := currentY + (currentH - editHeight) / 2

    ; Create edit GUI
    Gui, EditPrompt:New, +AlwaysOnTop
    Gui, EditPrompt:Add, Text,, Prompt Name:
    Gui, EditPrompt:Add, Edit, vvPromptName w380, %originalName%
    Gui, EditPrompt:Add, Text,, Prompt Text:
    Gui, EditPrompt:Add, Edit, vvPromptText w380 h80, %originalPrompt%
    Gui, EditPrompt:Add, Button, gSaveEditedPrompt w90, Save
    Gui, EditPrompt:Add, Button, x+10 w90 gEditPromptGuiClose, Cancel
    Gui, EditPrompt:Show, x%editX% y%editY% w%editWidth% h%editHeight%, Edit AI Prompt
}

SaveEditedPrompt() {
    global vPromptName, vPromptText, g_AIPrompts, g_OriginalPromptName
    Gui, EditPrompt:Submit, NoHide

    if (vPromptName = "" || vPromptText = "") {
        MsgBox, Please fill in both fields.
        return
    }

    ; Get the usage count from the original prompt
    originalUsage := g_AIPrompts[g_OriginalPromptName].uses

    ; If name changed, delete the old prompt
    if (vPromptName != g_OriginalPromptName) {
        g_AIPrompts.Delete(g_OriginalPromptName)
    }

    ; Save the edited prompt with original usage count
    g_AIPrompts[vPromptName] := {prompt: vPromptText, uses: originalUsage}
    
    SavePreferencesToFile()
    Gui, EditPrompt:Destroy
    
    ; Refresh the manage prompts window
    Gui, ManagePrompts:Destroy
    ManageAIPrompts()
}

SanitizePHI(text) {
    ; 1. Names with labels 
	text := RegExReplace(text, "i)(?:name|patient):\s*[a-zA-Z][a-z]+(?:\s+[a-zA-Z]\.?)?\s+[a-zA-Z][a-z\-']+\b", "Name: [NAME]")
	text := RegExReplace(text, "i)(?<![\w'])\b(?:mr|dr|mrs|ms|miss|rev|hon|prof)(?:\.|\b)\s+[a-zA-Z][a-z\-']+(?:\s+[a-zA-Z][a-z\-']+)?\b", "[NAME]")

	; 2. Standalone names at start of lines/sections
	text := RegExReplace(text, "mi)^(?!(?:MRN|ACC|INDICATIONS|TECHNIQUE|COMPARISON|FINDINGS|IMPRESSION|HISTORY|EXAM|CLINICAL)\b)[a-zA-Z][a-z]+(?:\s+[a-zA-Z]\.?)?\s+[a-zA-Z][a-z]+(?:\s*$|\R)", "[NAME]")
	text := RegExReplace(text, "mi)^(?!(?:MRN|ACC|CT|MRI)\b)[a-zA-Z][a-z]+,\s+[a-zA-Z][a-z]+(?:\s*$|\R)", "[NAME]")

	; 3. Names before medical report headers
	text := RegExReplace(text, "mi)^(?!(?:MRN|ACC|CT|MRI)\b)[a-zA-Z][a-z]+(?:\s+[a-zA-Z]\.?)?\s+[a-zA-Z][a-z\-']+(?=\R+(?:MRI|CT|CLINICAL|TECHNIQUE|FINDINGS|IMPRESSION|HISTORY|EXAM)\b)", "[NAME]")

	; 4. Relative names
	text := RegExReplace(text, "i)(?:Father|Mother|Brother|Sister|Son|Daughter|Wife|Husband|Spouse)'s?\s+(?:name|history):\s*[a-zA-Z][a-z]+\s+[a-zA-Z][a-z\-']+\b", "[RELATIVE]")
    
    ; 2. Geographic Subdivisions
    text := RegExReplace(text, "\b(?:AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\b(?=\s+\d{5})", "[STATE]")  ; State abbreviations
    text := RegExReplace(text, "\b\d{5}(?:-\d{4})?\b", "[ZIP]")  ; ZIP codes
    text := RegExReplace(text, "\b[A-Z][a-z\.]+(?: County| Parish| Borough)\b", "[COUNTY]")  ; Counties
    text := RegExReplace(text, "\b\d{1,5}\s+[A-Za-z0-9\s\-\.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Way|Court|Ct|Circle|Cir|Trail|Trl|Highway|Hwy|Route|Rte|Plaza|Pl|Square|Sq|Terrace|Ter|Parkway|Pkwy|Commons|Point|Pt)\b(?:,?\s+(?:Apt|Suite|Ste|Room|Rm|Unit)\s+[-A-Z0-9]+)?", "[ADDRESS]")  ; Street addresses with units
    text := RegExReplace(text, "\b(?:North|South|East|West|N|S|E|W)\s+[A-Z][a-z\.]+(?: Street| St| Avenue| Ave| Road| Rd)\b", "[ADDRESS]")  ; Directional streets

    ; 3. Dates
    ; text := RegExReplace(text, "(?<!\d\s)(?:\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|\d{4}[-/]\d{1,2}[-/]\d{1,2})", "[DATE]")  ; All date formats
    ; text := RegExReplace(text, "(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4}", "[DATE]")  ; Written dates
    ; text := RegExReplace(text, "i)DOB:?\s*.*?(?=\s|$)", "DOB: [DOB]")  ; Date of birth variations
    
    ; 4. Telephone Numbers
    text := RegExReplace(text, "(?:Tel|Telephone|Phone|Mobile|Cell|Home|Work|Fax)(?:\s*#|\s*:|\s+)\s*(?:\+\d{1,2}\s*)?(?:\(?\d{3}\)?[-\.\s]?)?\d{3}[-\.\s]?\d{4}", "[PHONE]")  ; Phone numbers with labels
    text := RegExReplace(text, "\b(?:\+\d{1,2}\s*)?(?:\(?\d{3}\)?[-\.\s]?)?\d{3}[-\.\s]?\d{4}\b", "[PHONE]")  ; Generic phone numbers
    text := RegExReplace(text, "Extension\s*:?\s*\d+", "[EXT]")  ; Extensions
    
    ; 5. Fax Numbers
    ; text := RegExReplace(text, "(?:Fax|Facsimile)(?:\s*#|\s*:|\s+)\s*(?:\+\d{1,2}\s*)?(?:\(?\d{3}\)?[-\.\s]?)?\d{3}[-\.\s]?\d{4}", "[FAX]")  ; Fax numbers
    
    ; 6. Email Addresses
    text := RegExReplace(text, "\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", "[EMAIL]")  ; Email addresses
    
    ; 7. Social Security Numbers
    text := RegExReplace(text, "(?:SSN|SIN|Social Security)(?:\s*#|\s*:|\s+)\s*\d{3}[-\s]?\d{2}[-\s]?\d{4}", "[SSN]")  ; SSN with labels
    text := RegExReplace(text, "\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b(?!\s*(?:mm|cm|tesla))", "[SSN]")  ; Generic SSN pattern (avoiding measurements)
    
    ; 8. Medical Record Numbers and Accession Numbers
    text := RegExReplace(text, "i)(?:MRN|Medical Record Number|Medical Record|Record Number|Chart Number|Patient ID)(?:\s*#|\s*:|\s*Number:|\s+)\s*[A-Za-z0-9\-]+", "[MRN]")  ; Medical record numbers
    text := RegExReplace(text, "i)(?:ACC(?:ESSION)?|Accession Number)(?:\s*#|\s*:|\s*Number:|\s+)\s*[A-Za-z0-9\-]+", "[ACC]")  ; Accession numbers with letters
    text := RegExReplace(text, "i)(?:ACC|Accession):\s*\d+[A-Za-z0-9\-]*", "[ACC]")  ; Additional accession pattern
    
    ; 9. Health Plan Numbers
    text := RegExReplace(text, "i)(?:Health Plan|Insurance|Policy|Group|Member|Coverage)(?:\s*#|\s*:|\s*ID:?|\s+)\s*[A-Za-z0-9\-\._/\\]+", "[INSURANCE]")  ; Insurance IDs
    text := RegExReplace(text, "i)Insurance:?\s*[A-Za-z0-9\-\._/\\]+", "[INSURANCE]")  ; Additional insurance pattern
    
    ; 10. Account Numbers
    text := RegExReplace(text, "i)(?:Account|Acct|Order|Reference|Visit|Encounter)(?:\s*#|\s*:|\s*ID:?|\s+)\s*[A-Za-z0-9\-\._/\\]+", "[ACCOUNT]")  ; Account numbers
    text := RegExReplace(text, "i)(?:Account|Acct):?\s*[A-Za-z0-9\-\._/\\]+", "[ACCOUNT]")  ; Additional account pattern
    
    ; 11. Certificate/License Numbers
    text := RegExReplace(text, "i)(?:Certificate|License|Registration|Certification|Reg|ID)(?:\s*#|\s*:|\s*ID:?|\s+)\s*[A-Za-z0-9\-\._/\\]+", "[LICENSE]")  ; License numbers
    text := RegExReplace(text, "i)(?:License|Cert):?\s*[A-Za-z0-9\-\._/\\]+", "[LICENSE]")  ; Additional license pattern
    
    ; 12. Vehicle Identifiers
    ; text := RegExReplace(text, "i)\b[A-Za-z0-9]{17}\b", "[VIN]")  ; VINs (includes letters)
    ; text := RegExReplace(text, "i)(?:Vehicle|Car|Auto|License|Tag)(?:\s*#|\s*:|\s*ID:?|\s+)\s*[A-Za-z0-9\-\._/\\]+", "[VEHICLE]")  ; Removed "Plate" from this group
	; text := RegExReplace(text, "i)(?:Plate\s*#|Plate\s*:|Plate\s*ID:?|\bPlate\s+)[A-Za-z0-9\-\._/\\]+", "[VEHICLE]")  ; Separate pattern for "Plate" with identifiers
    ; text := RegExReplace(text, "i)(?:VIN|Vehicle):?\s*[A-Za-z0-9\-\._/\\]+", "[VEHICLE]")  ; Additional vehicle pattern
    
    ; 13. Device Identifiers
    text := RegExReplace(text, "i)(?:Device|Serial|Model|Equipment|Unit|Product)(?:\s*#|\s*:|\s*ID:?|\s+)\s*[A-Za-z0-9\-\._/\\]+", "[DEVICE]")  ; Device IDs
    text := RegExReplace(text, "i)(?:Serial|Model):?\s*[A-Za-z0-9\-\._/\\]+", "[DEVICE]")  ; Additional device pattern
    
    ; 14. Web URLs
    ; text := RegExReplace(text, "https?://[^\s<>""]+", "[URL]")  ; URLs
    
    ; 15. IP Addresses
    text := RegExReplace(text, "\b(?:\d{1,3}\.){3}\d{1,3}\b", "[IP]")  ; IPv4 addresses
    text := RegExReplace(text, "\b(?:[A-F0-9]{1,4}:){7}[A-F0-9]{1,4}\b", "[IP]")  ; IPv6 addresses
    
    ; 16. Biometric Identifiers
    ; text := RegExReplace(text, "(?:Fingerprint|Retinal|Iris|Face|Voice)(?:\s*Scan|\s*Image|\s*Print|\s*ID)(?:\s*#|\s*:|\s+)\s*[A-Z0-9\-]+", "[BIOMETRIC]")  ; Biometric data
    
    ; 17. Photographic Images
    ; text := RegExReplace(text, "(?:Photo|Image|Picture|Portrait)(?:\s*#|\s*:|\s+)\s*[A-Z0-9\-]+", "[PHOTO]")  ; Photo references
    
    ; 18. Any other unique identifying number, characteristic, or code
    text := RegExReplace(text, "\b\d{6,}\b(?!\s*(?:mm|cm|tesla))", "[ID]")  ; Long number sequences (avoiding measurements)
    
    ; Age Information (while preserving clinical duration references)
    text := RegExReplace(text, "i)Age:\s*\d+", "Age: [AGE]")  ; Age with label
    text := RegExReplace(text, "\b(?:age[d]?\s*:?\s*|)\d{1,3}\s*(?:years?|yrs?|y\.?o\.?|months?|mos?)\s*(?:old|of?\s*age)\b", "[AGE]")  ; Age variations
    
    ; Provider Names & Facility Information (if not already part of public record)
    text := RegExReplace(text, "(?:Dr\.|Doctor|Provider|Physician)\s+[A-Z][a-z\-']+(?:\s+[A-Z][a-z\-']+)?", "[PROVIDER]")  ; Provider names
    
    return text
}

; Add these labels to your existing GUI labels section
EditPromptGuiClose:
    Gui, EditPrompt:Destroy
return
RestoreAIDefaults:
    RestoreAIDefaults()
return
AddPromptGuiClose:
ManagePromptsGuiClose:
AISettingsGuiClose:
    Gui, Destroy
return

PromptListHandler:
return

; ------------------------------------------
; End of Script
; ------------------------------------------
ExitApp

; ============================================================
; QuickCall (embedded) - floating always-on-top Google Voice call panel
; Same code as QuickCall_v1.ahk, built in so this script is self-contained.
; Must stay after ExitApp: it has no auto-execute code; QC_Enable() starts it.
; Toggle: right-click > Preferences > Quick Call Panel (Ctrl+Alt+P)
; ============================================================

; >>> QUICKCALL BEGIN (generated from QuickCall_v1.ahk - edit there, then re-embed) >>>
; ================= SETTINGS (values are set in QC_Init) =================
global QC_RadName, QC_IncludeReadBack, QC_OpenAtStart, QC_DialMode, QC_GVAccount
global QC_AutoConfirm, QC_ConfirmDelayMs
global QC_BookFile, QC_IniFile, QC_TickMs

; ================= STATE =================
global QC_Initialized := false, QC_Enabled := false
global QC_Entries, QC_BtnMap, QC_Expanded, QC_LastCall, QC_DialogOpen
global QC_X, QC_Y, QC_LastExtWin, QC_Pid, QC_PanelHwnd, QC_EditorHwnd
global QC_CtxEntry, QC_Work
global QC_EdLV, QC_EdSec, QC_EdLab, QC_EdNum      ; editor GUI control variables
global QC_Collapsed, QC_W, QC_H, QC_CW, QC_CH       ; panel size / collapse state
global QC_CMain, QC_CHeads, QC_CCols, QC_CBottom, QC_CTechs, QC_CToggle, QC_CHint, QC_NMain, QC_MaxRows

; ================= STANDALONE =================
; Only reached when this file is run directly (when #Included it is after ExitApp)
#SingleInstance, Force      ; same setting the host script already uses
if (A_LineFile = A_ScriptFullPath)
    QC_Enable()
return

; ================= HOTKEYS =================
; Active only while Quick Call is enabled; otherwise the keys pass through.
#If QC_Enabled
^!p::QC_TogglePanel()       ; Ctrl+Alt+P  show / hide panel
^!d::QC_DialSelection()     ; Ctrl+Alt+D  dial highlighted number
^!l::QC_LogCall()           ; Ctrl+Alt+L  paste critical-result statement
#If

; ================= ENABLE / DISABLE =================
QC_Init() {
    if (QC_Initialized)
        return
    QC_Initialized := true

    ; ---- user settings ----
    QC_OpenAtStart     := true      ; open the panel when the script starts
    QC_DialMode        := "url"     ; "url" = Google Voice on this computer | "cell" = Google Voice rings your cell
                                    ; "teams" = Microsoft Teams | "tel" = tel: link
                                    ; (also switchable by right-clicking a panel button; the choice is saved)
    QC_GVAccount       := 0         ; Google account index if signed into several
    QC_AutoConfirm     := true      ; auto-press Call on Google Voice's "Call?" prompt
    QC_ConfirmDelayMs  := 1500      ; ms to let the Voice page load before confirming
    QC_RadName         := "Dr. Harwood"
    QC_IncludeReadBack := true
    QC_TickMs          := 500       ; how often the panel checks it is still on top
    QC_BookFile := A_ScriptDir "\QuickCall_PhoneBook.txt"
    QC_IniFile  := A_ScriptDir "\QuickCall_Settings.ini"

    ; ---- state ----
    QC_Entries := [], QC_BtnMap := {}, QC_Expanded := false, QC_LastCall := ""
    QC_DialogOpen := 0, QC_X := "", QC_Y := "", QC_LastExtWin := 0
    QC_PanelHwnd := 0, QC_EditorHwnd := 0, QC_Work := []
    QC_Pid := DllCall("GetCurrentProcessId")

    QC_LoadBook()
    IniRead, QC_X, %QC_IniFile%, Panel, X, %A_Space%
    IniRead, QC_Y, %QC_IniFile%, Panel, Y, %A_Space%
    IniRead, exp, %QC_IniFile%, Panel, Expanded, 0
    QC_Expanded := (exp = "1")
    IniRead, QC_W, %QC_IniFile%, Panel, W, %A_Space%
    IniRead, QC_H, %QC_IniFile%, Panel, H, %A_Space%
    IniRead, col, %QC_IniFile%, Panel, Collapsed, 0
    QC_Collapsed := (col = "1")
    IniRead, dm, %QC_IniFile%, Settings, DialMode, %A_Space%
    if RegExMatch(dm, "^(url|cell|teams|tel)$")
        QC_DialMode := dm
    QC_CW := 0, QC_CH := 0
    OnExit("QC_OnExit")
    OnMessage(0xA3, "QC_OnDblClick")      ; double-click title bar
    OnMessage(0x203, "QC_OnDblClick")     ; double-click header strip
}

; showPanel: -1 = follow QC_OpenAtStart, 0 = don't open, 1 = open now
QC_Enable(showPanel := -1) {
    QC_Init()
    if (!QC_Enabled) {
        QC_Enabled := true
        QC_SetTray(true)
        SetTimer, QC_Tick, %QC_TickMs%
    }
    if (showPanel = 1)
        QC_ShowPanel(true)
    else if (showPanel = -1 && QC_OpenAtStart)
        QC_ShowPanel(false)     ; at startup: don't steal focus from PowerScribe
}

QC_Disable() {
    if (!QC_Enabled)
        return
    QC_Enabled := false
    SetTimer, QC_Tick, Off
    QC_SetTray(false)
    QC_EdClose()
    if (QC_PanelHwnd) {
        QC_SavePos()
        Gui, QCPanel:Destroy
        QC_PanelHwnd := 0
    }
}

; Called by the host script after Preferences are saved
QC_ApplyEnabled(on) {
    if (on && !QC_Enabled)
        QC_Enable(1)
    else if (!on && QC_Enabled)
        QC_Disable()
}

QC_SetTray(add) {
    try Menu, Tray, Delete, Quick Call panel
    try Menu, Tray, Delete, Edit phone numbers
    if (!add)
        return
    Menu, Tray, Add, Quick Call panel, QC_MenuShow
    Menu, Tray, Add, Edit phone numbers, QC_MenuEditor
}

; Menu callbacks (Menu passes ItemName, ItemPos, MenuName)
QC_MenuShow(p1 := "", p2 := "", p3 := "") {
    QC_ShowPanel(true)
}
QC_MenuEditor(p1 := "", p2 := "", p3 := "") {
    QC_ShowEditor()
}

; ================= PHONE BOOK FILE =================
QC_DefaultBook() {
    t := "
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
    return t
}

QC_LoadBook() {
    if !FileExist(QC_BookFile)
        FileAppend, % QC_DefaultBook() "`n", %QC_BookFile%, UTF-8
    QC_Entries := []
    FileRead, txt, *P65001 %QC_BookFile%
    Loop, Parse, txt, `n, `r
    {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        p := StrSplit(line, "|")
        if (p.Length() < 2)
            continue
        QC_Entries.Push({sec: Trim(p[1]), label: Trim(p[2]), num: (p.Length() >= 3 ? Trim(p[3]) : "")})
    }
}

; Writes to a temp file first so a OneDrive sync lock can't wipe the phone book
QC_SaveBook() {
    txt := "; QuickCall phone book. One contact per line: Group|Label|Number`n"
    txt .= "; Group Main = big buttons at the top. Any other group = a tech column.`n"
    for i, e in QC_Entries
        txt .= e.sec "|" e.label "|" e.num "`n"
    tmp := QC_BookFile ".tmp"
    FileDelete, %tmp%
    FileAppend, %txt%, %tmp%, UTF-8
    if (ErrorLevel) {
        MsgBox, 262192, Quick Call, Could not save the phone book (file locked by OneDrive?). Try again in a moment.
        return
    }
    FileMove, %tmp%, %QC_BookFile%, 1
    if (ErrorLevel)
        MsgBox, 262192, Quick Call, Could not replace QuickCall_PhoneBook.txt (file locked by OneDrive?). Your changes are in QuickCall_PhoneBook.txt.tmp
}

QC_Groups() {
    main := [], secs := [], grp := {}
    for i, e in QC_Entries {
        if (e.sec = "Main") {
            main.Push(e)
            continue
        }
        if !grp.HasKey(e.sec) {
            grp[e.sec] := []
            secs.Push(e.sec)
        }
        grp[e.sec].Push(e)
    }
    return {main: main, secs: secs, grp: grp}
}

QC_Full(e) {
    return (e.sec = "Main") ? e.label : e.sec " " e.label
}

QC_IsValidNum(v) {
    d := RegExReplace(v, "\D")
    return StrLen(d) = 10 || (StrLen(d) = 11 && SubStr(d, 1, 1) = "1")
}

; ================= PANEL =================
; Layout: [+/-] collapse button on top, main numbers (2 columns), "+ Techs" toggle,
; optional tech columns, then Dial / Log / Edit. The window can be resized:
; buttons stretch to the new width and button heights scale to the new height.
QC_BuildPanel(activate := true) {
    prevGui := A_DefaultGui
    if (QC_PanelHwnd) {
        QC_SavePos()
        Gui, QCPanel:Destroy
        QC_PanelHwnd := 0
    }
    QC_BtnMap := {}, QC_CMain := [], QC_CHeads := [], QC_CCols := [], QC_CBottom := []
    grps := QC_Groups()
    QC_NMain := grps.main.Length(), QC_MaxRows := 0

    ; +ToolWindow = floating panel with no taskbar button; Esc / X hide it and it
    ; comes back with Ctrl+Alt+P, the right-click menu, or the tray menu.
    Gui, QCPanel:New, +AlwaysOnTop +ToolWindow +Resize -MaximizeBox -MinimizeBox +MinSize150x40 +HwndhPanel +LabelQC_Panel_, Quick Call
    Gui, QCPanel:Color, 202020
    Gui, QCPanel:Font, s12 bold, Segoe UI
    Gui, QCPanel:Add, Button, x8 y6 w30 h26 gQC_BtnCollapse HwndhT, % (QC_Collapsed ? "+" : "-")
    QC_CToggle := hT
    Gui, QCPanel:Font, s9 norm c9FC5E8
    Gui, QCPanel:Add, Text, x46 y12 w220 h18 BackgroundTrans gQC_HintClick HwndhH, % (QC_Collapsed ? "Quick Call" : "Click a name to call   Ctrl+Alt+P hide")
    QC_CHint := hH

    Gui, QCPanel:Font, s11 norm cDefault
    for i, e in grps.main {
        txt := i "   " e.label (e.num = "" ? " (add #)" : "")
        Gui, QCPanel:Add, Button, x0 y0 w10 h10 gQC_BtnClick HwndhB, % txt
        QC_BtnMap[hB + 0] := e
        QC_CMain.Push(hB)
    }
    Gui, QCPanel:Font, s10
    Gui, QCPanel:Add, Button, x0 y0 w10 h10 gQC_BtnTechs HwndhTechs, % (QC_Expanded ? "-   Techs" : "+   Techs")
    QC_CTechs := hTechs
    if (QC_Expanded) {
        for k, sec in grps.secs {
            Gui, QCPanel:Font, s10 bold c9FC5E8
            Gui, QCPanel:Add, Text, x0 y0 w10 h10 BackgroundTrans HwndhHd, % sec
            QC_CHeads.Push(hHd)
            Gui, QCPanel:Font, s9 norm cDefault
            col := []
            for j, e in grps.grp[sec] {
                txt := e.label (e.num = "" ? " (add #)" : "")
                Gui, QCPanel:Add, Button, x0 y0 w10 h10 gQC_BtnClick HwndhB, % txt
                QC_BtnMap[hB + 0] := e
                col.Push(hB)
            }
            QC_CCols.Push(col)
            QC_MaxRows := Max(QC_MaxRows, col.Length())
        }
    }
    Gui, QCPanel:Font, s9 norm cDefault
    Gui, QCPanel:Add, Button, x0 y0 w10 h10 gQC_BtnManual HwndhB1, Dial #...
    Gui, QCPanel:Add, Button, x0 y0 w10 h10 gQC_BtnLog HwndhB2, Log call
    Gui, QCPanel:Add, Button, x0 y0 w10 h10 gQC_BtnEdit HwndhB3, Edit #s
    QC_CBottom := [hB1, hB2, hB3]

    QC_PanelHwnd := hPanel
    w := (QC_IsNum(QC_W) && QC_W >= 150) ? QC_W : QC_DefaultW()
    nat := QC_NaturalH()
    h := (QC_IsNum(QC_H) && QC_H >= nat * 0.55) ? QC_H : nat
    if (QC_Collapsed) {
        QC_SetBodyVisible(false)
        w := QC_CollapsedW(), h := QC_CollapsedH()
        QC_MoveCtl(QC_CHint, 46, 12, w - 52, 18)
    } else {
        QC_Layout(w, h)
    }
    QC_CW := w, QC_CH := h
    showOpt := (activate ? "" : "NoActivate ") "w" w " h" h
    if QC_ValidPos(QC_X, QC_Y)
        showOpt .= " x" QC_X " y" QC_Y
    Gui, QCPanel:Show, %showOpt%
    QC_FitOnScreen()
    QC_RaiseTop(hPanel)
    Gui, %prevGui%:Default
}

QC_IsNum(v) {
    if v is number
        return true
    return false
}

; Keep the whole panel on its monitor: move it up, or shrink it if taller than the screen
QC_FitOnScreen() {
    WinGetPos, x, y, w, ht, ahk_id %QC_PanelHwnd%
    if (x = "")
        return
    cx := x + w // 2, cy := y + 10
    l := 0, t := 0, r := A_ScreenWidth, b := A_ScreenHeight
    SysGet, cnt, MonitorCount
    Loop, %cnt% {
        SysGet, m, MonitorWorkArea, %A_Index%
        if (cx >= mLeft && cx < mRight && cy >= mTop && cy < mBottom)
            l := mLeft, t := mTop, r := mRight, b := mBottom
    }
    nh := Min(ht, b - t), ny := Max(t, Min(y, b - nh)), nx := Max(l, Min(x, r - w))
    if (nh != ht || ny != y || nx != x)
        WinMove, ahk_id %QC_PanelHwnd%, , %nx%, %ny%, , %nh%
}

QC_DefaultW() {
    n := QC_Expanded ? QC_CCols.Length() : 0
    return Max(2 * 150 + 8 + 20, n * 158 - 8 + 20)
}

QC_CollapsedH() {
    return 38
}

QC_CollapsedW() {      ; collapsed = small rectangle: [+] and "Quick Call"
    return 175
}

; Double-click on the panel's title bar (or its empty header strip) collapses/expands it
QC_OnDblClick(wParam, lParam, msg, hwnd) {
    if (!QC_PanelHwnd || hwnd != QC_PanelHwnd)
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

; Double-click on the header text
QC_HintClick(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    if (GuiEvent = "DoubleClick")
        QC_ToggleCollapse()
}

; Height when nothing is stretched (fixed gaps + natural button heights)
QC_NaturalH() {
    f := QC_HeightParts()
    return Round(f.fixed + f.scalable)
}

QC_HeightParts() {
    rows := Ceil(QC_NMain / 2)
    fixed := 40 + (rows > 0 ? (rows - 1) * 8 + 12 : 0) + 10 + 10
    scalable := rows * 42 + 30 + 28
    if (QC_Expanded && QC_CCols.Length()) {
        fixed += 10 + 22 + (QC_MaxRows - 1) * 4
        scalable += QC_MaxRows * 28
    }
    return {fixed: fixed, scalable: scalable}
}

QC_MoveCtl(hwnd, x, y, w, h) {
    GuiControl, QCPanel:Move, %hwnd%, % "x" Round(x) " y" Round(y) " w" Round(w) " h" Round(h)
}

QC_Layout(w, h) {
    if (!QC_PanelHwnd || !IsObject(QC_CMain))
        return
    M := 10, G := 8
    f := QC_HeightParts()
    s := (h - f.fixed) / f.scalable
    s := Max(0.55, Min(3, s))
    inner := Max(60, w - 2 * M)
    QC_MoveCtl(QC_CHint, 46, 12, Max(10, w - 52), 18)

    y := 40
    bw := Floor((inner - G) / 2), mh := Round(42 * s)
    for i, hb in QC_CMain {
        col := Mod(i - 1, 2), row := (i - 1) // 2
        QC_MoveCtl(hb, M + col * (bw + G), y + row * (mh + G), bw, mh)
    }
    rows := Ceil(QC_NMain / 2)
    if (rows)
        y += rows * mh + (rows - 1) * G + 12
    th := Round(30 * s)
    QC_MoveCtl(QC_CTechs, M, y, inner, th)
    y += th
    if (QC_Expanded && QC_CCols.Length()) {
        n := QC_CCols.Length()
        cw := Floor((inner - (n - 1) * G) / n)
        rh := Round(28 * s)
        y += 10
        for k, col in QC_CCols {
            x := M + (k - 1) * (cw + G)
            QC_MoveCtl(QC_CHeads[k], x, y, cw, 20)
            for j, hb in col
                QC_MoveCtl(hb, x, y + 22 + (j - 1) * (rh + 4), cw, rh)
        }
        y += 22 + QC_MaxRows * rh + (QC_MaxRows - 1) * 4
    }
    y += 10
    w3 := Floor((inner - 2 * G) / 3), bh := Round(28 * s)
    for i, hb in QC_CBottom
        QC_MoveCtl(hb, M + (i - 1) * (w3 + G), y, w3, bh)
    DllCall("RedrawWindow", "Ptr", QC_PanelHwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
}

QC_SetBodyVisible(v) {
    cmd := v ? "Show" : "Hide"
    all := []
    for i, hb in QC_CMain
        all.Push(hb)
    all.Push(QC_CTechs)
    for i, hb in QC_CHeads
        all.Push(hb)
    for i, col in QC_CCols
        for j, hb in col
            all.Push(hb)
    for i, hb in QC_CBottom
        all.Push(hb)
    for i, hb in all
        GuiControl, QCPanel:%cmd%, %hb%
}

; Size event (named by +LabelQC_Panel_)
QC_Panel_Size(GuiHwnd := 0, EventInfo := 0, Width := 0, Height := 0) {
    if (EventInfo = 1 || !QC_PanelHwnd)    ; minimized
        return
    QC_CW := Width, QC_CH := Height
    if (QC_Collapsed) {
        QC_MoveCtl(QC_CHint, 46, 12, Max(10, Width - 52), 18)
        return
    }
    QC_W := Width, QC_H := Height
    QC_Layout(Width, Height)
}

; The [+/-] button or a double-click on the header: collapse to a small rectangle, or expand
QC_ToggleCollapse() {
    cw := QC_CW, ch := QC_CH
    if (!QC_Collapsed)
        QC_W := cw, QC_H := ch
    QC_Collapsed := !QC_Collapsed
    IniWrite, % (QC_Collapsed ? 1 : 0), %QC_IniFile%, Panel, Collapsed
    GuiControl, QCPanel:, %QC_CToggle%, % (QC_Collapsed ? "+" : "-")
    GuiControl, QCPanel:, %QC_CHint%, % (QC_Collapsed ? "Quick Call" : "Click a name to call   Ctrl+Alt+P hide")
    if (QC_Collapsed) {
        QC_SetBodyVisible(false)
        w := QC_CollapsedW(), h := QC_CollapsedH()
        QC_MoveCtl(QC_CHint, 46, 12, w - 52, 18)
        Gui, QCPanel:Show, NoActivate w%w% h%h%
    } else {
        w := (QC_IsNum(QC_W) && QC_W >= 150) ? QC_W : QC_DefaultW()
        h := (QC_IsNum(QC_H) && QC_H > QC_CollapsedH() + 20) ? QC_H : QC_NaturalH()
        QC_Layout(w, h)
        QC_SetBodyVisible(true)
        Gui, QCPanel:Show, NoActivate w%w% h%h%
        QC_FitOnScreen()
    }
    QC_SavePos()
}

QC_BtnCollapse(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_ToggleCollapse()
}

QC_ShowPanel(activate := true) {
    if (!QC_PanelHwnd) {
        QC_BuildPanel(activate)
        return
    }
    if (activate)
        Gui, QCPanel:Show
    else
        Gui, QCPanel:Show, NoActivate
    QC_RaiseTop(QC_PanelHwnd)
}

QC_TogglePanel() {
    if (!QC_PanelHwnd) {
        QC_BuildPanel(true)
        return
    }
    if !DllCall("IsWindowVisible", "Ptr", QC_PanelHwnd) {
        QC_ShowPanel(true)
    } else {
        QC_SavePos()
        Gui, QCPanel:Hide
    }
}

QC_ToggleTechs() {
    QC_SavePos()
    QC_Expanded := !QC_Expanded
    IniWrite, % (QC_Expanded ? 1 : 0), %QC_IniFile%, Panel, Expanded
    QC_H := ""                                   ; height follows the new content
    if (QC_Expanded && QC_IsNum(QC_W))           ; widen enough for the tech columns
        QC_W := Max(QC_W, QC_Groups().secs.Length() * 120 + 20)
    QC_BuildPanel(true)
    QC_SavePos()
}

; GUI event functions (named by +LabelQC_Panel_)
QC_Panel_Close(GuiHwnd := 0) {
    QC_SavePos()
    Gui, QCPanel:Hide
}
QC_Panel_Escape(GuiHwnd := 0) {
    QC_SavePos()
    Gui, QCPanel:Hide
}

; Button callbacks (g-label functions get CtrlHwnd, GuiEvent, EventInfo, ErrLevel)
QC_BtnClick(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    e := QC_BtnMap[CtrlHwnd + 0]
    if IsObject(e)
        QC_DialEntry(e)
}
QC_BtnTechs(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_ToggleTechs()
}
QC_BtnManual(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_ManualDial()
}
QC_BtnLog(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_LogCall()
}
QC_BtnEdit(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_ShowEditor()
}

QC_SavePos() {
    if (!QC_PanelHwnd)
        return
    if !DllCall("IsWindowVisible", "Ptr", QC_PanelHwnd)
        return
    WinGet, mm, MinMax, ahk_id %QC_PanelHwnd%
    if (mm = -1)
        return
    WinGetPos, x, y, , , ahk_id %QC_PanelHwnd%
    if (x = "")
        return
    QC_X := x, QC_Y := y
    IniWrite, %x%, %QC_IniFile%, Panel, X
    IniWrite, %y%, %QC_IniFile%, Panel, Y
    if (!QC_Collapsed && QC_CW > 0) {
        IniWrite, %QC_CW%, %QC_IniFile%, Panel, W
        IniWrite, %QC_CH%, %QC_IniFile%, Panel, H
    }
}

QC_ValidPos(x, y) {
    if (x = "" || y = "")
        return false
    SysGet, cnt, MonitorCount
    Loop, %cnt% {
        SysGet, m, MonitorWorkArea, %A_Index%
        if (x >= mLeft - 50 && x < mRight - 50 && y >= mTop - 10 && y < mBottom - 50)
            return true
    }
    return false
}

QC_OnExit(ExitReason := "", ExitCode := "") {
    QC_SavePos()
    return 0    ; allow exit
}

; Keeps the panel above Sectra/PowerScribe and remembers the last non-browser window
QC_Tick() {
    static lastObs := 0, lastRaise := 0
    activePid := 0
    WinGet, a, ID, A
    if (a) {
        WinGet, activePid, PID, ahk_id %a%
        if (activePid != QC_Pid) {
            WinGet, pn, ProcessName, ahk_id %a%
            if !RegExMatch(pn, "i)^(chrome|msedge|firefox|brave)\.exe$")
                QC_LastExtWin := a
        }
    }
    if (!QC_PanelHwnd || QC_DialogOpen > 0)
        return
    if !DllCall("IsWindowVisible", "Ptr", QC_PanelHwnd)
        return
    if (activePid = QC_Pid)    ; one of our own windows or menus is active
        return
    ; Only touch the z-order when something is actually wrong: every
    ; SetWindowPos repaints the title bar, which made the close X blink.
    ; 0x13 = NOSIZE|NOMOVE|NOACTIVATE
    WinGet, exStyle, ExStyle, ahk_id %QC_PanelHwnd%
    if !(exStyle & 0x8)    ; lost WS_EX_TOPMOST
        DllCall("SetWindowPos", "Ptr", QC_PanelHwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    ; Sectra / PowerScribe windows that are themselves topmost can still sit
    ; above us; if anything covers the panel, bump it to the top of the band.
    ; If the same window is still on top right after a bump, it is winning the
    ; topmost fight (or is an invisible overlay), so retry only every 10 s.
    obs := QC_IsObscured(QC_PanelHwnd)
    if (!obs) {
        lastObs := 0
    } else if (obs != lastObs || A_TickCount - lastRaise > 10000) {
        QC_RaiseTop(QC_PanelHwnd)
        lastObs := obs, lastRaise := A_TickCount
    }
}

; Move the panel to the very top of the always-on-top band without activating it.
; Toggling NOTOPMOST -> TOPMOST is what lifts it above other topmost windows.
QC_RaiseTop(h) {
    DllCall("SetWindowPos", "Ptr", h, "Ptr", -2, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    DllCall("SetWindowPos", "Ptr", h, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

; True if another application's window is drawn over part of the panel.
; Shell UI (taskbar, Start, Alt+Tab, menus, tooltips) and our own windows are ignored.
QC_IsObscured(h) {
    static shellCls := "i)^(Shell_TrayWnd|Shell_SecondaryTrayWnd|#32768|tooltips_class32|NotifyIconOverflowWindow|TopLevelWindowForOverflowXamlIsland|Windows\.UI\.Core\.CoreWindow|ForegroundStaging|MultitaskingViewFrame|XamlExplorerHostIslandWindow|TaskListThumbnailWnd|Progman|WorkerW)$"
    WinGetPos, x, y, w, hh, ahk_id %h%
    if (x = "")
        return false
    pts := [[x + w // 2, y + hh // 2], [x + 12, y + 12], [x + w - 12, y + 12], [x + 12, y + hh - 12], [x + w - 12, y + hh - 12]]
    for i, p in pts {
        hit := DllCall("WindowFromPoint", "Int64", (p[2] << 32) | (p[1] & 0xFFFFFFFF), "Ptr")
        if (!hit)
            continue
        root := DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr")   ; GA_ROOT
        if (!root || root = h)
            continue
        WinGet, rpid, PID, ahk_id %root%
        if (rpid = "" || rpid = QC_Pid)
            continue
        WinGetClass, cls, ahk_id %root%
        if RegExMatch(cls, shellCls)
            continue
        return root   ; the covering window (truthy)
    }
    return false
}

QC_OwnIfVisible() {
    if (QC_PanelHwnd && DllCall("IsWindowVisible", "Ptr", QC_PanelHwnd))
        Gui, QCPanel:+OwnDialogs
}

; Right-click a button on the panel to edit it
QC_Panel_ContextMenu(GuiHwnd := 0, CtrlHwnd := 0, EventInfo := "", IsRightClick := "", X := "", Y := "") {
    e := QC_BtnMap[CtrlHwnd + 0]
    if !IsObject(e)
        return
    QC_CtxEntry := e
    Menu, QCCtx, Add
    Menu, QCCtx, DeleteAll
    Menu, QCCtx, Add, % "Edit number for " QC_Full(e) "...", QC_CtxEditNum
    Menu, QCCtx, Add, Rename..., QC_CtxRename
    Menu, QCCtx, Add
    Menu, QCCtx, Add, Open phone book editor..., QC_MenuEditor
    Menu, QCCtx, Add
    Menu, QCCtx, Add, Place calls from this computer (Google Voice), QC_CtxModeGV
    Menu, QCCtx, Add, Place calls from my cell phone (Google Voice), QC_CtxModeCell
    Menu, QCCtx, Add, Place calls with Microsoft Teams, QC_CtxModeTeams
    Menu, QCCtx, % (QC_DialMode = "url" ? "Check" : "Uncheck"), Place calls from this computer (Google Voice)
    Menu, QCCtx, % (QC_DialMode = "cell" ? "Check" : "Uncheck"), Place calls from my cell phone (Google Voice)
    Menu, QCCtx, % (QC_DialMode = "teams" ? "Check" : "Uncheck"), Place calls with Microsoft Teams
    Menu, QCCtx, Show
}
QC_CtxEditNum(p1 := "", p2 := "", p3 := "") {
    QC_EditField(QC_CtxEntry, "num")
}
QC_CtxRename(p1 := "", p2 := "", p3 := "") {
    QC_EditField(QC_CtxEntry, "label")
}

QC_EditField(e, field) {
    QC_DialogOpen++
    QC_OwnIfVisible()
    prompt := (field = "num") ? "Phone number for " QC_Full(e) ":" : "New label for " QC_Full(e) ":"
    cur := e[field]
    InputBox, val, Quick Call, % prompt, , 340, 140, , , , , % cur
    cancelled := ErrorLevel
    QC_DialogOpen--
    if (cancelled)
        return
    val := Trim(val)
    if (field = "num" && val != "" && !QC_IsValidNum(val)) {
        MsgBox, 262192, Quick Call, Enter a 10-digit number (e.g. 636-947-5111) or leave it blank.
        return
    }
    if (field = "label" && val = "")
        return
    e[field] := val
    QC_SaveBook()
    QC_BuildPanel(true)
}

; ================= PHONE BOOK EDITOR =================
QC_ShowEditor() {
    if (QC_EditorHwnd) {
        Gui, QCEdit:Show
        return
    }
    prevGui := A_DefaultGui
    QC_Work := []
    groups := "", seen := {}
    for i, e in QC_Entries {
        QC_Work.Push({sec: e.sec, label: e.label, num: e.num})
        if !seen.HasKey(e.sec) {
            seen[e.sec] := 1
            groups .= (groups = "" ? "" : "|") e.sec
        }
    }

    Gui, QCEdit:New, +AlwaysOnTop -MaximizeBox +HwndhEd +LabelQC_Edit_, Quick Call - Edit Phone Book
    Gui, QCEdit:Font, s10, Segoe UI
    Gui, QCEdit:Add, Text, xm, Group Main = big buttons at top. Other groups = tech columns. Type a new group name to add a column.
    Gui, QCEdit:Add, ListView, xm w560 r16 -Multi Grid AltSubmit vQC_EdLV gQC_EdLVEvent, Group|Label|Number
    Gui, QCEdit:Add, Text, xm y+10, Group
    Gui, QCEdit:Add, ComboBox, x+5 yp-3 w100 vQC_EdSec, %groups%
    Gui, QCEdit:Add, Text, x+12 yp+3, Label
    Gui, QCEdit:Add, Edit, x+5 yp-3 w170 vQC_EdLab
    Gui, QCEdit:Add, Text, x+12 yp+3, Number
    Gui, QCEdit:Add, Edit, x+5 yp-3 w130 vQC_EdNum
    Gui, QCEdit:Add, Button, xm y+12 w90 gQC_EdAdd, Add new
    Gui, QCEdit:Add, Button, x+6 yp w90 gQC_EdUpdate, Update
    Gui, QCEdit:Add, Button, x+6 yp w90 gQC_EdDelete, Delete
    Gui, QCEdit:Add, Button, x+6 yp w50 gQC_EdUp, Up
    Gui, QCEdit:Add, Button, x+6 yp w50 gQC_EdDown, Down
    Gui, QCEdit:Add, Button, xm y+16 w130 gQC_EdSave, Save && Close
    Gui, QCEdit:Add, Button, x+6 yp w90 gQC_EdCancel, Cancel

    QC_EditorHwnd := hEd
    QC_DialogOpen++
    QC_EdRefresh()
    Gui, QCEdit:Show
    Gui, %prevGui%:Default
}

QC_EdRefresh(sel := 0) {
    Gui, QCEdit:Default
    Gui, QCEdit:ListView, QC_EdLV
    LV_Delete()
    for i, e in QC_Work
        LV_Add("", e.sec, e.label, e.num)
    LV_ModifyCol(1, 90), LV_ModifyCol(2, 260), LV_ModifyCol(3, 180)
    if (sel > 0 && sel <= QC_Work.Length())
        LV_Modify(sel, "Select Focus Vis")
}

QC_EdSelected() {
    Gui, QCEdit:Default
    Gui, QCEdit:ListView, QC_EdLV
    return LV_GetNext(0)
}

QC_EdLVEvent(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    ; "I" event with a capital S in ErrorLevel = row became selected
    if (GuiEvent == "I" && InStr(ErrLevel, "S", true)) {
        e := QC_Work[EventInfo]
        if !IsObject(e)
            return
        GuiControl, QCEdit:Text, QC_EdSec, % e.sec
        GuiControl, QCEdit:, QC_EdLab, % e.label
        GuiControl, QCEdit:, QC_EdNum, % e.num
    }
}

QC_EdRead() {
    Gui, QCEdit:Submit, NoHide
    Gui, QCEdit:+OwnDialogs
    s := Trim(QC_EdSec), l := Trim(QC_EdLab), n := Trim(QC_EdNum)
    if (s = "" || l = "") {
        MsgBox, 48, Quick Call, Group and Label are required.
        return ""
    }
    if (n != "" && !QC_IsValidNum(n)) {
        MsgBox, 48, Quick Call, Enter a 10-digit number (e.g. 636-947-5111) or leave it blank.
        return ""
    }
    return {sec: s, label: l, num: n}
}

QC_EdAdd(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    f := QC_EdRead()
    if !IsObject(f)
        return
    r := QC_EdSelected()
    if (r = 0) {
        QC_Work.Push(f)
        r := QC_Work.Length()
    } else {
        QC_Work.InsertAt(r + 1, f)
        r := r + 1
    }
    QC_EdRefresh(r)
}

QC_EdUpdate(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    r := QC_EdSelected()
    if (r = 0) {
        Gui, QCEdit:+OwnDialogs
        MsgBox, 0, Quick Call, Select a row to update.
        return
    }
    f := QC_EdRead()
    if !IsObject(f)
        return
    QC_Work[r] := f
    QC_EdRefresh(r)
}

QC_EdDelete(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    r := QC_EdSelected()
    if (r = 0)
        return
    QC_Work.RemoveAt(r)
    QC_EdRefresh(r > QC_Work.Length() ? QC_Work.Length() : r)
}

QC_EdMove(dir) {
    r := QC_EdSelected()
    t := r + dir
    if (r = 0 || t < 1 || t > QC_Work.Length())
        return
    tmp := QC_Work[r]
    QC_Work[r] := QC_Work[t]
    QC_Work[t] := tmp
    QC_EdRefresh(t)
}
QC_EdUp(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_EdMove(-1)
}
QC_EdDown(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_EdMove(1)
}

QC_EdSave(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_Entries := QC_Work
    QC_SaveBook()
    QC_EdClose()
    QC_BuildPanel(true)
}

QC_EdCancel(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    QC_EdClose()
}
QC_Edit_Close(GuiHwnd := 0) {
    QC_EdClose()
}
QC_Edit_Escape(GuiHwnd := 0) {
    QC_EdClose()
}

QC_EdClose() {
    if (!QC_EditorHwnd)
        return
    Gui, QCEdit:Destroy
    QC_EditorHwnd := 0
    QC_DialogOpen--
}

; ================= DIALING =================
QC_DialEntry(e) {
    if (e.num = "") {
        QC_EditField(e, "num")
        return
    }
    QC_Dial(e.num, QC_Full(e))
}

QC_Dial(num, label := "") {
    d := RegExReplace(num, "\D")
    if (StrLen(d) = 11 && SubStr(d, 1, 1) = "1")
        d := SubStr(d, 2)
    if (StrLen(d) != 10) {
        MsgBox, 262192, Quick Call, % "Can't dial '" num "'. Need a full 10-digit number."
        return
    }
    if (QC_DialMode = "tel")
        url := "tel:+1" d
    else if (QC_DialMode = "teams")
        url := "msteams:/l/call/0/0?users=4:%2B1" d     ; Teams app, number ready to call
    else
        url := "https://voice.google.com/u/" QC_GVAccount "/calls?a=nc,%2B1" d
    ok := true
    try Run, %url%
    catch
        ok := false
    if (!ok && QC_DialMode = "teams") {    ; Teams app not registered: use Teams on the web
        url := "https://teams.microsoft.com/l/call/0/0?users=4:%2B1" d
        ok := true
        try Run, %url%
        catch
            ok := false
    }
    if (!ok) {
        MsgBox, 262192, Quick Call, Could not open the dialer link. Is a default browser set?
        return
    }
    if (QC_AutoConfirm && (QC_DialMode = "url" || QC_DialMode = "cell"))
        SetTimer, QC_ConfirmCall, -250
    QC_LastCall := {label: (label != "" ? label : QC_FormatPhone(d)), time: A_Now}
    QC_Tip("Calling " QC_LastCall.label "  " QC_FormatPhone(d) (QC_DialMode = "teams" ? "  (Teams)" : QC_DialMode = "cell" ? "  - answer your cell" : ""), 3000)
}

; Works whether or not the panel has been initialised (Preferences calls these).
QC_GetDialMode() {
    if (QC_DialMode != "")
        return QC_DialMode
    IniRead, dm, %A_ScriptDir%\QuickCall_Settings.ini, Settings, DialMode, url
    return RegExMatch(dm, "^(url|cell|teams|tel)$") ? dm : "url"
}
QC_DialModeName(mode) {
    return mode = "cell" ? "your cell phone (Google Voice)" : mode = "teams" ? "Microsoft Teams"
        : mode = "tel" ? "the phone app (tel:)" : "this computer (Google Voice)"
}

; Switching between computer and cell needs one Google Voice setting changed;
; say exactly which one and offer to open the settings page.
QC_SetDialMode(mode) {
    old := QC_GetDialMode()
    QC_DialMode := mode
    ini := (QC_IniFile != "") ? QC_IniFile : A_ScriptDir "\QuickCall_Settings.ini"
    IniWrite, %mode%, %ini%, Settings, DialMode
    acct := (QC_GVAccount != "") ? QC_GVAccount : 0
    msg := ""
    if (mode = "cell" && old != "cell")
        msg := "Quick Call will now place calls from your cell phone.`n`nGoogle Voice rings your cell first: answer it and the call connects. The call audio goes over the cell network, not this computer.`n`nOne-time setup: in Google Voice open Settings > Calls and turn ON ""Always use my phone to place calls"" (your cell must be listed as a linked number).`n`nOpen Google Voice settings now?"
    else if (mode = "url" && old = "cell")
        msg := "Quick Call will now place calls from this computer (dictaphone / headset).`n`nIn Google Voice open Settings > Calls and turn OFF ""Always use my phone to place calls"", or Google Voice will keep ringing your cell.`n`nOpen Google Voice settings now?"
    if (msg != "") {
        QC_DialogOpen++
        MsgBox, 262180, Quick Call, %msg%
        QC_DialogOpen--
        IfMsgBox, Yes
            Run, % "https://voice.google.com/u/" acct "/settings"
        return
    }
    note := (mode = "teams") ? "`n(needs outside calling in Teams: a dial pad on the Calls tab)" : ""
    QC_Tip("Quick Call now places calls from " QC_DialModeName(mode) note, 3000)
}
QC_CtxModeGV(p1 := "", p2 := "", p3 := "") {
    QC_SetDialMode("url")
}
QC_CtxModeCell(p1 := "", p2 := "", p3 := "") {
    QC_SetDialMode("cell")
}
QC_CtxModeTeams(p1 := "", p2 := "", p3 := "") {
    QC_SetDialMode("teams")
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
    WinGet, proc, ProcessName, A
    WinGetTitle, title, A
    onVoice := RegExMatch(proc, "i)^(chrome|msedge|firefox|brave)\.exe$") && InStr(title, "Voice")
    if (onVoice && !seenAt)
        seenAt := A_TickCount
    if (onVoice && A_TickCount - seenAt >= QC_ConfirmDelayMs) {
        Send, {Enter}
        tries := 0
        return
    }
    if (tries > 60) {          ; ~15 s: give up quietly
        tries := 0
        return
    }
    SetTimer, QC_ConfirmCall, -250
}

QC_DialText(txt) {
    if !RegExMatch(txt, "(\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}|\b8[057]-?\d{4}\b", m) {
        QC_Tip("No phone number found")
        return
    }
    d := RegExReplace(m, "\D")
    if (StrLen(d) = 6) {
        pre := SubStr(d, 1, 2), ext := SubStr(d, 3)
        if (pre = "85")
            d := "636947" ext
        else if (pre = "80")
            d := "636327" ext
        else {
            MsgBox, 262192, Quick Call, 87- extensions are split between 636-625 and 636-755. Dial the full number.
            return
        }
    }
    QC_Dial(d)
}

QC_DialSelection() {
    Sleep, 100
    saved := ClipboardAll
    Clipboard := ""
    Send, ^c
    ClipWait, 0.5
    if (ErrorLevel) {
        Clipboard := saved
        saved := ""
        QC_Tip("Highlight a phone number first")
        return
    }
    txt := Clipboard
    Clipboard := saved
    saved := ""
    QC_DialText(txt)
}

QC_ManualDial() {
    QC_DialogOpen++
    QC_OwnIfVisible()
    InputBox, val, Quick Call, Number to dial (10-digit or 85-xxxx / 80-xxxx):, , 340, 140
    cancelled := ErrorLevel
    QC_DialogOpen--
    if (!cancelled && Trim(val) != "")
        QC_DialText(val)
}

QC_FormatPhone(d) {
    return SubStr(d, 1, 3) "-" SubStr(d, 4, 3) "-" SubStr(d, 7)
}

QC_Tip(msg, ms := 2000) {
    ToolTip, % msg, , , 2
    SetTimer, QC_TipOff, % -ms
}
QC_TipOff() {
    ToolTip, , , , 2
}

; ================= CRITICAL RESULT STATEMENT =================
QC_LogCall() {
    if !IsObject(QC_LastCall) {
        QC_Tip("No call placed yet this session")
        return
    }
    target := 0
    WinGet, a, ID, A
    if (a) {
        WinGet, apid, PID, ahk_id %a%
        WinGet, pn, ProcessName, ahk_id %a%
        if (apid != QC_Pid && !RegExMatch(pn, "i)^(chrome|msedge|firefox|brave)\.exe$"))
            target := a
    }
    if (!target)
        target := QC_LastExtWin

    QC_DialogOpen++
    QC_OwnIfVisible()
    InputBox, who, % "Critical result: " QC_LastCall.label, Spoke with (name / title):, , 360, 140
    cancelled := ErrorLevel
    QC_DialogOpen--
    if (cancelled || Trim(who) = "")
        return

    FormatTime, t, % QC_LastCall.time, h:mm tt
    FormatTime, dt, % QC_LastCall.time, M/d/yyyy
    s := "These findings were discussed by telephone with " Trim(who) " (" QC_LastCall.label ") by " QC_RadName " at " t " on " dt "."
    if (QC_IncludeReadBack)
        s .= " Read-back was performed."

    Clipboard := s
    ClipWait, 1
    if (target && WinExist("ahk_id " target)) {
        WinActivate, ahk_id %target%
        WinWaitActive, ahk_id %target%, , 1
        if (!ErrorLevel) {
            Send, ^v
            return
        }
    }
    QC_Tip("Statement copied. Paste it into the report.", 3000)
}
; <<< QUICKCALL END

; >>> SMARTPARSE BEGIN (generated from SmartParse_v1.ahk - edit there, then re-embed) >>>
global SP_Result, SP_TargetHwnd, SP_ConfHwnd, SP_BoneHwnd, SP_BoneText
global SP_DataminingPhrase, SP_IncludeDatamining, SP_FleischnerAtEnd, SP_RVLVFormat
global SPB_Bone, SPB_Chrono, SPB_Dob, SPB_Exam, SPB_Sex, SPB_Preview    ; bone age GUI controls
global SP_Initialized, SP_Pid
global SP_ShowParse, SP_ShowTIRADS, SP_ShowORADS, SP_ShowBoneAge     ; set by the host (Preferences)
global SP_ShowLIRADS                                                  ; set by the host (Preferences, off by default)
global SP_LRHwnd, SP_LRText, SPL_Size, SPL_APHE, SPL_WO, SPL_Cap, SPL_TG, SPL_Anc, SPL_TIV, SPL_LRM, SPL_Ovr, SPL_Preview   ; LI-RADS GUI

SP_Init() {
    if (SP_Initialized)
        return
    SP_Initialized := true
    SP_DataminingPhrase := "SSM lung nodule"
    SP_IncludeDatamining := true
    SP_FleischnerAtEnd := true       ; Fleischner / TI-RADS / O-RADS go at the end of the report
    SP_RVLVFormat := "Macro"         ; "Macro" = cm, "Inline" = mm
    SP_Result := "", SP_TargetHwnd := 0, SP_ConfHwnd := 0, SP_BoneHwnd := 0
    SP_Pid := DllCall("GetCurrentProcessId")
}

; ================= dark theme helpers (used by the host for its own windows too) =================
; Dark context menus: Windows 10 1903+/11 draw the app's popup menus dark with
; light text once the app opts in (uxtheme ordinals 135/136). Menu, Color alone
; only changes the background and leaves black text.
SP_SetDarkMenus(on) {
    static last := ""
    if (last = on)
        return
    last := on
    hMod := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
    if (!hMod)
        hMod := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
    setMode := DllCall("GetProcAddress", "Ptr", hMod, "Ptr", 135, "Ptr")     ; SetPreferredAppMode
    flush := DllCall("GetProcAddress", "Ptr", hMod, "Ptr", 136, "Ptr")       ; FlushMenuThemes
    if (setMode)
        DllCall(setMode, "Int", on ? 2 : 3)      ; 2 = force dark, 3 = force light
    if (flush)
        DllCall(flush)
}

; Make a GUI readable in dark mode: themed checkboxes, radio buttons and group
; boxes ignore the text color (black on dark), so turn theming off for those;
; buttons and edits get the system dark style; dark title bar.
SP_DarkenGui(hwnd) {
    dhw := A_DetectHiddenWindows
    DetectHiddenWindows, On
    WinGet, list, ControlListHwnd, ahk_id %hwnd%
    Loop, Parse, list, `n
    {
        h := A_LoopField
        WinGetClass, cls, ahk_id %h%
        if (cls = "Button") {
            WinGet, st, Style, ahk_id %h%
            t := st & 0xF
            if (t = 2 || t = 3 || t = 4 || t = 5 || t = 6 || t = 7 || t = 9)
                DllCall("uxtheme\SetWindowTheme", "Ptr", h, "Str", "", "Str", "")
            else
                DllCall("uxtheme\SetWindowTheme", "Ptr", h, "Str", "DarkMode_Explorer", "Ptr", 0)
        } else if (cls = "Edit" || cls = "ComboBox" || cls = "ListBox" || cls = "SysListView32") {
            DllCall("uxtheme\SetWindowTheme", "Ptr", h, "Str", "DarkMode_Explorer", "Ptr", 0)
        }
    }
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 20, "Int*", 1, "Int", 4)
    DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
    DetectHiddenWindows, %dhw%
}

; ================= small helpers (v1 equivalents of v2 built-ins) =================
PE_N() {
    return "(?<![\d.])(\d+(?:\.\d+)?|\.\d+)"
}
PE_U() {
    return "(mm|cm|millimeters?|centimeters?|millimetres?|centimetres?)"
}
; RegExMatch returning a match object (adds the O option)
PE_RX(hay, pat, ByRef m, start := 1) {
    if RegExMatch(pat, "^[imsxADJUXPSC``]*\)")
        pat := "O" pat
    else
        pat := "O)" pat
    return RegExMatch(hay, pat, m, start)
}
PE_Lower(s) {
    return Format("{:L}", s)
}
PE_IsNum(v) {
    if v is number
        return true
    return false
}
PE_FormatTime(ts, fmt) {
    FormatTime, out, %ts%, %fmt%
    return out
}
PE_AddDays(ts, n) {
    ts += n, Days
    return ts
}
PE_DaysBetween(a, b) {     ; b - a in days
    b -= a, Days
    return b
}
PE_Fail(msg) {
    return {ok: false, err: msg}
}
PE_Ok(title, values, text, conf, atImpression := false) {
    return {ok: true, title: title, values: values, text: text, conf: conf, atImpression: atImpression}
}

; Remove numbers that are not measurements (image/series numbers, W/L, dates, MRN)
PE_Filter(t) {
    t := RegExReplace(t, "i)\(\s*(?:image|img|i|slice|ser|seq)\s*\d+\s*/\s*\d+\s*\)", "")
    t := RegExReplace(t, "i)(?:image|img|slice|series|seq|level)\s*[:=#]?\s*\d+(?:\s*/\s*\d+)?", "")
    t := RegExReplace(t, "\b(?:W|L|WW|WL)\s*[:=]\s*-?\d+", "")
    t := RegExReplace(t, "\d{1,2}/\d{1,2}/\d{2,4}", "")
    t := RegExReplace(t, "\d{4}-\d{1,2}-\d{1,2}", "")
    t := RegExReplace(t, "i)page\s*\d+\s*(?:of|/)\s*\d+", "")
    t := RegExReplace(t, "i)(?:ACC|MRN|ID)\s*#?\s*:?\s*\d+", "")
    return t
}

PE_Clean(text) {
    t := RegExReplace(text, "\R", " ")
    t := StrReplace(t, Chr(0xD7), "x")
    t := RegExReplace(t, "\s+", " ")
    return PE_Filter(t)
}

PE_Unit(u) {
    if (u = "")
        return ""
    return (SubStr(PE_Lower(u), 1, 1) = "c") ? "cm" : "mm"
}
PE_ToMm(v, u) {
    return (u = "cm") ? v * 10 : v
}
PE_ToCm(v, u) {
    return (u = "mm") ? v / 10 : v
}
PE_Fmt(v, dec := 1) {
    s := Round(v, dec) ""
    if InStr(s, ".")
        s := RTrim(RTrim(s, "0"), ".")
    return s
}

PE_FirstValue(s) {
    if PE_RX(s, "i)" PE_N() "\s*-?\s*" PE_U() "?(?!\d|\.\d|\s*%|-?\s*(?:min|sec|hour|hr|day|week|month|year|HU|o'?clock))", m)
        return {val: m[1] + 0, unit: PE_Unit(m[2]), pos: m.Pos(0), len: m.Len(0)}
    return ""
}

PE_ValueAfter(t, labelRe, stopRe := "", maxGap := 90) {
    pos := 1
    while (p := PE_RX(t, "i)" labelRe, lm, pos)) {
        after := SubStr(t, p + lm.Len(0), maxGap)
        if (stopRe != "" && (sp := RegExMatch(after, "i)" stopRe)))
            after := SubStr(after, 1, sp - 1)
        v := PE_FirstValue(after)
        if IsObject(v) {
            v.labelPos := p
            return v
        }
        pos := p + lm.Len(0)
    }
    return ""
}

PE_Measures(t) {
    out := [], pos := 1
    while (p := PE_RX(t, "i)" PE_N() "\s*-?\s*" PE_U() "\b", m, pos)) {
        out.Push({val: m[1] + 0, unit: PE_Unit(m[2]), pos: p})
        pos := p + m.Len(0)
    }
    return out
}

PE_FindDims(t) {
    n := PE_N(), u := "\s*" PE_U() "?", sep := "\s*(?:x|by|\*)\s*"
    if !PE_RX(t, "i)" n u sep n u sep n u "(?!\d|\.\d)", m)
        return ""
    vals := [m[1] + 0, m[3] + 0, m[5] + 0]
    units := [PE_Unit(m[2]), PE_Unit(m[4]), PE_Unit(m[6])]
    hasUnit := (units[1] != "" || units[2] != "" || units[3] != "")
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
        g := (Max(vals*) >= 20) ? "mm" : "cm"
        units := [g, g, g]
    }
    return {vals: vals, units: units, hasUnit: hasUnit, guessed: guessed, pos: m.Pos(0), len: m.Len(0)}
}

PE_DimsText(d) {
    if (d.units[1] = d.units[2] && d.units[2] = d.units[3])
        return PE_Fmt(d.vals[1], 2) " x " PE_Fmt(d.vals[2], 2) " x " PE_Fmt(d.vals[3], 2) " " d.units[1]
    return PE_Fmt(d.vals[1], 2) " " d.units[1] " x " PE_Fmt(d.vals[2], 2) " " d.units[2] " x " PE_Fmt(d.vals[3], 2) " " d.units[3]
}

PE_Before(t, pos, n := 140) {
    start := Max(1, pos - n)
    s := SubStr(t, start, pos - start)
    if (p := InStr(s, ". ", false, 0))
        s := SubStr(s, p + 2)
    return s
}

; ================= VOLUME =================
PE_Volume(text) {
    t := PE_Clean(text)
    d := PE_FindDims(t)
    if !IsObject(d)
        return PE_Fail("Could not find three dimensions.`n`nExamples:`n- The prostate gland measures 4.5 x 3.2 x 4.1 cm.`n- Right ovarian cyst measuring 32 x 24 x 28 mm.")
    cm := [PE_ToCm(d.vals[1], d.units[1]), PE_ToCm(d.vals[2], d.units[2]), PE_ToCm(d.vals[3], d.units[3])]
    vol := 0.5236 * cm[1] * cm[2] * cm[3]
    organ := PE_Organ(PE_Before(t, d.pos))
    conf := d.hasUnit ? ((RegExMatch(t, "i)measur|size|dimension") || organ != "") ? 95 : 85) : 40
    if (Max(cm*) > 50)
        conf -= 30
    res := " This corresponds to a volume of " PE_Fmt(vol) " cc (mL)"
    ; Size grading ONLY for the prostate (no descriptors for ICH, cysts, other organs)
    if (organ = "prostate")
        res .= ", " PE_ProstateGrade(vol) "."
    else
        res .= "."
    vals := [["Structure", organ != "" ? organ : "(not detected)"], ["Dimensions", PE_DimsText(d) (d.guessed ? "  (units assumed)" : "")], ["Volume", PE_Fmt(vol) " cc"]]
    if (organ = "prostate")
        vals.Push(["Grade", "<30 normal, 30-49 mild, 50-79 moderate, 80+ severe"])
    return PE_Ok(organ = "prostate" ? "Prostate Volume" : "Ellipsoid Volume", vals, res, conf)
}

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
    static organs := ""
    if !IsObject(organs)
        organs := [["prostat", "prostate"], ["bladder", "bladder"], ["thyroid", "thyroid"], ["ovar", "ovary"], ["uter", "uterus"]
            , ["testi", "testis"], ["kidney|renal", "kidney"], ["spleen|splenic", "spleen"], ["liver|hepatic", "liver"]
            , ["hematoma", "hematoma"], ["hemorrhage|bleed", "hemorrhage"], ["abscess", "abscess"], ["collection", "collection"]
            , ["cyst", "cyst"], ["lymph node|node", "lymph node"], ["mass", "mass"], ["lesion", "lesion"], ["nodule", "nodule"]]
    for _, o in organs {
        if RegExMatch(s, "i)\b(?:" o[1] ")")
            return o[2]
    }
    return ""
}

; ================= ICH (ABC/2) =================
PE_ICH(text) {
    t := PE_Clean(text)
    d := PE_FindDims(t)
    if !IsObject(d)
        return PE_Fail("Could not find three hemorrhage dimensions.`n`nExample: Intraparenchymal hemorrhage measuring 4.2 x 2.8 x 3.5 cm.")
    a := PE_ToCm(d.vals[1], d.units[1]), b := PE_ToCm(d.vals[2], d.units[2]), c := PE_ToCm(d.vals[3], d.units[3])
    vol := (a * b * c) / 2
    conf := d.hasUnit ? 90 : 40
    res := " ICH volume approximately " PE_Fmt(vol) " cc (ABC/2: " PE_Fmt(a) " x " PE_Fmt(b) " x " PE_Fmt(c) " cm)."
    vals := [["Dimensions", PE_DimsText(d) (d.guessed ? "  (units assumed)" : "")], ["A x B x C", PE_Fmt(a) " x " PE_Fmt(b) " x " PE_Fmt(c) " cm"], ["Volume (ABC/2)", PE_Fmt(vol) " cc"]]
    return PE_Ok("ICH Volume (ABC/2)", vals, res, conf)
}

; ================= RV / LV =================
PE_RVLV(text) {
    t := PE_Clean(text)
    rvRe := "(?:\bRV\b|\bR\.V\.|\bright\s+ventric(?:le|ular)|\brt\.?\s+ventric(?:le|ular)|\brvval\b)"
    lvRe := "(?:\bLV\b|\bL\.V\.|\bleft\s+ventric(?:le|ular)|\blt\.?\s+ventric(?:le|ular)|\blvval\b)"
    rv := "", lv := "", conf := 0
    if PE_RX(t, "i)\bRV\s*[/:]\s*LV\b[^\d]{0,20}" PE_N() "\s*[/:]\s*" PE_N(), m) {
        rv := {val: m[1] + 0, unit: ""}, lv := {val: m[2] + 0, unit: ""}, conf := 80
    } else if (PE_RX(t, "i)\bRV\s*(?:/|:|to)\s*LV\b(?:\s*(?:diameter\s*)?ratio)?[^\d]{0,20}" PE_N() "(?!\s*[/:]\s*\d)", m) && (m[1] + 0) < 4) {
        ratio := PE_Fmt(m[1] + 0, 2)
        return PE_Ok("RV/LV Ratio", [["Ratio", ratio]], " RV/LV ratio: " ratio ". " PE_RVLVInterp(ratio), 80)
    } else {
        rv := PE_ValueAfter(t, rvRe, lvRe)
        lv := PE_ValueAfter(t, lvRe, rvRe)
        if (IsObject(rv) && IsObject(lv))
            conf := 90
    }
    if (!IsObject(rv) || !IsObject(lv))
        return PE_Fail("Could not find both RV and LV measurements.`n`nExamples:`n- The right ventricle measures 4.2 cm and the left ventricle measures 3.8 cm.`n- RV 42 mm / LV 35 mm")
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
    if (SP_RVLVFormat = "Inline")
        res := " RV/LV ratio: " ratio " (RV " PE_Fmt(rvMm) "mm, LV " PE_Fmt(lvMm) "mm). " PE_RVLVInterp(ratio)
    else
        res := " RV/LV ratio: " ratio " (RV " PE_Fmt(rvMm / 10) "cm, LV " PE_Fmt(lvMm / 10) "cm). " PE_RVLVInterp(ratio)
    vals := [["RV", PE_Fmt(rv.val, 2) " " rvU], ["LV", PE_Fmt(lv.val, 2) " " lvU], ["Ratio", ratio]]
    return PE_Ok("RV/LV Ratio", vals, res, conf)
}

; No validated mild/moderate/severe grading exists for the CT RV/LV ratio, so the
; text only states what the number shows (never "severe" or a strain diagnosis).
PE_RVLVInterp(ratio) {
    if (ratio >= 1.0)
        return "Elevated (1.0 or greater), compatible with right ventricular dilatation. Correlate clinically and with echocardiography for right heart strain."
    if (ratio >= 0.9)
        return "Borderline (0.9-0.99)."
    return "Normal (less than 0.9)."
}

; ================= STENOSIS / NASCET =================
PE_Stenosis(text, forceNascet := false) {
    t := PE_Clean(text)
    stenRe := "(?:residual\s+(?:lumen|luminal\s+diameter|diameter)|minimal\s+lumen(?:al)?(?:\s+diameter)?|\bMLD\b|narrowest|tightest|narrowing|narrowed|stenos[ie]s|stenotic|lumen\s+at\s+the\s+(?:stenosis|narrowing))"
    normRe := "(?:\bnormal|\breference|\bdistal|non-?stenotic|unaffected|uninvolved|beyond\s+the\s+(?:stenosis|narrowing)|downstream)"
    sten := PE_ValueAfter(t, stenRe, normRe)
    norm := PE_ValueAfter(t, normRe, stenRe)
    conf := 90
    if (!IsObject(sten) && PE_RX(t, "i)" PE_N() "\s*-?\s*" PE_U() "?\s+(?:residual\s+lumen|stenosis|narrowing)", m))
        sten := {val: m[1] + 0, unit: PE_Unit(m[2])}
    if (!IsObject(sten) || !IsObject(norm) || (sten.val = norm.val && sten.unit = norm.unit)) {
        ms := PE_Measures(t)
        if (ms.Length() = 2 && RegExMatch(t, "i)" stenRe)) {
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
    sU := sten.unit != "" ? sten.unit : ((norm.unit = "cm" && sten.val < 2) ? "cm" : "mm")
    nU := norm.unit != "" ? norm.unit : ((sten.unit = "cm" && norm.val < 2) ? "cm" : "mm")
    if (sten.unit = "" || norm.unit = "")
        conf -= 10
    s := PE_ToMm(sten.val, sU), n := PE_ToMm(norm.val, nU)
    if (s >= n) {
        if (s > n) {
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
    severity := pct < 50 ? "mild stenosis" : pct < 70 ? "moderate stenosis" : "severe stenosis"
    if (forceNascet || vessel = "ICA") {
        res := " NASCET: " PE_Fmt(pct) "% stenosis (distal " PE_Fmt(n) "mm, stenosis " PE_Fmt(s) "mm), "
        res .= pct < 50 ? "mild stenosis." : pct < 70 ? "moderate stenosis, consider intervention if symptomatic." : "severe stenosis, strong indication for CEA/CAS."
        title := "NASCET Stenosis"
    } else {
        res := " " (vessel != "" ? vessel : "Vessel") " stenosis: " PE_Fmt(pct) "% (normal " PE_Fmt(n) "mm, stenosis " PE_Fmt(s) "mm), " severity "."
        title := "Vessel Stenosis"
    }
    vals := [["Vessel", vessel != "" ? vessel : "(not detected)"], ["Stenosis", PE_Fmt(sten.val, 2) " " sU], ["Normal", PE_Fmt(norm.val, 2) " " nU], ["% stenosis", PE_Fmt(pct) "%"]]
    return PE_Ok(title, vals, res, conf)
}

PE_NASCET(text) {
    return PE_Stenosis(text, true)
}

PE_Vessel(t) {
    static vessels := ""
    if !IsObject(vessels)
        vessels := [["\bICA\b|internal\s+carotid", "ICA"], ["\bCCA\b|common\s+carotid", "CCA"], ["\bECA\b|external\s+carotid", "ECA"]
            , ["\bSMA\b|superior\s+mesenteric", "SMA"], ["\bIMA\b|inferior\s+mesenteric", "IMA"], ["celiac", "Celiac"]
            , ["renal\s+arter", "Renal artery"], ["vertebral", "Vertebral artery"], ["basilar", "Basilar artery"]
            , ["\bMCA\b|middle\s+cerebral", "MCA"], ["\bACA\b|anterior\s+cerebral", "ACA"], ["\bPCA\b|posterior\s+cerebral", "PCA"]
            , ["subclavian", "Subclavian artery"], ["\bCIA\b|common\s+iliac", "Common iliac artery"], ["\bEIA\b|external\s+iliac", "External iliac artery"]
            , ["\bIIA\b|internal\s+iliac", "Internal iliac artery"], ["\bSFA\b|superficial\s+femoral", "SFA"], ["\bCFA\b|common\s+femoral", "CFA"]
            , ["popliteal", "Popliteal artery"], ["\bLAD\b", "LAD"], ["\bRCA\b", "RCA"], ["circumflex|\bLCx\b", "LCx"], ["left\s+main", "Left main"]
            , ["carotid", "ICA"], ["aort", "Aorta"], ["iliac", "Iliac artery"], ["femoral", "Femoral artery"]]
    for _, v in vessels {
        if RegExMatch(t, "i)" v[1])
            return v[2]
    }
    return ""
}

; ================= ADRENAL WASHOUT =================
PE_Adrenal(text) {
    t := PE_Clean(text)
    vals := [], pos := 1
    while (p := PE_RX(t, "i)(?<![\d.])(-?\d+(?:\.\d+)?)\s*(?:HU\b|Hounsfield(?:\s+units?)?)", m, pos)) {
        vals.Push({val: m[1] + 0, pos: p, end: p + m.Len(0), phase: ""})
        pos := p + m.Len(0)
    }
    if (vals.Length() < 2)
        return PE_Fail("Could not find at least two HU values.`n`nExample: Left adrenal nodule measures 45 HU on noncontrast, 85 HU on portal venous phase, and 50 HU on 15-minute delayed phase.")
    nv := vals.Length()
    for i, v in vals {
        nextStart := (i < nv) ? vals[i + 1].pos : StrLen(t) + 1
        prevEnd := (i > 1) ? vals[i - 1].end : 1
        after := SubStr(t, v.end, Min(45, nextStart - v.end))
        before := SubStr(t, prevEnd, v.pos - prevEnd)
        ph := ""
        if PE_RX(after, "i)^\s*(?:\(|on\b|in\b|at\b|during\b|with\b|for\b)\s*(?:the\s+)?(.{0,30})", am)
            ph := PE_Phase(am[1], true)
        if (ph = "")
            ph := PE_Phase(before, false)
        if (ph = "" && PE_RX(after, "i)^[\s,]*(.{0,30})", am))
            ph := PE_Phase(am[1], true)
        v.phase := ph
    }
    pre := "", post := "", del := "", labeled := 0
    for _, v in vals {
        if (v.phase = "pre" && pre = "")
            pre := v.val, labeled++
        else if (v.phase = "post" && post = "")
            post := v.val, labeled++
        else if (v.phase = "delayed" && del = "")
            del := v.val, labeled++
    }
    conf := 95
    if (labeled < nv || post = "" || del = "") {
        if (nv >= 3)
            pre := vals[1].val, post := vals[2].val, del := vals[3].val
        else
            pre := "", post := vals[1].val, del := vals[2].val
        conf := 55
    }
    if (post < -50 || post > 300 || del < -50 || del > 300)
        conf -= 25
    res := " Adrenal washout: "
    if (pre != "" && post != pre) {
        absW := Round((post - del) / (post - pre) * 100, 1)
        res .= "absolute " PE_Fmt(absW) "%" (absW >= 60 ? " (likely adenoma)" : " (indeterminate)") ", "
    }
    if (post != 0) {
        rel := Round((post - del) / post * 100, 1)
        res .= "relative " PE_Fmt(rel) "%" (rel >= 40 ? " (likely adenoma)" : " (indeterminate)") "."
    }
    if (pre != "" && pre <= 10)
        res .= " Pre-contrast " PE_Fmt(pre) " HU suggests lipid-rich adenoma."
    out := [["Pre-contrast", pre != "" ? PE_Fmt(pre) " HU" : "N/A"], ["Portal venous", PE_Fmt(post) " HU"], ["Delayed", PE_Fmt(del) " HU"]]
    return PE_Ok("Adrenal Washout", out, res, conf)
}

PE_Phase(s, fromStart) {
    static phases := ""
    if !IsObject(phases)
        phases := [["delayed", "delayed|15[- ]?min(?:ute)?|10[- ]?min(?:ute)?|\blate\b|washout\s+phase"]
            , ["post", "portal(?:\s+venous)?|\bvenous|\bPV\b|post-?contrast|postcontrast|contrast[- ]enhanced|\benhanced|arterial|nephrographic|60[- ]?(?:70[- ]?)?sec"]
            , ["pre", "non-?contrast|non-?enhanced|unenhanced|pre-?contrast|precontrast|without\s+contrast|native|baseline|plain|non-?con\b|\bNC\b"]]
    best := "", bestPos := fromStart ? 999 : 0
    for _, ph in phases {
        if (fromStart) {
            if ((p := RegExMatch(s, "i)" ph[2])) && p < bestPos)
                best := ph[1], bestPos := p
        } else {
            q := 1
            while (p := PE_RX(s, "i)" ph[2], m, q)) {
                if (p >= bestPos)
                    best := ph[1], bestPos := p
                q := p + Max(1, m.Len(0))
            }
        }
    }
    return best
}

; ================= FLEISCHNER =================
PE_Fleischner(text) {
    t := RegExReplace(text, "\R", " ")
    t := StrReplace(t, Chr(0xD7), "x")
    t := PE_Filter(t)
    t := RegExReplace(t, "(?<!\d)\.(?!\d)|;|(?<=\d)\.(?=\s+[A-Z])", "`n")
    nodRe := "i)\b(?:nodules?|nodular\s+(?:opacit(?:y|ies)|densit(?:y|ies))|micronodules?|GGNs?|GGOs?|ground[- ]?glass\s+(?:opacit(?:y|ies)|nodules?|lesions?|focus)|subsolid\s+(?:lesions?|opacit(?:y|ies)))\b"
    nonLung := "i)\b(?:thyroid|adrenal|renal|kidney|hepatic|liver|breast|splenic|spleen|pancrea|ovar|testic|prostat|lymph|skin|subcutaneous|bone|osseous)"
    found := [], plural := false
    for _, s in StrSplit(t, "`n") {
        if !RegExMatch(s, nodRe)
            continue
        if (RegExMatch(s, nonLung) && !RegExMatch(s, "i)lung|pulmonary|lobe|lingula|\b[RL][UML]L\b"))
            continue
        if (RegExMatch(s, "i)\bcalcified\b") && !RegExMatch(s, "i)\b(?:non-?|partially\s+)calcified\b"))
            continue
        size := 0, sub6 := false
        if RegExMatch(s, "i)sub[- ]?(?:6|centimeter)|<\s*6\s*mm|less\s+than\s+6\s*mm|smaller\s+than\s+6\s*mm")
            size := 5, sub6 := true
        if (sub6) {
            ; already sized
        } else if PE_RX(s, "i)" PE_N() "\s*" PE_U() "?\s*(?:x|by)\s*" PE_N() "\s*" PE_U(), m) {
            u1 := PE_Unit(m[2] != "" ? m[2] : m[4]), u2 := PE_Unit(m[4])
            a := PE_ToMm(m[1] + 0, u1), b := PE_ToMm(m[3] + 0, u2)
            size := Round((a + b) / 2)
        } else {
            for _, v in PE_Measures(s) {
                mmv := PE_ToMm(v.val, v.unit)
                if (mmv > size)
                    size := mmv
            }
        }
        if (size = 0 && RegExMatch(s, "i)punctate|tiny|small|micronodul|miliary"))
            size := 5, sub6 := true
        if (size = 0 || size > 30)
            continue
        size := PE_Fmt(size) + 0
        type := "solid"
        if RegExMatch(s, "i)part[- ]?solid|semi[- ]?solid|mixed(?:\s+(?:solid|density|attenuation))?")
            type := "part-solid"
        else if RegExMatch(s, "i)ground[- ]?glass|\bGG[NO]s?\b|sub[- ]?solid|non-?solid|hazy")
            type := "subsolid"
        lobe := PE_Lobe(s)
        if RegExMatch(s, "i)\b(?:nodules|micronodules|GGNs|GGOs|opacities|multiple|several|numerous|innumerable|scattered|few|bilateral|two|three|four)\b")
            plural := true
        dup := false
        for _, f in found {
            if (f.type = type && Abs(f.size - size) <= 1 && (f.lobe = "" || lobe = "" || f.lobe = lobe)) {
                dup := true
                if (size > f.size)
                    f.size := size
                if (f.lobe = "")
                    f.lobe := lobe
                break
            }
        }
        if (!dup)
            found.Push({type: type, size: size, lobe: lobe, sub6: sub6})
    }
    if (found.Length() = 0)
        return PE_Fail("Could not find a pulmonary nodule with a size.`n`nExamples:`n- There is a 7 mm solid noncalcified pulmonary nodule in the right upper lobe.`n- 8 x 6 mm ground-glass nodule in the left lower lobe.")
    isMultiple := (found.Length() > 1) || plural
    maxSolid := 0, maxSub := 0, maxPart := 0
    for _, f in found {
        if (f.type = "solid")
            maxSolid := Max(maxSolid, f.size)
        else if (f.type = "subsolid")
            maxSub := Max(maxSub, f.size)
        else
            maxPart := Max(maxPart, f.size)
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
    recLow := PE_FleischnerRec(maxSolid, maxSub, maxPart, isMultiple, "Low risk")
    recHigh := PE_FleischnerRec(maxSolid, maxSub, maxPart, isMultiple, "High risk")
    for _, f in found {
        if (f.sub6) {
            nm := f.type = "solid" ? "Solid" : f.type = "subsolid" ? "Ground glass" : "Part-solid"
            recLow := StrReplace(recLow, nm " 5mm", nm " <6mm"), recHigh := StrReplace(recHigh, nm " 5mm", nm " <6mm")
        }
    }
    r .= "`nLOW RISK recommendation:`n" recLow
    r .= "`n`nHIGH RISK recommendation:`n" recHigh
    if (SP_IncludeDatamining)
        r .= "`n`n" SP_DataminingPhrase "`nACR and AMA MIPS #364"
    r .= "`n`nNote: The need for followup depends on clinical discussion of patient's comorbid conditions, demographics, and willingness to undergo followup imaging and potential intervention."
    if (ShowCitations)
        r .= "`nRef: MacMahon H et al. Radiology 2017;284:228-243"
    r .= "`n___________________________________________________________"
    summary := ""
    for _, f in found
        summary .= (summary != "" ? "; " : "") f.type " " (f.sub6 ? "<6" : PE_Fmt(f.size)) " mm" (f.lobe != "" ? " " f.lobe : "")
    vals := [["Nodules", summary], ["Count", isMultiple ? "Multiple" : "Single"]]
    return PE_Ok("Fleischner Nodules", vals, r, found.Length() > 3 ? 75 : 90, SP_FleischnerAtEnd)
}

PE_FleischnerRec(maxSolid, maxSubsolid, maxPartsolid, isMultiple, risk) {
    result := ""
    if (maxSolid > 0) {
        if (maxSolid < 6)
            result .= (risk = "Low risk") ? "- Solid " maxSolid "mm: No routine follow-up required." : "- Solid " maxSolid "mm: Optional CT at 12 months."
        else if (maxSolid <= 8) {
            if (isMultiple)
                result .= (risk = "Low risk") ? "- Solid " maxSolid "mm (multiple): CT at 3-6 months, then consider CT at 18-24 months." : "- Solid " maxSolid "mm (multiple): CT at 3-6 months, then CT at 18-24 months."
            else
                result .= (risk = "Low risk") ? "- Solid " maxSolid "mm: CT at 6-12 months, then consider CT at 18-24 months." : "- Solid " maxSolid "mm: CT at 6-12 months, then CT at 18-24 months."
        } else
            result .= "- Solid " maxSolid "mm: Consider CT at 3 months, PET/CT, or tissue sampling."
    }
    if (maxSubsolid > 0) {
        if (result != "")
            result .= "`n"
        if (maxSubsolid < 6)
            result .= isMultiple ? "- Ground glass " maxSubsolid "mm (multiple): CT at 3-6 months. If stable, consider CT at 2 and 4 years." : "- Ground glass " maxSubsolid "mm: No routine follow-up required."
        else
            result .= isMultiple ? "- Ground glass " maxSubsolid "mm (multiple): CT at 3-6 months, subsequent management based on most suspicious nodule." : "- Ground glass " maxSubsolid "mm: CT at 6-12 months, then every 2 years for 5 years."
    }
    if (maxPartsolid > 0) {
        if (result != "")
            result .= "`n"
        if (maxPartsolid < 6)
            result .= "- Part-solid " maxPartsolid "mm: No routine follow-up required."
        else
            result .= isMultiple ? "- Part-solid " maxPartsolid "mm (multiple): CT at 3-6 months. If stable, annual CT for 5 years." : "- Part-solid " maxPartsolid "mm: CT at 3-6 months. If stable, annual CT for 5 years. If solid component >=6mm, consider PET/CT or biopsy."
    }
    return result
}

PE_Lobe(s) {
    if PE_RX(s, "i)\b(right|left)\s+(upper|middle|lower)\s+lobe", m)
        return PE_Lower(m[1] " " m[2]) " lobe"
    if PE_RX(s, "\b(RUL|RML|RLL|LUL|LLL)\b", m) {
        abbr := {RUL: "right upper lobe", RML: "right middle lobe", RLL: "right lower lobe", LUL: "left upper lobe", LLL: "left lower lobe"}
        return abbr[m[1]]
    }
    if RegExMatch(s, "i)lingula")
        return "lingula"
    return ""
}

; ================= FOLLOW-UP DATE =================
PE_FutureDate(interval, unit) {
    today := A_YYYY A_MM A_DD
    if (unit = "days")
        d := PE_AddDays(today, interval)
    else if (unit = "weeks")
        d := PE_AddDays(today, interval * 7)
    else {
        months := (unit = "years") ? interval * 12 : interval
        y := A_YYYY + 0, mo := A_MM + 0 + months, day := A_DD + 0
        y += Floor((mo - 1) / 12)
        mo := Mod(mo - 1, 12) + 1
        first := Format("{:04}{:02}01", y, mo)
        nextFirst := SubStr(PE_AddDays(first, 32), 1, 6) "01"
        dim := PE_DaysBetween(first, nextFirst)
        d := Format("{:04}{:02}{:02}", y, mo, Min(day, dim))
    }
    return PE_FormatTime(d, "MMMM d, yyyy")
}

PE_Date(text) {
    t := RegExReplace(text, "\R", " ")
    words := {a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, eighteen: 18}
    num := "(\d+|twenty[- ]four|eighteen|twelve|eleven|ten|nine|eight|seven|six|five|four|three|two|one|an?)"
    unitRe := "(days?|weeks?|wks?|months?|mos?|years?|yrs?)"
    if !PE_RX(t, "i)\b" num "(?:\s*(?:-|to|or)\s*" num ")?[\s-]*" unitRe "\b(?![\s-]*old)", m) {
        if !PE_RX(t, "i)\b(\d+)\s*(d|w|m|y)\b", m)
            return PE_Fail("Could not find a follow-up interval.`n`nExamples:`n- Recommend follow-up ultrasound in 6 months.`n- Please schedule follow-up MRI in 3 weeks.")
        n1 := m[1] + 0, n2 := "", u := m[2]
    } else {
        n1 := PE_WordNum(m[1], words)
        n2 := (m[2] = "") ? "" : PE_WordNum(m[2], words)
        u := m[3]
    }
    c := PE_Lower(SubStr(u, 1, 1))
    unit := c = "d" ? "days" : c = "w" ? "weeks" : c = "m" ? "months" : "years"
    if (n1 = 0)
        return PE_Fail("Follow-up interval must be greater than 0.")
    d1 := PE_FutureDate(n1, unit)
    span := n1 (n2 != "" ? "-" n2 : "") " " ((n2 = "" && n1 = 1) ? RTrim(unit, "s") : unit)
    when := (n2 != "") ? d1 " to " PE_FutureDate(n2, unit) : d1
    modality := ""
    if PE_RX(t, "i)\b(CT|MRI|MR|ultrasound|sonogra\w*|US|PET(?:/CT)?|mammogra\w*|radiograph\w*|x-?ray|CTA|MRA)\b", mm)
        modality := mm[1]
    if RegExMatch(t, "i)follow[- ]?up|recommend|repeat|re-?evaluat|re-?image|schedul")
        res := " (Due approximately " when ".)"
    else
        res := " Recommend follow-up" (modality != "" ? " " modality : "") " in " span " (approximately " when ")."
    vals := [["Interval", span], ["Modality", modality != "" ? modality : "(not stated)"], ["Due date", when]]
    return PE_Ok("Follow-up Date", vals, res, 95)
}

PE_WordNum(w, words) {
    if PE_IsNum(w)
        return w + 0
    w := PE_Lower(RegExReplace(w, "[- ]", ""))
    if (w = "twentyfour")
        return 24
    return words[w]
}

; ================= THYROID: ACR TI-RADS =================
PE_TIRADS(text) {
    t := RegExReplace(text, "\R", "`n")
    t := StrReplace(t, Chr(0xD7), "x")
    if PE_RX(t, "i)(?:^|\n)\s*(?:CLINICAL\s+)?IMPRESSIONS?\s*:", im)
        t := SubStr(t, 1, im.Pos(0) - 1)
    ; Skip the report header and the TI-RADS legend ("TR3 = ... If >2.5cm, FNA")
    if PE_RX(t, "i)(?:^|\n)\s*FINDINGS\s*:", fm)
        t := SubStr(t, fm.Pos(0) + fm.Len(0))
    if (RegExMatch(t, "im)^\s*Composition\s*:") && RegExMatch(t, "im)^\s*Echogenicity\s*:"))
        nodules := PE_TIRADSFromTemplate(t)
    else
        nodules := PE_TIRADSFromText(t)
    if (nodules.Length() = 0)
        return PE_Fail("Could not find a thyroid nodule with a size.`n`nTemplate: fill in the nodule's Size, Composition, Echogenicity, Shape, Margins and Echogenic Foci.`nFree text example: Right lobe: solid, hypoechoic, 1.5 cm nodule with macrocalcifications, wider-than-tall with smooth margins.")
    out := "`n`nACR TI-RADS:"
    vals := [], fnaCount := 0, conf := 90
    for i, n in nodules {
        sc := PE_TIRADSScore(n.text)
        tr := PE_TIRADSLevel(sc.total)
        rec := PE_TIRADSRec(tr, n.size)
        if InStr(rec, "FNA recommended")
            fnaCount++
        num := n.num != "" ? n.num : i
        out .= "`nNodule " num (n.loc != "" ? ", " n.loc : "") ", " PE_Fmt(n.size) " cm: TR" tr " (" PE_TIRADSName(tr) "), "
        out .= sc.total " point" (sc.total = 1 ? "" : "s") ". " rec
        out .= "`n    Points: " sc.detail
        vals.Push(["Nodule " num, (n.loc != "" ? n.loc " " : "") PE_Fmt(n.size) " cm, " sc.total " pts, TR" tr (sc.missing != "" ? "  [assumed: " sc.missing "]" : "")])
        if (sc.missing != "")
            conf := Min(conf, 70)
    }
    if (fnaCount > 2)
        out .= "`nNote: If multiple nodules meet FNA criteria, sample the two highest-scoring nodules."
    if (nodules.Length() > 4)
        out .= "`nNote: Only the four highest-scoring nodules need to be reported."
    if (ShowCitations)
        out .= "`nRef: Tessler FN et al. ACR TI-RADS. JACR 2017;14:587-595."
    return PE_Ok("ACR TI-RADS", vals, out, conf, true)
}

; Structured template: one block per nodule, starting at its "Location:" line.
; Fields still showing their picklist ("composition choices:Cystic/Solid/...") are skipped.
PE_TIRADSFromTemplate(t) {
    nodules := [], cur := "", lastHdr := ""
    for _, line in StrSplit(t, "`n") {
        line := Trim(line, " `t`r")
        if RegExMatch(line, "i)^Nodule\b(?!s)\s*(?:number|no\.?|#)?\s*(\d*)", h) {
            lastHdr := h1
            continue
        }
        if RegExMatch(line, "i)^Follow-?up\s+details") {
            cur := ""
            continue
        }
        if !RegExMatch(line, "i)^([A-Za-z \-]+?)\s*:\s*(.*)$", f)
            continue
        label := Format("{:L}", Trim(f1)), val := Trim(f2)
        if (label = "location") {
            cur := {num: lastHdr, loc: "", size: 0, text: "", fields: ""}
            nodules.Push(cur)
            lastHdr := ""
            if !InStr(val, "/")
                cur.loc := PE_ThyroidLoc(val)
            continue
        }
        if !IsObject(cur)
            continue
        if (label = "size") {
            v := RegExReplace(val, "i)\(?\s*previously.*$")     ; current size only
            cur.size := PE_TIRADSSize(v)
        } else if RegExMatch(label, "^(?:composition|echogenicity|shape|margins?|echogenic foci)$") {
            if (val != "" && !InStr(val, "choices") && !InStr(val, "/"))
                cur.text .= label ": " val ". "
        }
    }
    out := []
    for _, n in nodules
        if (n.size > 0)
            out.Push(n)
    return out
}

; Free dictation: a nodule is a sentence with "nodule" and a size, plus the
; sentences that follow it.
PE_TIRADSFromText(t) {
    keep := ""
    for _, line in StrSplit(t, "`n") {
        ; template count lines / legend: "nodules >/= 1 cm", "TR3 = 3 pts"
        if RegExMatch(line, "i)>\s*/?\s*=|not\s+described\s+below|^\s*TR\d\s*=|estimated\s+total\s+number")
            continue
        keep .= line "`n"
    }
    t := RegExReplace(keep, "\s+", " ")
    t := RegExReplace(t, "(?<!\d)\.(?!\d)|;", ".`n")
    nodules := [], cur := ""
    for _, s in StrSplit(t, "`n") {
        s := Trim(s)
        if (s = "")
            continue
        hasNod := RegExMatch(s, "i)\b(?:nodules?|lesions?|mass|TR\d)\b")
        sz := PE_TIRADSSize(s)
        if (hasNod && sz > 0) {
            if RegExMatch(s, "i)\bno\s+(?:\w+\s+){0,3}nodules?\b")
                continue
            cur := {text: s, size: sz, num: "", loc: ""}
            nodules.Push(cur)
        } else if IsObject(cur) {
            if (RegExMatch(s, "i)\b(?:nodules?|lobe|isthmus)\b") && !RegExMatch(s, "i)\b(?:it|this|the\s+nodule|which|there\s+is)\b"))
                cur := ""
            else
                cur.text .= " " s
        }
    }
    for _, n in nodules
        n.loc := PE_ThyroidLoc(n.text)
    return nodules
}

PE_TIRADSSize(s) {
    best := 0, pos := 1
    while (p := PE_RX(s, "i)" PE_N() "\s*(?:" PE_U() ")?((?:\s*(?:x|by)\s*(?:\d+(?:\.\d+)?|\.\d+)\s*(?:" PE_U() ")?){0,2})", m, pos)) {
        pos := p + Max(1, m.Len(0))
        u := ""
        if PE_RX(m.Value(0), "i)(mm|cm|millimet|centimet)[a-z]*\s*$", um)
            u := PE_Unit(um[1])
        if (u = "")
            continue
        nums := [], q := 1, mv := m.Value(0)
        while (qq := PE_RX(mv, "(\d+(?:\.\d+)?|\.\d+)", nm, q))
            nums.Push(nm[1] + 0), q := qq + nm.Len(0)
        mx := Max(nums*)
        best := Max(best, u = "mm" ? mx / 10 : mx)
    }
    return best
}

PE_TIRADSScore(s) {
    s := StrReplace(s, "&", " and ")
    t := RegExReplace(s, "i)\b(?:no|without|absent|negative\s+for)\s+(?:\w+[\s,]+){0,4}?(?:micro|macro)?calcifications?|\b(?:no|without)\s+(?:\w+\s+){0,3}?echogenic\s+foci", " ")
    t := RegExReplace(t, "i)\b(?:no|without)\s+(?:evidence\s+of\s+)?extra-?\s?thyroidal\s+extension", " ")
    t := RegExReplace(t, "i)\bnot\s+taller[- ]than[- ]wide", " wider-than-tall")
    missing := ""
    if RegExMatch(t, "i)spongiform")
        return {total: 0, detail: "spongiform 0 (inherently benign; no further points added)", missing: ""}
    if RegExMatch(t, "i)mixed|partially\s+cystic|predominantly\s+(?:solid|cystic)|solid\s+and\s+cystic|cystic\s+and\s+solid|complex\s+cystic|cystic\s+(?:and|with)\s+solid|solid\s+(?:with|and)\s+cystic")
        comp := 1, cname := "mixed cystic and solid"
    else if (RegExMatch(t, "i)(?:purely|completely|entirely|almost\s+completely|simple)\s+cystic|\bcyst\b|anechoic\s+cyst|\bcystic\b") && !RegExMatch(t, "i)\bsolid\b"))
        comp := 0, cname := "cystic"
    else if RegExMatch(t, "i)\bsolid\b")
        comp := 2, cname := "solid"
    else
        comp := 2, cname := "solid (composition not stated)", missing .= "composition "
    if (comp = 0)
        echo := 0, ename := "anechoic"
    else if RegExMatch(t, "i)(?:very|markedly)\s+hypoechoic")
        echo := 3, ename := "very hypoechoic"
    else if RegExMatch(t, "i)hypoechoic|hypoechogenic")
        echo := 2, ename := "hypoechoic"
    else if RegExMatch(t, "i)isoechoic|hyperechoic|iso-?\s?echoic|hyper-?\s?echoic|echogenic\s+nodule")
        echo := 1, ename := RegExMatch(t, "i)hyper") ? "hyperechoic" : "isoechoic"
    else if RegExMatch(t, "i)anechoic")
        echo := 0, ename := "anechoic"
    else
        echo := 1, ename := "echogenicity not stated", missing .= "echogenicity "
    if RegExMatch(t, "i)taller[- ]than[- ]wide|anti-?parallel")
        shape := 3, sname := "taller-than-wide"
    else {
        shape := 0, sname := "wider-than-tall"
        if !RegExMatch(t, "i)wider[- ]than[- ]tall|parallel|oval|round")
            sname .= " (shape not stated)"
    }
    if RegExMatch(t, "i)extra-?\s?thyroidal|\bETE\b|invad(?:es|ing)\s+(?:the\s+)?(?:strap|capsule|trachea)")
        margin := 3, mname := "extrathyroidal extension"
    else if RegExMatch(t, "i)lobulated|irregular|spiculated|angular|microlobulated")
        margin := 2, mname := "lobulated/irregular margins"
    else if RegExMatch(t, "i)smooth|well[- ]?(?:defined|circumscribed)|circumscribed|ill[- ]?defined")
        margin := 0, mname := "smooth margins"
    else
        margin := 0, mname := "margins not stated"
    foci := 0, fnames := ""
    if RegExMatch(t, "i)microcalcification|punctate\s+(?:echogenic\s+foci|calcification)|psammoma")
        foci += 3, fnames .= "punctate echogenic foci (3) "
    if RegExMatch(t, "i)peripheral\s+(?:rim\s+)?calcification|rim\s+calcification|eggshell|peripheral\s+calcific|peripheral\s+or\s+rim")
        foci += 2, fnames .= "peripheral calcifications (2) "
    if RegExMatch(t, "i)macro-?\s?calc|coarse\s+calcification|large\s+calcification")
        foci += 1, fnames .= "macrocalcifications (1) "
    if (fnames = "")
        fnames := RegExMatch(t, "i)comet[- ]tail") ? "comet-tail artifacts (0) " : "no echogenic foci (0) "
    total := comp + echo + shape + margin + foci
    detail := cname " " comp " + " ename " " echo " + " sname " " shape " + " mname " " margin " + " RTrim(RegExReplace(Trim(fnames), "\((\d)\)\s*", "$1 + "), " +")
    return {total: total, detail: detail, missing: Trim(missing)}
}

PE_TIRADSLevel(pts) {
    return pts >= 7 ? 5 : pts >= 4 ? 4 : pts = 3 ? 3 : pts = 2 ? 2 : 1
}
PE_TIRADSName(tr) {
    names := ["benign", "not suspicious", "mildly suspicious", "moderately suspicious", "highly suspicious"]
    return names[tr]
}

PE_TIRADSRec(tr, cm) {
    fna := [0, 0, 2.5, 1.5, 1.0], fu := [0, 0, 1.5, 1.0, 0.5]
    when := ["", "", "at 1, 3 and 5 years", "at 1, 2, 3 and 5 years", "yearly for 5 years"]
    if (tr <= 2)
        return "No FNA."
    if (cm >= fna[tr])
        return "FNA recommended."
    if (cm >= fu[tr])
        return "No FNA. Follow-up ultrasound " when[tr] "."
    return "No FNA or follow-up needed."
}

PE_ThyroidLoc(s) {
    loc := ""
    if RegExMatch(s, "i)\bisthmus")
        loc := "isthmus"
    else if PE_RX(s, "i)\b(right|left)\b", m)
        loc := PE_Lower(m[1]) " lobe"
    if (PE_RX(s, "i)\b(upper|mid(?:dle)?|lower|inferior|superior)\s*(?:pole|portion|third)?", p) && loc != "isthmus")
        loc := Trim(loc " " PE_Lower(p[1]) " pole")
    return loc
}

; ================= OVARIAN CYST: O-RADS US + SRU =================
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
    else if PE_RX(t, "i)\b(\d{2})[- ]?(?:year|yr|y)[- ]?(?:old|o\b)", am) {
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
    return PE_Ok("Ovarian Cyst (O-RADS / SRU)", vals, res, meno = "" ? 75 : 90, true)
}

PE_ORADSRec(type, cm, meno) {
    if (type = "simple") {
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
    }
    if (type = "hemorrhagic") {
        if (meno = "pre")
            return cm <= 5 ? "No follow-up needed." : "Follow-up ultrasound in 6-12 weeks to confirm resolution."
        return "Early postmenopause: follow-up ultrasound in 6-12 weeks to confirm resolution; late postmenopause: surgical evaluation."
    }
    if (type = "endometrioma")
        return meno = "pre" ? "Follow-up ultrasound in 6-12 weeks, then yearly if not surgically removed." : "Surgical evaluation may be considered; otherwise follow-up ultrasound in 6-12 weeks, then yearly."
    if (type = "dermoid")
        return "Yearly follow-up ultrasound if not surgically removed."
    return ""
}

; ================= BONE AGE (Greulich & Pyle) =================
PE_AgeMonths(s) {
    s := Trim(RegExReplace(s, "\s+", " "))
    uY := "(?:years?|yrs?|y/?o|y\.?o\.?|y)"
    uM := "(?:months?|mos?|m)"
    if PE_RX(s, "^(\d+)\s*:\s*(\d+)$", m)
        return m[1] * 12 + m[2]
    if PE_RX(s, "^(\d+(?:\.\d+)?)$", m)
        return Round(m[1] * 12)
    if PE_RX(s, "i)(\d+)\s*-?\s*" uY "\.?\s*and\s+(?:a\s+)?half", m)
        return m[1] * 12 + 6
    if PE_RX(s, "i)(\d+)\s*-?\s*" uY "\.?(?:\s*(?:,|and|\+)?\s*(\d+(?:\.\d+)?)\s*-?\s*" uM "\b)", m)
        return m[1] * 12 + Round(m[2] + 0)
    if PE_RX(s, "i)(\d+)\s*(?:-|\s)\s*(\d+)\s*/\s*12\b", m)
        return m[1] * 12 + m[2]
    if PE_RX(s, "i)(\d+)\s*(?:and\s+(?:a\s+)?half|-?\s*1/2|" Chr(0xBD) ")", m)
        return m[1] * 12 + 6
    if PE_RX(s, "i)(\d+)\s*(?:and\s+(?:a\s+)?quarter|-?\s*1/4)", m)
        return m[1] * 12 + 3
    if PE_RX(s, "i)(\d+)\s*(?:and\s+three\s+quarters|-?\s*3/4)", m)
        return m[1] * 12 + 9
    if PE_RX(s, "i)(\d+(?:\.\d+)?)\s*-?\s*" uY "\b", m)
        return Round(m[1] * 12)
    if PE_RX(s, "i)(\d+)\s*-?\s*" uM "\b", m)
        return m[1] + 0
    return ""
}

PE_AgeText(months) {
    months := Round(months)
    y := months // 12, mo := Mod(months, 12)
    return y " year" (y = 1 ? "" : "s") (mo ? " " mo " month" (mo = 1 ? "" : "s") : "")
}

PE_BoneAgeExtract(text) {
    t := RegExReplace(text, "\R", " ")
    r := {chrono: "", sex: "", bone: "", dob: "", examDate: ""}
    if PE_RX(t, "i)bone\s+age\s*(?:is|of|:|=|estimated\s+(?:at|to\s+be)|approximately|approx\.?|consistent\s+with|corresponds\s+to)?\s*(?:approximately\s+|about\s+)?(.{1,40}?)(?:[.;,](?!\d)|\(|$|\s+(?:which|by|per|using|according)|\s+and\s+(?!(?:a\s+)?half|\d))", m)
        r.bone := PE_AgeMonths(m[1])
    if PE_RX(t, "i)(?:chronologic(?:al)?\s+age|actual\s+age|patient(?:'s)?\s+age|(?<!bone\s)(?<!bone)\bage)\s*(?:is|of|:|=)?\s*(.{1,30}?)(?:[.;,](?!\d)|\(|$|\s+(?:male|female|boy|girl|M\b|F\b))", m)
        r.chrono := PE_AgeMonths(m[1])
    if (r.chrono = "" && PE_RX(t, "i)(\d+)[- ](?:year|yr)[- ]?(?:s)?[- ](?:and[- ])?(\d+)[- ]month[- ]?(?:s)?[- ]old", m))
        r.chrono := m[1] * 12 + m[2]
    if (r.chrono = "" && PE_RX(t, "i)(\d+(?:\.\d+)?)[- ]?(?:year|yr)s?[- ]?old|(\d+(?:\.\d+)?)\s*(?:yo|y/o|y\.o\.)\b", m))
        r.chrono := Round((m[1] != "" ? m[1] : m[2]) * 12)
    if (r.chrono = "" && PE_RX(t, "i)(\d+)[- ]month[- ]old", m))
        r.chrono := m[1] + 0
    dateRe := "(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})"
    if PE_RX(t, "i)(?:DOB|D\.O\.B\.|date\s+of\s+birth|birth\s*date|born)\s*:?\s*" dateRe, d) {
        r.dob := PE_Ymd(d[1], d[2], d[3])
        ex := ""
        if PE_RX(t, "i)(?:exam(?:ination)?|study|service|procedure|scan|accession)\s*(?:date|dt)?\s*:?\s*" dateRe, e)
            ex := PE_Ymd(e[1], e[2], e[3])
        r.examDate := ex != "" ? ex : A_YYYY A_MM A_DD
        if (r.dob != "" && r.dob < r.examDate)
            r.chrono := PE_MonthsBetween(r.dob, r.examDate)
    }
    if (PE_RX(t, "i)\b(female|girl|f)\b(?!\.?\s*(?:u|/u))", sx) || PE_RX(t, "i)\b(male|boy|m)\b", sx))
        r.sex := RegExMatch(sx[1], "i)^(?:female|girl|f)$") ? "Female" : "Male"
    if PE_RX(t, "i)\b(?:sex|gender)\s*:?\s*(m|f|male|female)\b", sx)
        r.sex := RegExMatch(sx[1], "i)^f") ? "Female" : "Male"
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
    mo := (SubStr(b, 1, 4) - SubStr(a, 1, 4)) * 12 + (SubStr(b, 5, 2) - SubStr(a, 5, 2))
    if (SubStr(b, 7, 2) + 0 < SubStr(a, 7, 2) + 0)
        mo -= 1
    return mo
}

PE_ParseDate(s) {
    if PE_RX(s, "(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})", d)
        return PE_Ymd(d[1], d[2], d[3])
    return ""
}

; Greulich & Pyle SD (months) by chronological age (months); Brush Foundation data
PE_GPSD(chronoMonths, sex) {
    ages := [3, 6, 9, 12, 18, 24, 30, 36, 42, 48, 54, 60, 72, 84, 96, 108, 120, 132, 144, 156, 168, 180, 192, 204]
    male := [0.72, 1.13, 1.43, 1.97, 3.52, 3.92, 4.52, 5.08, 5.40, 6.66, 8.36, 8.79, 9.17, 8.91, 9.10, 11.00, 11.38, 10.77, 10.44, 10.72, 11.32, 12.86, 13.05, 13.84]
    female := [0.72, 1.16, 1.36, 1.77, 3.49, 4.64, 5.37, 5.97, 7.48, 8.98, 10.73, 11.65, 10.23, 9.64, 10.23, 10.74, 11.73, 11.94, 10.24, 10.67, 11.30, 9.23, 7.31, 7.31]
    sd := (sex = "Female") ? female : male
    n := ages.Length()
    if (chronoMonths <= ages[1])
        return sd[1]
    if (chronoMonths >= ages[n])
        return sd[n]
    Loop % n - 1 {
        i := A_Index
        if (chronoMonths <= ages[i + 1]) {
            f := (chronoMonths - ages[i]) / (ages[i + 1] - ages[i])
            return sd[i] + f * (sd[i + 1] - sd[i])
        }
    }
    return sd[n]
}

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

; ================= AUTO-DETECT =================
PE_Auto(text) {
    t := PE_Clean(text)
    tried := [], tryOrder := [], huCount := 0, pos := 1
    while (p := PE_RX(t, "i)\d\s*(?:HU\b|Hounsfield)", m, pos))
        huCount++, pos := p + m.Len(0)
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
    if IsObject(PE_FindDims(t))
        tryOrder.Push(RegExMatch(t, "i)hemorrhage|hematoma|\bICH\b|\bbleed|intraparenchymal|intracerebral") ? "ICH" : "Volume")
    if RegExMatch(t, "i)nodul|\bGG[NO]|ground[- ]?glass")
        tryOrder.Push("Fleischner")
    if RegExMatch(t, "i)\b(?:\d+|one|two|three|four|six|twelve|an?)[\s-]*(?:days?|weeks?|months?|years?)\b(?![\s-]*old)")
        tryOrder.Push("Date")
    for _, name in tryOrder {
        r := PE_ByName(name, text)
        if (r.ok)
            return r
        tried.Push(name)
    }
    msg := "Could not recognize a calculation in the selected text."
    if (tried.Length()) {
        list := ""
        for _, n in tried
            list .= (list != "" ? ", " : "") n
        msg .= "`n`nTried: " list
    }
    msg .= "`n`nSupported: 3-D volumes, ICH (ABC/2), RV/LV, NASCET / vessel stenosis, adrenal washout (HU), Fleischner nodules, thyroid TI-RADS, ovarian cysts (O-RADS/SRU), follow-up dates."
    return PE_Fail(msg)
}

PE_ByName(name, text) {
    if (name = "Volume")
        return PE_Volume(text)
    if (name = "ICH")
        return PE_ICH(text)
    if (name = "RVLV")
        return PE_RVLV(text)
    if (name = "NASCET")
        return PE_NASCET(text)
    if (name = "Stenosis")
        return PE_Stenosis(text)
    if (name = "Adrenal")
        return PE_Adrenal(text)
    if (name = "Fleischner")
        return PE_Fleischner(text)
    if (name = "Date")
        return PE_Date(text)
    if (name = "TIRADS")
        return PE_TIRADS(text)
    if (name = "ORADS")
        return PE_ORADS(text)
    return PE_Auto(text)
}

; ============================================================
; UI: confirmation dialog, insert, bone age window, menus
; ============================================================

; Right-click menu entries (called from the host's CreateCustomMenu)
SP_AddMenu(menuName, showTIRADS := true, showORADS := true, showBoneAge := false, showLIRADS := false) {
    Menu, SPAsMenu, Add
    Menu, SPAsMenu, DeleteAll
    Menu, SPAsMenu, Add, Volume (prostate graded), SP_MenuItem
    Menu, SPAsMenu, Add, ICH Volume (ABC/2), SP_MenuItem
    Menu, SPAsMenu, Add, RV/LV Ratio, SP_MenuItem
    Menu, SPAsMenu, Add, NASCET (carotid), SP_MenuItem
    Menu, SPAsMenu, Add, Vessel Stenosis (any vessel), SP_MenuItem
    Menu, SPAsMenu, Add, Adrenal Washout, SP_MenuItem
    Menu, SPAsMenu, Add, Fleischner Nodules, SP_MenuItem
    Menu, SPAsMenu, Add, Follow-up Date, SP_MenuItem
    if (showTIRADS || showORADS)
        Menu, SPAsMenu, Add
    if (showTIRADS)
        Menu, SPAsMenu, Add, Thyroid ACR TI-RADS, SP_MenuItem
    if (showORADS)
        Menu, SPAsMenu, Add, Ovarian Cyst (O-RADS / SRU), SP_MenuItem
    Menu, %menuName%, Add, Smart Parse (Auto-detect), SP_MenuAuto
    Menu, %menuName%, Add, Smart Parse as..., :SPAsMenu
    if (showBoneAge)
        Menu, %menuName%, Add, Bone Age (Greulich && Pyle), SP_MenuBoneAge
    if (showLIRADS)
        Menu, %menuName%, Add, Liver LI-RADS (CT/MRI), SP_MenuLIRADS
}

SP_MenuItem(itemName := "", itemPos := "", menuName := "") {
    names := {"Volume (prostate graded)": "Volume", "ICH Volume (ABC/2)": "ICH", "RV/LV Ratio": "RVLV", "NASCET (carotid)": "NASCET"
        , "Vessel Stenosis (any vessel)": "Stenosis", "Adrenal Washout": "Adrenal", "Fleischner Nodules": "Fleischner"
        , "Follow-up Date": "Date", "Thyroid ACR TI-RADS": "TIRADS", "Ovarian Cyst (O-RADS / SRU)": "ORADS"}
    if (g_SelectedText = "") {
        MsgBox, 262192, Smart Parse, % "Highlight the dictated text first, then right-click."
        return
    }
    SP_Run(PE_ByName(names[itemName], g_SelectedText))
}

SP_MenuAuto(itemName := "", itemPos := "", menuName := "") {
    if (SP_ShowBoneAge && RegExMatch(g_SelectedText, "i)bone\s+age")) {
        SP_ShowBoneAgeGui(g_SelectedText)
        return
    }
    if (SP_ShowLIRADS && RegExMatch(g_SelectedText, "i)LI-?RADS|\bAPHE\b|arterial\s+(?:phase\s+)?hyper-?enhanc")) {
        SP_ShowLIRADSGui(g_SelectedText)
        return
    }
    if (g_SelectedText = "") {
        MsgBox, 262192, Smart Parse, % "Highlight the dictated sentence(s) first, then right-click > Smart Parse."
        return
    }
    SP_Run(PE_Auto(g_SelectedText))
}

SP_MenuBoneAge(itemName := "", itemPos := "", menuName := "") {
    SP_ShowBoneAgeGui(g_SelectedText)
}

; Remember the report window to paste back into (host calls this on right-click)
SP_SetTarget(hwnd) {
    SP_TargetHwnd := hwnd
}

SP_Run(r) {
    SP_Init()
    if (!r.ok) {
        MsgBox, 262192, Smart Parse, % r.err
        return
    }
    SP_Result := r
    SP_ShowConfirm(r)
}

SP_ShowConfirm(r) {
    Critical
    prevGui := A_DefaultGui
    if (SP_ConfHwnd)
        SP_CloseConfirm()
    dark := DarkMode
    bg := dark ? "1E1E1E" : "F0F0F0", fg := dark ? "E6E6E6" : "000000"
    accent := dark ? "9CDCFE" : "1F4E79"
    if (r.conf < 50)
        conf := "[!] LOW CONFIDENCE - check the values", cc := dark ? "FF7070" : "C00000"
    else if (r.conf < 80)
        conf := "[~] Medium confidence", cc := dark ? "FFC060" : "A06000"
    else
        conf := "[OK] High confidence", cc := dark ? "70E070" : "008000"
    found := ""
    for _, pair in r.values
        found .= (found != "" ? "`n" : "") pair[1] ": " pair[2]
    preview := Trim(StrReplace(r.text, "`n", "`r`n"), "`r`n ")
    lines := StrSplit(Trim(r.text, "`n "), "`n").Length()
    rows := Min(14, Max(2, lines + 1))

    Gui, SPConf:New, +AlwaysOnTop -MinimizeBox +HwndhC +LabelSPConf_, % "Confirm " r.title
    Gui, SPConf:Color, %bg%, % dark ? "2D2D2D" : "FFFFFF"
    Gui, SPConf:Font, s10 bold c%fg%, Segoe UI
    Gui, SPConf:Add, Text, x10 y10 w440, % r.title
    Gui, SPConf:Font, s10 norm c%fg%
    Gui, SPConf:Add, Text, x10 y+6 w440, Found:
    Gui, SPConf:Font, s10 bold c%accent%
    Gui, SPConf:Add, Text, x20 y+2 w430, % found
    Gui, SPConf:Font, s10 norm c%fg%
    Gui, SPConf:Add, Text, x10 y+8 w440, Will insert:
    Gui, SPConf:Add, Edit, x10 y+2 w440 r%rows% ReadOnly HwndhPrev, % preview
    Gui, SPConf:Font, s10 norm c%cc%
    Gui, SPConf:Add, Text, x10 y+8 w440, % conf
    Gui, SPConf:Font, s10 norm c%fg%
    Gui, SPConf:Add, Button, x10 y+10 w140 Default gSP_BtnInsert HwndhIns, Insert
    Gui, SPConf:Add, Button, x+10 yp w140 gSP_BtnCopy, Copy
    Gui, SPConf:Add, Button, x+10 yp w140 gSP_BtnCancel, Cancel
    SP_ConfHwnd := hC
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    mx += 10, my += 10
    Gui, SPConf:Show, x%mx% y%my% AutoSize
    SendMessage, 0x115, 6, 0, , ahk_id %hPrev%        ; preview scrolled to the top
    if (dark)
        SP_DarkenGui(hC)
    SP_Front(hC)
    GuiControl, SPConf:Focus, %hIns%
    fn := Func("SP_FrontIfNotActive").Bind(hC)
    SetTimer, % fn, -150
    fn2 := Func("SP_FrontIfNotActive").Bind(hC)
    SetTimer, % fn2, -600
    SetTimer, SP_KeepFront, 300
    Gui, %prevGui%:Default
    Critical, Off
}

SP_KeepFront() {
    if (!SP_ConfHwnd || !WinExist("ahk_id " SP_ConfHwnd)) {
        SetTimer, SP_KeepFront, Off
        return
    }
    if SP_IsObscured(SP_ConfHwnd)
        SP_RaiseTop(SP_ConfHwnd)
}

; Lift a window to the top of the always-on-top band without activating it
SP_RaiseTop(h) {
    DllCall("SetWindowPos", "Ptr", h, "Ptr", -2, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    DllCall("SetWindowPos", "Ptr", h, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

; True if another application's window covers part of h (shell UI and our own windows ignored)
SP_IsObscured(h) {
    static shellCls := "i)^(Shell_TrayWnd|Shell_SecondaryTrayWnd|#32768|tooltips_class32|NotifyIconOverflowWindow|TopLevelWindowForOverflowXamlIsland|Windows\.UI\.Core\.CoreWindow|ForegroundStaging|MultitaskingViewFrame|XamlExplorerHostIslandWindow|TaskListThumbnailWnd|Progman|WorkerW)$"
    WinGetPos, x, y, w, hh, ahk_id %h%
    if (x = "")
        return false
    pts := [[x + w // 2, y + hh // 2], [x + 12, y + 12], [x + w - 12, y + 12], [x + 12, y + hh - 12], [x + w - 12, y + hh - 12]]
    for _, p in pts {
        hit := DllCall("WindowFromPoint", "Int64", (p[2] << 32) | (p[1] & 0xFFFFFFFF), "Ptr")
        if (!hit)
            continue
        root := DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr")
        if (!root || root = h)
            continue
        WinGet, rpid, PID, ahk_id %root%
        if (rpid = "" || rpid = SP_Pid)
            continue
        WinGetClass, cls, ahk_id %root%
        if RegExMatch(cls, shellCls)
            continue
        return true
    }
    return false
}

SP_FrontIfNotActive(hwnd) {
    if (WinExist("ahk_id " hwnd) && !WinActive("ahk_id " hwnd))
        SP_Front(hwnd)
}

; Move a window fully onto the monitor under the mouse
SP_FitOnMouseMonitor(hwnd) {
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    WinGetPos, x, y, w, h, ahk_id %hwnd%
    if (x = "")
        return
    l := 0, t := 0, r := A_ScreenWidth, b := A_ScreenHeight
    SysGet, cnt, MonitorCount
    Loop, %cnt% {
        SysGet, mon, MonitorWorkArea, %A_Index%
        if (mx >= monLeft && mx < monRight && my >= monTop && my < monBottom)
            l := monLeft, t := monTop, r := monRight, b := monBottom
    }
    nx := Max(l, Min(x, r - w)), ny := Max(t, Min(y, b - h))
    if (nx != x || ny != y)
        WinMove, ahk_id %hwnd%, , %nx%, %ny%
}

; Bring our window to the very front and give it focus (attach-thread-input trick)
SP_Front(hwnd) {
    SP_FitOnMouseMonitor(hwnd)
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -2, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    fg := DllCall("GetForegroundWindow", "Ptr")
    fgThread := fg ? DllCall("GetWindowThreadProcessId", "Ptr", fg, "Ptr", 0, "UInt") : 0
    myThread := DllCall("GetCurrentThreadId", "UInt")
    attached := (fgThread && fgThread != myThread) ? DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", 1) : 0
    DllCall("BringWindowToTop", "Ptr", hwnd)
    DllCall("SetForegroundWindow", "Ptr", hwnd)
    if (attached)
        DllCall("AttachThreadInput", "UInt", myThread, "UInt", fgThread, "Int", 0)
    WinActivate, ahk_id %hwnd%
}

; Give focus back to the report window before pasting
SP_ActivateTarget() {
    t := SP_TargetHwnd
    if (!t || !WinExist("ahk_id " t))
        return
    WinWaitActive, ahk_id %t%, , 0.5
    if (!ErrorLevel)
        return
    ; WHY: No AttachThreadInput here - it confused the right-click hotkey afterwards.
    DllCall("SetForegroundWindow", "Ptr", t)
    WinWaitActive, ahk_id %t%, , 2.5
    if (ErrorLevel) {
        WinActivate, ahk_id %t%
        WinWaitActive, ahk_id %t%, , 1
    }
    Sleep, 50
}

; Paste text, then restore the user's clipboard. 700 ms: Windows 11 Notepad and
; PowerScribe read the clipboard asynchronously (100 ms pasted the old clipboard).
SP_Paste(text) {
    saved := ClipboardAll
    Clipboard := ""
    Clipboard := text
    ClipWait, 1
    Send, {Shift up}{Ctrl up}^v
    Sleep, 700
    Clipboard := saved
    saved := ""
}

SP_InsertAfterSelection(text) {
    Send, {Right}
    Sleep, 50
    SP_Paste(text)
    SP_Tip("Inserted", 1000)
}

; Tooltip offset from the cursor so it never sits under the mouse (the right-click
; hotkey looks at the window under the mouse)
SP_Tip(msg, ms := 1500) {
    CoordMode, Mouse, Screen
    CoordMode, ToolTip, Screen
    MouseGetPos, mx, my
    ToolTip, %msg%, % mx + 24, % my + 24
    SetTimer, SP_TipOff, % -ms
}

; Fleischner / TI-RADS / O-RADS: end of the report (= end of the IMPRESSION)
SP_InsertAtEnd(text) {
    Send, ^{End}
    Sleep, 80
    SP_Paste(text)
    SP_Tip("Inserted at end of report (after IMPRESSION)", 1500)
}

SP_TipOff() {
    ToolTip
}

SP_BtnInsert(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Critical
    r := SP_Result
    SetTimer, SP_KeepFront, Off
    if !IsObject(r) {
        SP_CloseConfirm()
        return
    }
    ; Focus the report window BEFORE closing the dialog, otherwise Windows may
    ; activate the always-on-top Quick Call panel and the paste goes nowhere.
    Gui, SPConf:Hide          ; Windows usually hands focus straight back to the report
    SP_ActivateTarget()       ; ...if not (e.g. it went to the Quick Call panel), ask for it
    if (r.atImpression && SP_FleischnerAtEnd)
        SP_InsertAtEnd(r.text)
    else
        SP_InsertAfterSelection(r.text)
    SP_CloseConfirm()
}

SP_BtnCopy(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    if IsObject(SP_Result)
        Clipboard := Trim(SP_Result.text, "`n ")
    SP_Tip("Copied to clipboard")
}

SP_BtnCancel(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    SP_CloseConfirm()
}
SPConf_Close(GuiHwnd := 0) {
    SP_CloseConfirm()
}
SPConf_Escape(GuiHwnd := 0) {
    SP_CloseConfirm()
}

SP_CloseConfirm() {
    SetTimer, SP_KeepFront, Off
    Gui, SPConf:Destroy
    SP_ConfHwnd := 0
}

; ---------------- Bone age window ----------------
SP_ShowBoneAgeGui(prefill := "") {
    SP_Init()
    prevGui := A_DefaultGui
    x := PE_BoneAgeExtract(prefill)
    dark := DarkMode
    bg := dark ? "1E1E1E" : "F0F0F0", fg := dark ? "E6E6E6" : "000000"
    bone := x.bone != "" ? PE_AgeText(x.bone) : ""
    chrono := (x.chrono != "" && x.dob = "") ? PE_AgeText(x.chrono) : ""
    dob := x.dob != "" ? PE_FormatTime(x.dob, "M/d/yyyy") : ""
    exam := x.examDate != "" ? PE_FormatTime(x.examDate, "M/d/yyyy") : PE_FormatTime(A_Now, "M/d/yyyy")
    sexOpt := x.sex = "Male" ? "Choose1" : x.sex = "Female" ? "Choose2" : ""
    Gui, SPBone:New, +AlwaysOnTop -MinimizeBox +HwndhB +LabelSPBone_, Bone Age (Greulich & Pyle)
    Gui, SPBone:Color, %bg%, % dark ? "2D2D2D" : "FFFFFF"
    Gui, SPBone:Font, s10 c%fg%, Segoe UI
    Gui, SPBone:Add, Text, x10 y12 w160, Bone age (as read):
    Gui, SPBone:Add, Edit, x175 y9 w230 vSPB_Bone gSPB_Update, %bone%
    Gui, SPBone:Add, Text, x10 y+12 w160, Chronological age:
    Gui, SPBone:Add, Edit, x175 yp-3 w230 vSPB_Chrono gSPB_Update, %chrono%
    Gui, SPBone:Add, Text, x10 y+12 w160, or DOB  /  exam date:
    Gui, SPBone:Add, Edit, x175 yp-3 w110 vSPB_Dob gSPB_Update, %dob%
    Gui, SPBone:Add, Edit, x+10 yp w110 vSPB_Exam gSPB_Update, %exam%
    Gui, SPBone:Add, Text, x10 y+12 w160, Sex:
    Gui, SPBone:Add, DropDownList, x175 yp-3 w110 vSPB_Sex gSPB_Update %sexOpt%, Male|Female
    Gui, SPBone:Add, Button, x295 yp-1 w110 gSPB_ReadReport, Read report
    Gui, SPBone:Font, s8 c808080
    Gui, SPBone:Add, Text, x10 y+8 w400, Any style works: 13 years 6 months, 13y6m, 13.5, 13 1/2, 13 6/12, 13:6, 162 months
    Gui, SPBone:Font, s10 c%fg%
    Gui, SPBone:Add, Edit, x10 y+6 w395 r7 ReadOnly vSPB_Preview
    Gui, SPBone:Add, Button, x10 y+10 w125 Default gSPB_Insert, Insert
    Gui, SPBone:Add, Button, x+10 yp w125 gSPB_Copy, Copy
    Gui, SPBone:Add, Button, x+10 yp w125 gSPB_Cancel, Cancel
    SP_BoneHwnd := hB
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    mx += 10, my += 10
    Gui, SPBone:Show, x%mx% y%my% AutoSize
    if (dark)
        SP_DarkenGui(hB)
    SP_Front(hB)
    GuiControl, SPBone:Focus, SPB_Bone
    SPB_Update()
    Gui, %prevGui%:Default
}

SPB_Update(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    if (!SP_BoneHwnd)
        return
    Gui, SPBone:Submit, NoHide
    bone := PE_AgeMonths(SPB_Bone)
    dob := PE_ParseDate(SPB_Dob), exam := PE_ParseDate(SPB_Exam)
    chrono := (dob != "" && exam != "" && dob < exam) ? PE_MonthsBetween(dob, exam) : PE_AgeMonths(SPB_Chrono)
    SP_BoneText := ""
    if (bone = "")
        msg := "Type the bone age above."
    else if (chrono = "")
        msg := "Enter the chronological age, or DOB and exam date."
    else if (SPB_Sex = "")
        msg := "Select the sex."
    else {
        r := PE_BoneAgeReport(bone, chrono, SPB_Sex)
        SP_BoneText := r.text
        msg := Trim(r.text)
    }
    GuiControl, SPBone:, SPB_Preview, %msg%
}

SPB_ReadReport(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    SP_ActivateTarget()
    saved := ClipboardAll
    Clipboard := ""
    Send, ^a
    Sleep, 50
    Send, ^c
    ClipWait, 1
    txt := ErrorLevel ? "" : Clipboard
    Clipboard := saved
    saved := ""
    Send, {Right}
    if (txt = "") {
        MsgBox, 262192, Bone Age, Could not read the report text.
        return
    }
    x := PE_BoneAgeExtract(txt)
    if (x.dob != "") {
        GuiControl, SPBone:, SPB_Dob, % PE_FormatTime(x.dob, "M/d/yyyy")
        GuiControl, SPBone:, SPB_Exam, % PE_FormatTime(x.examDate, "M/d/yyyy")
    } else if (x.chrono != "") {
        GuiControl, SPBone:, SPB_Chrono, % PE_AgeText(x.chrono)
    }
    if (x.sex != "")
        GuiControl, SPBone:Choose, SPB_Sex, % (x.sex = "Male" ? 1 : 2)
    GuiControlGet, curBone, SPBone:, SPB_Bone
    if (x.bone != "" && curBone = "")
        GuiControl, SPBone:, SPB_Bone, % PE_AgeText(x.bone)
    SP_Front(SP_BoneHwnd)
    SPB_Update()
}

SPB_Insert(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Critical
    SPB_Update()
    if (SP_BoneText = "") {
        MsgBox, 262192, Bone Age, % "Fill in bone age, chronological age and sex first."
        return
    }
    txt := SP_BoneText
    SP_ActivateTarget()
    Gui, SPBone:Hide
    SP_InsertAfterSelection(txt)
    SPB_Cancel()
}

SPB_Copy(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    SPB_Update()
    if (SP_BoneText = "")
        return
    Clipboard := Trim(SP_BoneText)
    SP_Tip("Copied to clipboard")
}

SPB_Cancel(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Gui, SPBone:Destroy
    SP_BoneHwnd := 0
}
SPBone_Close(GuiHwnd := 0) {
    SPB_Cancel()
}
SPBone_Escape(GuiHwnd := 0) {
    SPB_Cancel()
}

; ================= LIVER: ACR LI-RADS CT/MRI v2018 =================
; Diagnostic table for an untreated observation in a high-risk patient.
; PE_LIRADSExtract pre-fills the window from highlighted dictation; the
; radiologist confirms every feature in the window before inserting.
PE_LIRADSExtract(text) {
    t := " " RegExReplace(StrReplace(text, Chr(0xD7), "x"), "\s+", " ") " "
    ; "peripheral washout" (LR-M feature) vs nonperipheral washout (major feature)
    t := RegExReplace(t, "i)(?<!non)(?<!non-)(?<!non )peripheral\s+wash-?\s?out", "PERIPHWO")
    x := {}
    x.rim := PE_LRHas(t, "(?<!non)(?<!non-)(?<!non )\brim\s+(?:arterial\s+(?:phase\s+)?)?(?:APHE|hyper-?enhanc)")
    x.aphe := PE_LRHas(t, "\bnon-?\s?rim\s+(?:APHE|arterial|hyper)|\bAPHE\b|arterial(?:\s+phase)?\s+hyper-?enhanc|hyper-?enhanc\w*\s+(?:\w+\s+){0,2}arterial|arterially\s+(?:hyper-?)?enhanc|hypervascular")
    if (x.rim && !PE_LRHas(t, "\bnon-?\s?rim"))
        x.aphe := false
    x.washout := PE_LRHas(t, "wash-?\s?out|de-?enhanc|hypo-?enhanc\w*\s+(?:\w+\s+){0,2}(?:portal|venous|delayed|transitional)")
    x.capsule := PE_LRHas(t, "(?<!sub)(?<!Glisson)(?<!Glisson's )(?<!liver )(?<!hepatic )capsul")
    x.growth := PE_LRHas(t, "threshold\s+growth")
    x.tiv := PE_LRHas(t, "tumou?r\s+in\s+(?:the\s+)?vein|tumou?r\s+thromb|enhancing\s+(?:soft\s+tissue|thrombus)\s+(?:in|within|filling)\s+(?:the\s+)?(?:\w+\s+){0,3}vein|LR-?TIV")
    x.lrm := x.rim || PE_LRHas(t, "targetoid|PERIPHWO|delayed\s+central\s+enhancement|\bLR-?M\b")
    ; size: largest dimension in a sentence about the observation
    mm := 0
    for _, s in StrSplit(RegExReplace(t, "(?<!\d)\.(?!\d)|;", "`n"), "`n") {
        if RegExMatch(s, "i)observation|lesion|nodule|mass|focus|\bLR-?\d|APHE|enhanc")
            mm := Max(mm, PE_TIRADSSize(s) * 10)
    }
    x.mm := mm
    return x
}

; True if the pattern occurs without "no / without / absent ..." just before it
; (same clause: stops at . ; , boundaries).
PE_LRHas(t, pat) {
    pos := 1
    while (p := RegExMatch(t, "i)" pat, m, pos)) {
        pre := SubStr(t, Max(1, p - 45), Min(45, p - 1))
        pre := RegExReplace(pre, "^.*[.;,]")
        post := SubStr(t, p + StrLen(m), 40)
        post := RegExReplace(post, "[.;,].*$")
        negPre := RegExMatch(pre, "i)\b(?:no|without|absent|absence\s+of|negative\s+for|not|lacks?|lack\s+of)\b")
        negPost := RegExMatch(post, "i)^\s*(?:is\s+|are\s+|was\s+)?(?:not\s+(?:seen|identified|present|demonstrated|evident)|absent)")
        if (!negPre && !negPost)
            return true
        pos := p + Max(1, StrLen(m))
    }
    return false
}

; anc: 1 = none, 2 = favor malignancy, 3 = favor benignity
; ovr: 1 = from features, 2 = LR-1, 3 = LR-2, 4 = LR-NC
PE_LIRADSCalc(mm, aphe, wo, cap, tg, anc, tiv, lrm, ovr) {
    r := {cat: "", base: "", note: ""}
    if (ovr = 2)
        r.cat := "LR-1"
    else if (ovr = 3)
        r.cat := "LR-2"
    else if (ovr = 4)
        r.cat := "LR-NC"
    else if (tiv)
        r.cat := "LR-TIV"
    else if (lrm)
        r.cat := "LR-M"
    if (r.cat != "")
        return r
    if (mm <= 0)
        return r
    n := wo + cap + tg
    if (!aphe)
        c := (mm < 20) ? (n >= 2 ? 4 : 3) : (n = 0 ? 3 : 4)
    else if (mm < 10)
        c := (n = 0) ? 3 : 4
    else if (mm < 20)
        c := (n = 0) ? 3 : (n >= 2 || wo || tg) ? 5 : 4
    else
        c := (n = 0) ? 4 : 5
    r.base := "LR-" c
    if (anc = 2 && c < 4)
        c += 1, r.note := "Ancillary features favor malignancy: upgraded from " r.base " (upgrade limited to LR-4)."
    else if (anc = 2)
        r.note := "Ancillary features favor malignancy (no upgrade above LR-4 / to LR-5)."
    else if (anc = 3)
        c -= 1, r.note := "Ancillary features favor benignity: downgraded from " r.base "."
    r.cat := "LR-" c
    return r
}

PE_LIRADSName(cat) {
    static names := {"LR-1": "definitely benign", "LR-2": "probably benign", "LR-3": "intermediate probability of malignancy"
        , "LR-4": "probably HCC", "LR-5": "definitely HCC", "LR-M": "probably or definitely malignant, not HCC specific"
        , "LR-TIV": "tumor in vein", "LR-NC": "not categorizable"}
    return names[cat]
}

PE_LIRADSMgmt(cat) {
    static m := {"LR-NC": "Repeat or alternative diagnostic imaging in 3 months or less."
        , "LR-1": "Return to surveillance in 6 months."
        , "LR-2": "Return to surveillance in 6 months. Consider repeat diagnostic imaging in 6 months or less."
        , "LR-3": "Repeat or alternative diagnostic imaging in 3-6 months."
        , "LR-4": "Multidisciplinary discussion for tailored workup, which may include biopsy."
        , "LR-5": "Multidisciplinary discussion for consensus management."
        , "LR-M": "Multidisciplinary discussion for tailored workup, often including biopsy."
        , "LR-TIV": "Multidisciplinary discussion for tailored workup, which may include biopsy."}
    return m[cat]
}

PE_LIRADSText(mm, aphe, wo, cap, tg, anc, tiv, lrm, ovr) {
    r := PE_LIRADSCalc(mm, aphe, wo, cap, tg, anc, tiv, lrm, ovr)
    if (r.cat = "")
        return ""
    out := "`n`nLI-RADS (CT/MRI v2018): " r.cat ", " PE_LIRADSName(r.cat) "."
    if (ovr = 1 && !tiv && !lrm) {
        f := (aphe ? "nonrim APHE" : "no nonrim APHE")
        if (wo)
            f .= ", nonperipheral washout"
        if (cap)
            f .= ", enhancing capsule"
        if (tg)
            f .= ", threshold growth"
        out .= "`nObservation: " PE_Fmt(mm) " mm; " f "."
        if (r.note != "")
            out .= "`n" r.note
    }
    out .= "`nRecommendation: " PE_LIRADSMgmt(r.cat)
    if (ShowCitations)
        out .= "`nRef: ACR CT/MRI LI-RADS v2018 Core."
    return out
}

; ---------------- LI-RADS window ----------------
SP_ShowLIRADSGui(prefill := "") {
    SP_Init()
    prevGui := A_DefaultGui
    x := PE_LIRADSExtract(prefill)
    dark := DarkMode
    bg := dark ? "1E1E1E" : "F0F0F0", fg := dark ? "E6E6E6" : "000000"
    sz := x.mm > 0 ? PE_Fmt(x.mm) : ""
    aphe := x.aphe ? 1 : 0, wo := x.washout ? 1 : 0, cap := x.capsule ? 1 : 0
    tg := x.growth ? 1 : 0, tiv := x.tiv ? 1 : 0, lrm := x.lrm ? 1 : 0
    Gui, SPLR:New, +AlwaysOnTop -MinimizeBox +HwndhL +LabelSPLR_, LI-RADS CT/MRI v2018
    Gui, SPLR:Color, %bg%, % dark ? "2D2D2D" : "FFFFFF"
    Gui, SPLR:Font, s10 c%fg%, Segoe UI
    Gui, SPLR:Add, Text, x10 y12 w190, Observation size (mm):
    Gui, SPLR:Add, Edit, x205 y9 w70 vSPL_Size gSPL_Update, %sz%
    Gui, SPLR:Add, Checkbox, x10 y+10 w420 vSPL_APHE gSPL_Update Checked%aphe%, Nonrim arterial phase hyperenhancement (APHE)
    Gui, SPLR:Font, s10 bold c%fg%
    Gui, SPLR:Add, Text, x10 y+10 w420, Additional major features
    Gui, SPLR:Font, s10 norm c%fg%
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_WO gSPL_Update Checked%wo%, Nonperipheral washout
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_Cap gSPL_Update Checked%cap%, Enhancing capsule
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_TG gSPL_Update Checked%tg%, Threshold growth (size up 50`% or more in 6 months or less)
    Gui, SPLR:Add, Text, x10 y+12 w140, Ancillary features:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPL_Anc gSPL_Update AltSubmit Choose1, None / not applied|Favor malignancy (up 1, max LR-4)|Favor benignity (down 1)
    Gui, SPLR:Font, s10 bold c%fg%
    Gui, SPLR:Add, Text, x10 y+12 w420, These take precedence
    Gui, SPLR:Font, s10 norm c%fg%
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_TIV gSPL_Update Checked%tiv%, Tumor in vein (LR-TIV)
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 r2 vSPL_LRM gSPL_Update Checked%lrm%, LR-M features (targetoid, rim APHE, peripheral washout, delayed central enhancement)
    Gui, SPLR:Add, Text, x10 y+12 w140, Category:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPL_Ovr gSPL_Update AltSubmit Choose1, From the features above|LR-1 Definitely benign|LR-2 Probably benign|LR-NC Cannot be categorized
    Gui, SPLR:Font, s8 c808080
    Gui, SPLR:Add, Text, x10 y+8 w420, For untreated observations in high-risk patients (cirrhosis, chronic hepatitis B, current or prior HCC). Pre-filled from the highlighted text: check every box before inserting.
    Gui, SPLR:Font, s10 c%fg%
    Gui, SPLR:Add, Edit, x10 y+6 w420 r6 ReadOnly vSPL_Preview
    Gui, SPLR:Add, Button, x10 y+10 w133 Default gSPL_Insert, Insert
    Gui, SPLR:Add, Button, x+10 yp w133 gSPL_Copy, Copy
    Gui, SPLR:Add, Button, x+10 yp w134 gSPL_Cancel, Cancel
    SP_LRHwnd := hL
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    mx += 10, my += 10
    Gui, SPLR:Show, x%mx% y%my% AutoSize
    if (dark)
        SP_DarkenGui(hL)
    SP_FitOnMouseMonitor(hL)
    SP_Front(hL)
    GuiControl, SPLR:Focus, SPL_Size
    SPL_Update()
    Gui, %prevGui%:Default
}

SPL_Update(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    if (!SP_LRHwnd)
        return
    Gui, SPLR:Submit, NoHide
    mm := RegExReplace(SPL_Size, "[^\d.]")
    mm := PE_IsNum(mm) ? mm + 0 : 0
    SP_LRText := PE_LIRADSText(mm, SPL_APHE, SPL_WO, SPL_Cap, SPL_TG, SPL_Anc, SPL_TIV, SPL_LRM, SPL_Ovr)
    msg := SP_LRText != "" ? Trim(SP_LRText, "`n") : "Enter the observation size (mm)."
    GuiControl, SPLR:, SPL_Preview, %msg%
}

SPL_Insert(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Critical
    SPL_Update()
    if (SP_LRText = "") {
        MsgBox, 262192, LI-RADS, Enter the observation size first.
        return
    }
    txt := SP_LRText
    SP_ActivateTarget()
    Gui, SPLR:Hide
    if (SP_FleischnerAtEnd)
        SP_InsertAtEnd(txt)
    else
        SP_InsertAfterSelection(txt)
    SPL_Cancel()
}

SPL_Copy(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    SPL_Update()
    if (SP_LRText = "")
        return
    Clipboard := Trim(SP_LRText, "`n")
    SP_Tip("Copied to clipboard")
}

SPL_Cancel(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Gui, SPLR:Destroy
    SP_LRHwnd := 0
}
SPLR_Close(GuiHwnd := 0) {
    SPL_Cancel()
}
SPLR_Escape(GuiHwnd := 0) {
    SPL_Cancel()
}

SP_MenuLIRADS(itemName := "", itemPos := "", menuName := "") {
    SP_ShowLIRADSGui(g_SelectedText)
}
; <<< SMARTPARSE END
