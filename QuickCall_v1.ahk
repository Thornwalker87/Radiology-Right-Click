; ============================================================
; QuickCall v1  (AutoHotkey v1.1 module for Radiology Right Click v1.22)
; Persistent always-on-top call panel using Google Voice
;
; Used by "Radiology Right Click v1.22.ahk" / "-local.ahk":
;     #Include %A_ScriptDir%\QuickCall_v1.ahk   (at the very end of the file)
;     QC_Enable() / QC_Disable()                 (Preferences > Quick Call panel)
; Or double-click this file to run it on its own.
;
; The panel is a floating tool window (no taskbar button) that is kept above
; Sectra / PowerScribe: if another app's window covers it, it is pushed back to
; the top of the always-on-top band without taking focus.
;
; Requires AutoHotkey v1.1.27 or newer (portable AutoHotkey.exe on OneDrive is fine).
; This file is plain ASCII on purpose so AHK v1 reads it correctly with no BOM.
;
; NOTE: This file has no auto-execute code when #Included (it sits after the
; host script's ExitApp). All setup happens in QC_Init(), called by QC_Enable().
; ============================================================

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
    QC_DialMode        := "url"     ; "url" = Google Voice | "teams" = Microsoft Teams | "tel" = tel: link
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
    if RegExMatch(dm, "^(url|teams|tel)$")
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
    Menu, QCCtx, Add, Call with Google Voice, QC_CtxModeGV
    Menu, QCCtx, Add, Call with Microsoft Teams, QC_CtxModeTeams
    Menu, QCCtx, % (QC_DialMode = "url" ? "Check" : "Uncheck"), Call with Google Voice
    Menu, QCCtx, % (QC_DialMode = "teams" ? "Check" : "Uncheck"), Call with Microsoft Teams
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
    if (QC_AutoConfirm && QC_DialMode = "url")
        SetTimer, QC_ConfirmCall, -250
    QC_LastCall := {label: (label != "" ? label : QC_FormatPhone(d)), time: A_Now}
    QC_Tip("Calling " QC_LastCall.label "  " QC_FormatPhone(d) (QC_DialMode = "teams" ? "  (Teams)" : ""), 3000)
}

QC_SetDialMode(mode) {
    QC_DialMode := mode
    IniWrite, %mode%, %QC_IniFile%, Settings, DialMode
    QC_Tip("Quick Call now dials with " (mode = "teams" ? "Microsoft Teams" : mode = "tel" ? "the phone app (tel:)" : "Google Voice"), 2000)
}
QC_CtxModeGV(p1 := "", p2 := "", p3 := "") {
    QC_SetDialMode("url")
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
