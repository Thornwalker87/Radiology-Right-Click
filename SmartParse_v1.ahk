; ============================================================
; SmartParse v1  (AutoHotkey v1.1 port of the RadAssist v2 smart-parse engine)
; Used by "Radiology Right Click v1.22.ahk" / "-local.ahk" (embedded between the
; SMARTPARSE BEGIN/END markers - edit this file, then re-embed).
;
; Highlight dictated text -> right-click -> Smart Parse (Auto-detect) or Smart Parse as...
;   Volume (prostate graded), ICH ABC/2, RV/LV, NASCET / any-vessel stenosis,
;   adrenal washout, Fleischner 2017, follow-up date, ACR TI-RADS, ovarian cyst
;   (O-RADS US + SRU), Bone age (Greulich & Pyle) window, LI-RADS window (CT/MRI v2018,
;   CEUS v2027, US Surveillance v2024, Treatment Response v2024).
; Every PE_* function is pure (text in, result object out) so it can be tested
; without any GUI. Results: {ok, title, values: [[label, value], ...], text, conf,
; atImpression} or {ok: false, err}.
;
; Requires AutoHotkey v1.1.27+. Plain ASCII on purpose (AHK v1 reads it with no BOM).
; NOTE: No auto-execute code: the host calls SP_Init() once at startup.
; ============================================================

