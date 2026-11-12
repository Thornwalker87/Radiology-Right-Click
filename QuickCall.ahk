; ============================================================
; QuickCall v2  (module for Radiology Right Click)
; Persistent always-on-top call panel using Google Voice
;
; Used by RadAssist.ahk:  #Include QuickCall.ahk, then QC_Enable() / QC_Disable()
;                          (toggled by Settings > "Enable Quick Call panel")
; Or double-click this file to run it on its own.
;
; The panel is a floating tool window (no taskbar button) that is kept
; above Sectra / PowerScribe: if another app's window covers it, it is
; pushed back to the top of the always-on-top band without taking focus.
; ============================================================
#Requires AutoHotkey v2.0

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

; Standalone: double-clicking QuickCall.ahk runs it on its own
if (A_LineFile = A_ScriptFullPath) {
    Persistent()
    QC_Enable()
}

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