global SP_Result, SP_TargetHwnd, SP_ConfHwnd, SP_BoneHwnd, SP_BoneText
global SP_DataminingPhrase, SP_IncludeDatamining, SP_FleischnerAtEnd, SP_RVLVFormat
global SPB_Bone, SPB_Chrono, SPB_Dob, SPB_Exam, SPB_Sex, SPB_Preview    ; bone age GUI controls
global SP_Initialized, SP_Pid
global SP_ShowParse, SP_ShowTIRADS, SP_ShowORADS, SP_ShowBoneAge     ; set by the host (Preferences)
global SP_ShowLIRADS                                                  ; set by the host (Preferences, off by default)
global SP_LRHwnd, SP_LRText, SPL_Size, SPL_APHE, SPL_WO, SPL_Cap, SPL_TG, SPL_Anc, SPL_TIV, SPL_LRM, SPL_Ovr, SPL_Preview   ; LI-RADS GUI
global SP_LRMode, SP_LRPrefill, SP_LRCeusAgent, SP_LRLastTx, SPL_Mode
global SPC_Size, SPC_Agent, SPC_APHE, SPC_WO, SPC_Anc, SPC_TIV, SPC_Ovr, SPC_Adq      ; CEUS LI-RADS controls
global SPU_Cat, SPU_Vis, SPU_AFP, SPU_Risk                                          ; US surveillance controls
global SPT_Tx, SPT_Mass, SPT_AF, SPT_Intra, SPT_Peri, SPT_NE, SPT_Size               ; treatment response controls

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
    ; Impression sentence: "Multiple solid pulmonary nodules, the largest measuring 7 mm in the right upper lobe."
    big := found[1], nTypes := 0, seen := {}
    for _, f in found {
        if !seen.HasKey(f.type)
            seen[f.type] := true, nTypes++
        if (f.size > big.size)
            big := f
    }
    tn := {solid: "solid", subsolid: "ground-glass", "part-solid": "part-solid"}
    mix := ""
    for _, k in ["solid", "part-solid", "subsolid"]
        if seen.HasKey(k)
            mix .= (mix != "" ? " and " : "") tn[k]
    if (nTypes = 1)
        typeDesc := tn[big.type] " "
    else
        typeDesc := ""
    sizeTxt := big.sub6 ? "less than 6 mm" : PE_Fmt(big.size) " mm"
    if (isMultiple)
        r := "`n`nMultiple " typeDesc "pulmonary nodules" (typeDesc = "" ? " (" mix ")" : "")
            . ", the largest measuring " sizeTxt (typeDesc = "" ? " (" tn[big.type] ")" : "")
    else
        r := "`n`nSingle " typeDesc "pulmonary nodule measuring " sizeTxt
    r .= (big.lobe != "" ? " in the " big.lobe : "") ". Recommendations for follow-up as detailed below."
    r .= "`n`n___________________________________________________________`n"
    r .= "Incidental Lung Nodule Discussion:`n"
    r .= "2017 ACR Fleischner Society expert consensus recommendations on incidental pulmonary nodules.`n"
    r .= "Target Demographic: 35+ years without known cancer or immunosuppressive disorder.`n"
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
    r .= "`nRef: MacMahon H et al. Radiology 2017;284:228-243"     ; Fleischner reference always shown
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
    side := ""
    if PE_RX(t, "i)\b(right|left)\s+(?:\w+\s+){0,3}?(?:ovar|adnex)", sm)
        side := Format("{:T}", sm[1]) " "
    else if PE_RX(t, "i)(?:ovar|adnex)\w*\s+(?:\w+\s+){0,3}?(?:on\s+the\s+)?(right|left)\b", sm)
        side := Format("{:T}", sm[1]) " "
    dx := {hemorrhagic: "compatible with a hemorrhagic cyst", endometrioma: "compatible with an endometrioma"
        , dermoid: "compatible with a dermoid (mature cystic teratoma)"}
    if (cm >= 10) {
        cat := "O-RADS US 3 (low risk)"
        recTxt := "Classic benign-appearing lesion 10 cm or larger: management by gynecologist; consider MRI (O-RADS MRI)."
    } else {
        cat := (type = "simple" && cm <= 3 && meno != "post") ? "O-RADS US 1 (normal ovary, physiologic follicle)" : "O-RADS US 2 (almost certainly benign)"
        if (type = "simple" && cm <= 3 && meno = "")
            cat := "O-RADS US 1 if premenopausal (physiologic follicle), O-RADS US 2 if postmenopausal"
        if (meno = "")
            recTxt := "`n- If premenopausal: " PE_ORADSRec(type, cm, "pre") "`n- If postmenopausal: " PE_ORADSRec(type, cm, "post")
        else
            recTxt := "(" meno "menopausal): " PE_ORADSRec(type, cm, meno)
    }
    side1 := (side != "" ? side "ovarian" : "Ovarian") (type = "simple" ? " simple" : "")
    res := "`n`n" side1 " cyst (" PE_Fmt(cm) " cm)" (type = "simple" ? "" : " " dx[type]) ". " cat "."
    res .= "`nRecommendation" (SubStr(recTxt, 1, 1) = "(" ? " " recTxt : (SubStr(recTxt, 1, 1) = "`n" ? ":" recTxt : ": " recTxt))
    if (ShowCitations)
        res .= "`n`nRef: O-RADS US v2022 (ACR); follow-up per SRU consensus (Levine et al. Radiology 2010;256:943-954 and 2019;293:359-371)."
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
    if (showLIRADS) {
        Menu, SPLiverMenu, Add
        Menu, SPLiverMenu, DeleteAll
        Menu, SPLiverMenu, Add, CT/MRI diagnostic (v2018), SP_MenuLIRADS
        Menu, SPLiverMenu, Add, CEUS diagnostic (v2027), SP_MenuLIRADS
        Menu, SPLiverMenu, Add, US surveillance (v2024), SP_MenuLIRADS
        Menu, SPLiverMenu, Add, Treatment response (v2024), SP_MenuLIRADS
        Menu, %menuName%, Add, Liver LI-RADS, :SPLiverMenu
    }
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
    if (SP_ShowLIRADS && RegExMatch(g_SelectedText, "i)LI-?RADS|\bAPHE\b|arterial\s+(?:phase\s+)?hyper-?enhanc|\bCEUS\b|\bLR-?TR\b|\bVIS-?\s?[ABC]\b")) {
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

; ================= LIVER: ACR LI-RADS =================
; Modules (ACR LI-RADS site, Nov 2026): CT/MRI diagnostic v2018 | CEUS diagnostic v2027 |
; US Surveillance v2024 | Treatment Response v2024 (CT/MRI nonradiation, CT/MRI radiation,
; CEUS nonradiation). CT/MRI diagnostic table: untreated observation, high-risk patient.
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

; ---------------- CEUS LI-RADS v2027 (diagnostic) ----------------
; aphe: 1 none, 2 nonrim APHE, 3 rim APHE followed by washout of the rim (LR-M),
;       4 rim APHE without rim washout, 5 peripheral discontinuous nodular (hemangioma)
; wo:   1 none, 2 late (>=60 s) and mild [KCA: mild hypoenhancement 1-2 min or any 2-5 min],
;       3 early (<60 s) washout, 4 marked washout / KCA hypoenhancement at <2 min
PE_CEUSExtract(text) {
    t := " " RegExReplace(StrReplace(text, Chr(0xD7), "x"), "\s+", " ") " "
    x := {mm: 0, aphe: 1, wo: 1, agent: 1, tiv: false}
    if RegExMatch(t, "i)sonazoid|perfluorobutane|kupffer")
        x.agent := 2
    sec := ""
    if RegExMatch(t, "i)wash-?\s?out\D{0,30}?(\d+)\s*(?:s\b|sec)", m)
        sec := m1
    else if RegExMatch(t, "i)(\d+)\s*(?:s|sec\w*)\b\D{0,20}wash-?\s?out", m)
        sec := m1
    if PE_LRHas(t, "marked\s+(?:\w+\s+)?(?:wash-?\s?out|hypo-?enhanc)|punched[- ]out")
        x.wo := 4
    else if (PE_LRHas(t, "early\s+(?:\w+\s+)?wash-?\s?out") || (sec != "" && sec < 60))
        x.wo := 3
    else if PE_LRHas(t, "wash-?\s?out|hypo-?enhanc")
        x.wo := 2
    if PE_LRHas(t, "peripheral\s+(?:discontinuous\s+)?nodular|discontinuous\s+nodular")
        x.aphe := 5
    else if PE_LRHas(t, "(?<!non)(?<!non-)(?<!non )\brim\s+(?:arterial\s+(?:phase\s+)?)?(?:APHE|hyper-?enhanc|enhanc)")
        x.aphe := (x.wo >= 2) ? 3 : 4
    else if PE_LRHas(t, "\bAPHE\b|arterial(?:\s+phase)?\s+hyper-?enhanc|hyper-?enhanc\w*\s+(?:\w+\s+){0,2}arterial|arterially\s+(?:hyper-?)?enhanc")
        x.aphe := 2
    x.tiv := PE_LRHas(t, "tumou?r\s+in\s+(?:the\s+)?vein|tumou?r\s+thromb|LR-?TIV")
    for _, s in StrSplit(RegExReplace(t, "(?<!\d)\.(?!\d)|;", "`n"), "`n")
        if RegExMatch(s, "i)observation|lesion|nodule|mass|focus|\bLR-?\d|APHE|enhanc")
            x.mm := Max(x.mm, PE_TIRADSSize(s) * 10)
    return x
}

; anc: 1 none, 2 favor malignancy, 3 favor benignity; ovr: 1 features, 2 LR-1, 3 LR-2, 4 LR-NC
PE_CEUSCalc(mm, aphe, wo, anc, tiv, ovr) {
    r := {cat: "", base: "", note: ""}
    if (ovr = 2)
        r.cat := "LR-1"
    else if (ovr = 3)
        r.cat := "LR-2"
    else if (ovr = 4)
        r.cat := "LR-NC"
    else if (tiv)
        r.cat := "LR-TIV"
    else if (aphe = 5)
        r.cat := "LR-1", r.note := "Peripheral discontinuous nodular enhancement indicates hemangioma."
    else if (aphe = 3)
        r.cat := "LR-M", r.note := "Rim APHE followed by washout of rim-enhancing components."
    else if (wo = 3)
        r.cat := "LR-M", r.note := "Early (<60 s) washout."
    else if (wo = 4)
        r.cat := "LR-M", r.note := "Marked washout / hypoenhancement at <2 min."
    if (r.cat != "" || mm <= 0)
        return r
    if (aphe = 4)
        r.note := "Rim APHE without washout of the rim does not meet LR-M criteria (v2027); scored as no APHE."
    hasAphe := (aphe = 2), hasWo := (wo = 2)
    if (!hasAphe)
        c := (hasWo && mm >= 20) ? 4 : 3
    else if (mm < 10)
        c := hasWo ? 4 : 3
    else
        c := hasWo ? 5 : 4
    r.base := "LR-" c
    if (anc = 2 && c < 4)
        c += 1, r.note := Trim(r.note " Ancillary features favor malignancy: upgraded from " r.base " (limited to LR-4).")
    else if (anc = 3 && c = 5)
        r.note := Trim(r.note " Ancillary features favoring benignity cannot downgrade LR-5 (v2027).")
    else if (anc = 3)
        c -= 1, r.note := Trim(r.note " Ancillary features favor benignity: downgraded from " r.base ".")
    r.cat := "LR-" c
    return r
}

PE_CEUSMgmt(cat) {
    static m := {"LR-NC": "Alternative diagnostic imaging (CT or MRI) in 3 months or less (preferred), or repeat CEUS in 3 months or less if a technique correction would allow diagnostic imaging."
        , "LR-1": "Return to routine surveillance in 6 months."
        , "LR-2": "Return to routine surveillance in 6 months, or alternative diagnostic imaging (CT or MRI) in 6 months or less."
        , "LR-3": "Alternative diagnostic imaging (CT or MRI) in 3 months or less (preferred), or repeat CEUS in 3 months or less. Multidisciplinary discussion may be needed."
        , "LR-4": "Multidisciplinary discussion may be needed for consensus management. If neither biopsy, CT/MRI, nor treatment is planned, repeat or alternative diagnostic imaging in 3 months or less."
        , "LR-5": "Diagnostic of HCC. Multidisciplinary discussion for consensus management."
        , "LR-M": "Multidisciplinary discussion for consensus management; often includes biopsy, alternative or repeat imaging, or treatment."
        , "LR-TIV": "Multidisciplinary discussion for consensus management; may include biopsy or biomarker correlation to determine the etiology of the tumor in vein."}
    return m[cat]
}

PE_CEUSText(mm, agent, aphe, wo, anc, tiv, ovr, adq) {
    r := PE_CEUSCalc(mm, aphe, wo, anc, tiv, ovr)
    if (r.cat = "")
        return ""
    name := (r.cat = "LR-M") ? "probably or definitely malignant, not necessarily HCC" : PE_LIRADSName(r.cat)
    out := "`n`nCEUS LI-RADS (v2027): CEUS " r.cat ", " name "."
    adqName := ["A (no or minimal limitations)", "B (moderate limitations)", "C (severe limitations)"]
    if (ovr = 1 && !tiv) {
        apheTxt := ["no APHE", "nonrim APHE", "rim APHE with washout of the rim", "rim APHE without rim washout", "peripheral discontinuous nodular enhancement"]
        woTxt := (agent = 2) ? ["no hypoenhancement at 1-5 min", "mild hypoenhancement at 1-2 min or hypoenhancement at 2-5 min", "early (<60 s) washout", "marked hypoenhancement at <2 min"]
                            : ["no washout", "late (60 s or later) and mild washout", "early (<60 s) washout", "marked washout at <2 min"]
        out .= "`nNodule: " (mm > 0 ? PE_Fmt(mm) " mm; " : "") (agent = 2 ? "Kupffer-cell agent" : "blood-pool agent") "; " apheTxt[aphe] "; " woTxt[wo] "."
    }
    if (r.note != "")
        out .= "`n" r.note
    out .= "`nLI-RADS Adequacy Score: " adqName[adq] "."
    if (adq = 3)
        out .= " Imaging may need to be repeated; consider a different technique or modality."
    out .= "`nRecommendation: " PE_CEUSMgmt(r.cat)
    if (ShowCitations)
        out .= "`nRef: ACR LI-RADS CEUS v2027 Core."
    return out
}

; ---------------- US LI-RADS Surveillance v2024 ----------------
; cat: 1 US-1, 2 US-2, 3 US-3; vis: 1 A, 2 B, 3 C
PE_USExtract(text) {
    x := {cat: 1, vis: 1, afp: false}
    if RegExMatch(text, "i)\bUS-?\s?([123])\b", m)
        x.cat := m1
    else {
        mm := PE_TIRADSSize(text) * 10
        if (mm >= 10)
            x.cat := 3
        else if (mm > 0)
            x.cat := 2
    }
    if RegExMatch(text, "i)\bVIS-?\s?([ABC])\b", m)
        x.vis := InStr("ABC", m1)
    if RegExMatch(text, "i)thrombus") && !RegExMatch(text, "i)\bno\s+(?:\w+\s+){0,3}thrombus")
        x.cat := 3
    return x
}

PE_USText(cat, vis, afp, risk) {
    catTxt := ["US-1 Negative", "US-2 Subthreshold", "US-3 Positive"]
    visTxt := ["VIS-A (no or minimal limitations)", "VIS-B (moderate limitations)", "VIS-C (severe limitations)"]
    if (cat = 3)
        rec := "Diagnostic multiphase contrast-enhanced CT or MRI, or CEUS."
    else if (afp)
        rec := "AFP positive without a US-3 observation: diagnostic multiphase MRI or CT (CEUS is unlikely to help without a US correlate)."
    else if (vis = 3 && risk)
        rec := "Consider an alternative surveillance modality (e.g., abbreviated MRI or multiphase CT); repeat VIS-C is likely."
    else if (vis = 3)
        rec := "Repeat US within 3 months. If still VIS-C, consider an alternative surveillance strategy (e.g., abbreviated MRI or multiphase CT)."
    else if (cat = 2)
        rec := "Repeat US in 3-6 months, up to two times. If the observation is no longer seen or remains under 10 mm, return to routine 6-month surveillance."
    else
        rec := "Repeat US in 6 months."
    out := "`n`nLI-RADS US Surveillance (v2024): " catTxt[cat] ", " visTxt[vis] "."
    out .= "`nRecommendation: " rec
    if (ShowCitations)
        out .= "`nRef: ACR LI-RADS US Surveillance v2024 Core."
    return out
}

; ---------------- LI-RADS Treatment Response v2024 ----------------
; tx: 1 CT/MRI nonradiation, 2 CT/MRI radiation, 3 CEUS nonradiation
; mass (CT/MRI): 1 cannot assess, 2 none, 3 uncertain [rad: present, stable/decreased], 4 present [rad: new/increased]
; intra/peri (CEUS): 1 absent, 2 uncertain, 3 present
PE_TRACat(tx, mass, af, intra, peri, ne) {
    if (tx = 3) {
        if (ne)
            return "Nonevaluable"
        if (intra = 3 || peri = 3)
            return "Viable"
        if (intra = 2 || peri = 2)
            return "Equivocal"
        return "Nonviable"
    }
    if (mass = 1)
        return "Nonevaluable"
    if (mass = 2)
        return "Nonviable"
    if (mass = 4)
        return "Viable"
    if (af)
        return "Viable"
    return (tx = 2) ? "Nonprogressing" : "Equivocal"
}

PE_TRAText(tx, mass, af, intra, peri, ne, mm) {
    cat := PE_TRACat(tx, mass, af, intra, peri, ne)
    name := ["CT/MRI Nonradiation TRA v2024", "CT/MRI Radiation TRA v2024", "CEUS Nonradiation TRA v2024"]
    if (cat = "Nonevaluable")
        rec := "Repeat imaging in 3 months or less."
    else if (cat = "Nonviable")
        rec := "Continue monitoring in about 3 months."
    else if (cat = "Viable")
        rec := "Multidisciplinary discussion for consensus management, often including retreatment."
    else if (tx = 3)
        rec := "Continue monitoring in about 3 months. Multidisciplinary discussion for consensus management (often CT or MRI) if stable or increasing 6 months or more after treatment, or new in a previously nonviable lesion."
    else
        rec := "Continue monitoring in about 3 months; multidisciplinary discussion in unusual or complex cases."
    out := "`n`nLI-RADS Treatment Response (" name[tx] "): LR-TR " cat "."
    if (mm > 0 && cat != "Nonviable" && cat != "Nonevaluable")
        out .= "`nMasslike enhancement measures " PE_Fmt(mm) " mm."
    if (af && tx != 3 && (mass = 3))
        out .= "`nUpgraded to LR-TR Viable by ancillary features (diffusion restriction or T2 hyperintensity" (tx = 2 ? ", new or increased" : "") ")."
    out .= "`nRecommendation: " rec
    if (ShowCitations)
        out .= "`nRef: ACR LI-RADS " name[tx] " Core."
    return out
}

PE_TRAExtract(text) {
    x := {tx: 1}
    if RegExMatch(text, "i)CEUS|contrast-enhanced\s+(?:ultrasound|US)|microbubble")
        x.tx := 3
    else if RegExMatch(text, "i)\bTARE\b|radioembol|Y-?90|yttrium|SBRT|stereotactic|radiation|proton")
        x.tx := 2
    return x
}

; Which LI-RADS module fits the highlighted text
PE_LIRADSMode(text) {
    if RegExMatch(text, "i)LR-?TR|treated\s+(?:lesion|observation)|post-?(?:treatment|ablation|TACE)|\bTACE\b|\bTARE\b|ablation|radioembol|Y-?90|SBRT|chemoemboli")
        return "tra"
    if RegExMatch(text, "i)\bCEUS\b|contrast-enhanced\s+(?:ultrasound|US)|microbubble|sonazoid|definity|lumason")
        return "ceus"
    if RegExMatch(text, "i)\bUS-?\s?[123]\b|\bVIS-?\s?[ABC]\b|surveillance\s+(?:ultrasound|US)")
        return "us"
    return "ctmr"
}

; ---------------- LI-RADS window (one window, four modules) ----------------
SP_ShowLIRADSGui(prefill := "", mode := "") {
    SP_Init()
    prevGui := A_DefaultGui
    if (mode = "")
        mode := PE_LIRADSMode(prefill)
    SP_LRMode := mode, SP_LRLastTx := 0
    dark := DarkMode
    bg := dark ? "1E1E1E" : "F0F0F0", fg := dark ? "E6E6E6" : "000000"
    titles := {ctmr: "LI-RADS CT/MRI v2018 (diagnostic)", ceus: "CEUS LI-RADS v2027 (diagnostic)", us: "LI-RADS US Surveillance v2024", tra: "LI-RADS Treatment Response v2024"}
    Gui, SPLR:New, +AlwaysOnTop -MinimizeBox +HwndhL +LabelSPLR_, % titles[mode]
    Gui, SPLR:Color, %bg%, % dark ? "2D2D2D" : "FFFFFF"
    Gui, SPLR:Font, s10 c%fg%, Segoe UI
    Gui, SPLR:Add, Text, x10 y12 w90, Module:
    modeMap := {ctmr: 1, ceus: 2, us: 3, tra: 4}
    modeIdx := modeMap[mode]
    Gui, SPLR:Add, DropDownList, x100 y9 w330 vSPL_Mode gSPL_ModeChange AltSubmit Choose%modeIdx%, CT/MRI diagnostic (v2018)|CEUS diagnostic (v2027)|US surveillance (v2024)|Treatment response (v2024)
    SP_LRPrefill := prefill
    if (mode = "ceus")
        SP_LRBuildCEUS(prefill, fg)
    else if (mode = "us")
        SP_LRBuildUS(prefill, fg)
    else if (mode = "tra")
        SP_LRBuildTRA(prefill, fg)
    else
        SP_LRBuildCTMR(prefill, fg)
    Gui, SPLR:Font, s10 c%fg%
    Gui, SPLR:Add, Edit, x10 y+8 w420 r7 ReadOnly vSPL_Preview
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
    SPL_Update()
    Gui, %prevGui%:Default
}

SP_LRNote(fg, txt) {
    Gui, SPLR:Font, s8 c808080
    Gui, SPLR:Add, Text, x10 y+8 w420, %txt%
    Gui, SPLR:Font, s10 c%fg%
}
SP_LRHead(fg, txt) {
    Gui, SPLR:Font, s10 bold c%fg%
    Gui, SPLR:Add, Text, x10 y+10 w420, %txt%
    Gui, SPLR:Font, s10 norm c%fg%
}

SP_LRBuildCTMR(prefill, fg) {
    x := PE_LIRADSExtract(prefill)
    sz := x.mm > 0 ? PE_Fmt(x.mm) : ""
    aphe := x.aphe ? 1 : 0, wo := x.washout ? 1 : 0, cap := x.capsule ? 1 : 0
    tg := x.growth ? 1 : 0, tiv := x.tiv ? 1 : 0, lrm := x.lrm ? 1 : 0
    Gui, SPLR:Add, Text, x10 y+12 w190, Observation size (mm):
    Gui, SPLR:Add, Edit, x205 yp-3 w70 vSPL_Size gSPL_Update, %sz%
    Gui, SPLR:Add, Checkbox, x10 y+10 w420 vSPL_APHE gSPL_Update Checked%aphe%, Nonrim arterial phase hyperenhancement (APHE)
    SP_LRHead(fg, "Additional major features")
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_WO gSPL_Update Checked%wo%, Nonperipheral washout
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_Cap gSPL_Update Checked%cap%, Enhancing capsule
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_TG gSPL_Update Checked%tg%, Threshold growth (size up 50`% or more in 6 months or less)
    Gui, SPLR:Add, Text, x10 y+12 w140, Ancillary features:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPL_Anc gSPL_Update AltSubmit Choose1, None / not applied|Favor malignancy (up 1, max LR-4)|Favor benignity (down 1)
    SP_LRHead(fg, "These take precedence")
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 vSPL_TIV gSPL_Update Checked%tiv%, Tumor in vein (LR-TIV)
    Gui, SPLR:Add, Checkbox, x20 y+4 w410 r2 vSPL_LRM gSPL_Update Checked%lrm%, LR-M features (targetoid, rim APHE, peripheral washout, delayed central enhancement)
    Gui, SPLR:Add, Text, x10 y+12 w140, Category:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPL_Ovr gSPL_Update AltSubmit Choose1, From the features above|LR-1 Definitely benign|LR-2 Probably benign|LR-NC Cannot be categorized
    SP_LRNote(fg, "Untreated observation, high-risk patient (cirrhosis, chronic hepatitis B, current or prior HCC). Pre-filled from the highlighted text: check every box before inserting.")
}

SP_LRBuildCEUS(prefill, fg) {
    x := PE_CEUSExtract(prefill)
    sz := x.mm > 0 ? PE_Fmt(x.mm) : ""
    tiv := x.tiv ? 1 : 0
    SP_LRCeusAgent := x.agent
    Gui, SPLR:Add, Text, x10 y+12 w190, Nodule size (mm, B-mode):
    Gui, SPLR:Add, Edit, x205 yp-3 w70 vSPC_Size gSPL_Update, %sz%
    Gui, SPLR:Add, Text, x10 y+12 w140, Contrast agent:
    Gui, SPLR:Add, DropDownList, % "x150 yp-3 w280 vSPC_Agent gSPL_Update AltSubmit Choose" x.agent, Blood-pool agent (Lumason, Definity)|Kupffer-cell agent (Sonazoid)
    Gui, SPLR:Add, Text, x10 y+12 w140, Arterial phase:
    Gui, SPLR:Add, DropDownList, % "x150 yp-3 w280 vSPC_APHE gSPL_Update AltSubmit Choose" x.aphe, No APHE|Nonrim APHE|Rim APHE, then washout of the rim (LR-M)|Rim APHE, no washout of the rim|Peripheral discontinuous nodular (hemangioma)
    Gui, SPLR:Add, Text, x10 y+12 w140, Washout:
    Gui, SPLR:Add, DropDownList, % "x150 yp-3 w280 vSPC_WO gSPL_Update AltSubmit Choose" x.wo, % SP_LRWashItems(x.agent)
    Gui, SPLR:Add, Text, x10 y+12 w140, Ancillary features:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPC_Anc gSPL_Update AltSubmit Choose1, None / not applied|Favor malignancy (up 1, max LR-4)|Favor benignity (down 1, not from LR-5)
    Gui, SPLR:Add, Checkbox, x10 y+10 w420 vSPC_TIV gSPL_Update Checked%tiv%, Tumor in vein (CEUS LR-TIV)
    Gui, SPLR:Add, Text, x10 y+12 w140, Category:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPC_Ovr gSPL_Update AltSubmit Choose1, From the features above|LR-1 Definitely benign|LR-2 Probably benign|LR-NC Cannot be categorized
    Gui, SPLR:Add, Text, x10 y+12 w140, Adequacy score:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPC_Adq gSPL_Update AltSubmit Choose1, A - No or minimal limitations|B - Moderate limitations|C - Severe limitations
    SP_LRNote(fg, "Untreated nodule visible on B-mode US, high-risk patient. LR-M: rim APHE with rim washout, early (<60 s) washout, or marked washout at <2 min. Unsure about a feature: treat it as absent.")
}

SP_LRWashItems(agent) {
    if (agent = 2)
        return "No hypoenhancement at 1-5 min|Mild hypoenhancement at 1-2 min, or any at 2-5 min|Early washout (under 60 s) (LR-M)|Marked hypoenhancement within 2 min (LR-M)"
    return "No washout|Late (60 s or later) and mild washout|Early washout (under 60 s) (LR-M)|Marked washout within 2 min (LR-M)"
}

SP_LRBuildUS(prefill, fg) {
    x := PE_USExtract(prefill)
    Gui, SPLR:Add, Text, x10 y+12 w140, US category:
    Gui, SPLR:Add, DropDownList, % "x150 yp-3 w280 vSPU_Cat gSPL_Update AltSubmit Choose" x.cat, US-1 Negative (none / definitely benign)|US-2 Subthreshold (under 10 mm)|US-3 Positive (10 mm+, distortion, new vein thrombus)
    Gui, SPLR:Add, Text, x10 y+12 w140, Visualization:
    Gui, SPLR:Add, DropDownList, % "x150 yp-3 w280 vSPU_Vis gSPL_Update AltSubmit Choose" x.vis, VIS-A No or minimal limitations|VIS-B Moderate limitations|VIS-C Severe limitations
    Gui, SPLR:Add, Checkbox, x10 y+10 w420 vSPU_AFP gSPL_Update, AFP positive (per referrer / AASLD definition)
    Gui, SPLR:Add, Checkbox, x10 y+6 w420 r2 vSPU_Risk gSPL_Update, Risk factors for repeat VIS-C (MASH or alcohol cirrhosis, Child-Pugh B/C, BMI 35 or more)
    SP_LRNote(fg, "Surveillance US in a patient at high risk for HCC. US-3 or AFP positive takes priority, then VIS-C, then US-2 / US-1.")
}

SP_LRBuildTRA(prefill, fg) {
    x := PE_TRAExtract(prefill)
    Gui, SPLR:Add, Text, x10 y+12 w140, Treatment / exam:
    Gui, SPLR:Add, DropDownList, % "x150 yp-3 w280 vSPT_Tx gSPL_Update AltSubmit Choose" x.tx, CT/MRI after TACE, TAE, ablation or resection|CT/MRI after TARE (Y-90) or SBRT|CEUS after TACE, TAE, ablation or resection
    SP_LRHead(fg, "CT / MRI")
    Gui, SPLR:Add, Text, x20 y+4 w130, Masslike enhancement:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPT_Mass gSPL_Update AltSubmit Choose2, % SP_LRMassItems(x.tx)
    Gui, SPLR:Add, Checkbox, x20 y+8 w410 r2 vSPT_AF gSPL_Update, % SP_LRAFText(x.tx)
    SP_LRHead(fg, "CEUS")
    Gui, SPLR:Add, Text, x20 y+4 w130, Intralesional:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPT_Intra gSPL_Update AltSubmit Choose1, Absent (no intralesional enhancement)|Uncertain|Present
    Gui, SPLR:Add, Text, x20 y+10 w130, Perilesional:
    Gui, SPLR:Add, DropDownList, x150 yp-3 w280 vSPT_Peri gSPL_Update AltSubmit Choose1, Absent (enhances like liver)|Uncertain|Present (APHE with washout)
    Gui, SPLR:Add, Checkbox, x20 y+8 w410 vSPT_NE gSPL_Update, Not evaluable (LR-TR Nonevaluable)
    Gui, SPLR:Add, Text, x10 y+12 w200, Enhancing tissue size (mm, optional):
    Gui, SPLR:Add, Edit, x215 yp-3 w70 vSPT_Size gSPL_Update
    SP_LRNote(fg, "Per treated lesion. New or untreated observations outside the treatment zone: use the diagnostic module. Unsure between two categories: choose the less certain one.")
}

SP_LRMassItems(tx) {
    if (tx = 2)
        return "Cannot be assessed (degraded / omitted)|None|Present, stable or smaller over time|Present, new or larger over time"
    return "Cannot be assessed (degraded / omitted)|None|Uncertain (presence or shape)|Present (any degree, any phase)"
}
SP_LRAFText(tx) {
    if (tx = 2)
        return "Ancillary: new or increasing diffusion restriction or mild-moderate T2 hyperintensity (Nonprogressing -> Viable)"
    return "Ancillary: diffusion restriction or mild-moderate T2 hyperintensity where enhancement is uncertain (Equivocal -> Viable)"
}

SPL_ModeChange(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Gui, SPLR:Submit, NoHide
    modes := ["ctmr", "ceus", "us", "tra"]
    if (modes[SPL_Mode] = SP_LRMode)
        return
    p := SP_LRPrefill
    SPL_Cancel()
    SP_ShowLIRADSGui(p, modes[SPL_Mode])
}

SPL_Update(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    if (!SP_LRHwnd)
        return
    Gui, SPLR:Submit, NoHide
    if (SP_LRMode = "ceus") {
        if (SPC_Agent != SP_LRCeusAgent) {          ; washout wording depends on the agent
            SP_LRCeusAgent := SPC_Agent
            GuiControl, SPLR:, SPC_WO, % "|" SP_LRWashItems(SPC_Agent)
            GuiControl, SPLR:Choose, SPC_WO, % (SPC_WO >= 1 ? SPC_WO : 1)
            Gui, SPLR:Submit, NoHide
        }
        mm := RegExReplace(SPC_Size, "[^\d.]"), mm := PE_IsNum(mm) ? mm + 0 : 0
        SP_LRText := PE_CEUSText(mm, SPC_Agent, SPC_APHE, SPC_WO, SPC_Anc, SPC_TIV, SPC_Ovr, SPC_Adq)
        hint := "Enter the nodule size (mm)."
    } else if (SP_LRMode = "us") {
        SP_LRText := PE_USText(SPU_Cat, SPU_Vis, SPU_AFP, SPU_Risk)
        hint := ""
    } else if (SP_LRMode = "tra") {
        if (SPT_Tx != SP_LRLastTx) {
            SP_LRLastTx := SPT_Tx
            ct := (SPT_Tx != 3)
            GuiControl, SPLR:, SPT_Mass, % "|" SP_LRMassItems(SPT_Tx)
            GuiControl, SPLR:Choose, SPT_Mass, 2
            GuiControl, SPLR:, SPT_AF, % SP_LRAFText(SPT_Tx)
            for _, c in ["SPT_Mass", "SPT_AF"]
                GuiControl, % "SPLR:" (ct ? "Enable" : "Disable"), %c%
            for _, c in ["SPT_Intra", "SPT_Peri", "SPT_NE"]
                GuiControl, % "SPLR:" (ct ? "Disable" : "Enable"), %c%
            Gui, SPLR:Submit, NoHide
        }
        mm := RegExReplace(SPT_Size, "[^\d.]"), mm := PE_IsNum(mm) ? mm + 0 : 0
        SP_LRText := PE_TRAText(SPT_Tx, SPT_Mass, SPT_AF, SPT_Intra, SPT_Peri, SPT_NE, mm)
        hint := ""
    } else {
        mm := RegExReplace(SPL_Size, "[^\d.]"), mm := PE_IsNum(mm) ? mm + 0 : 0
        SP_LRText := PE_LIRADSText(mm, SPL_APHE, SPL_WO, SPL_Cap, SPL_TG, SPL_Anc, SPL_TIV, SPL_LRM, SPL_Ovr)
        hint := "Enter the observation size (mm)."
    }
    msg := SP_LRText != "" ? Trim(SP_LRText, "`n") : hint
    GuiControl, SPLR:, SPL_Preview, %msg%
}

SPL_Insert(CtrlHwnd := 0, GuiEvent := "", EventInfo := "", ErrLevel := "") {
    Critical
    SPL_Update()
    if (SP_LRText = "") {
        MsgBox, 262192, LI-RADS, Enter the size first.
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
    modes := {"CT/MRI diagnostic (v2018)": "ctmr", "CEUS diagnostic (v2027)": "ceus", "US surveillance (v2024)": "us", "Treatment response (v2024)": "tra"}
    SP_ShowLIRADSGui(g_SelectedText, modes.HasKey(itemName) ? modes[itemName] : "")
}
