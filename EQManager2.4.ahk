; ==============================================================================
; EQManager.ahk — AutoHotkey v2
; Tray-based state manager for Equalizer APO + HeSuVi
; ==============================================================================
;
; COMPILATION COMMAND:
;   .\Ahk2Exe.exe /in "EQManagerx.ahk" /out "EQManagerx.exe" /icon "audiox.ico" /base "AutoHotkey64.exe"
;
; ARCHITECTURE OVERVIEW:
;   1. Parse EQManager.txt into memory:
;        - preset definitions
;        - template blocks
;        - optional startup overrides
;
;   2. Determine active state:
;        - preset > 0  → explicit startup preset
;        - preset = 0  → detect live APO state from config.txt / conv.txt
;
;   3. Build tray menu reflecting the detected active configuration.
;
;   4. On user click:
;        - update active selection
;        - regenerate APO files from templates
;        - rebuild tray menu checkmarks
;
;   5. No polling. No timers. Fully event-driven.
;
; FILE LAYOUT:
;   EQManagerx.exe
;       Compiled tray application.
;
;   audiox.ico
;       Embedded tray icon at compile time.
;
;   %ProgramFiles%\EqualizerAPO\config\EQManager.txt
;       Preset database + template source.
;
; APO FILES MANAGED:
;   %ProgramFiles%\EqualizerAPO\config\config.txt
;       Main Equalizer APO pipeline.
;
;   %ProgramFiles%\EqualizerAPO\config\HeSuVi\conv.txt
;       Active convolution preset.
;
;   %ProgramFiles%\EqualizerAPO\config\HeSuVi\master.txt
;       Virtualization master gain.
;
; DESIGN PRINCIPLES:
;   - Single source of truth = live APO files
;   - EQManager.txt defines available presets, not active state
;   - Full-file regeneration only (never partial edits)
;   - Stateless event-driven runtime
; ==============================================================================


#Requires AutoHotkey v2.0
#SingleInstance Force

; ------------------------------------------------------------------------------
; ADMIN CHECK
; ------------------------------------------------------------------------------

if not A_IsAdmin {
    MsgBox(
        "EQManager must be run as Administrator.`n`n"
        "Right-click EQManager.exe → Run as administrator.",
        "EQManager — Insufficient Privileges",
        "OK Icon!"
    )
    ExitApp
}

; ------------------------------------------------------------------------------
; GLOBAL STATE
; ------------------------------------------------------------------------------

global g_BaseDir := A_ScriptDir
global g_APODir  := EnvGet("ProgramFiles") . "\EqualizerAPO\config"

global g_VP := []
global g_HP := []
global g_IP := []

; 0 means "autodetect from live APO files"
global g_ActiveVP := 0
global g_ActiveHP := 0
global g_ActiveIP := 0

global g_ConfigTemplate := ""
global g_ConvTemplate   := ""
global g_MasterTemplate := ""

global g_TrayMenu := Menu()

; ------------------------------------------------------------------------------
; ENTRY POINT
; ------------------------------------------------------------------------------

ParseConfig()
BuildTrayMenu()

A_TrayMenu.Delete()
OnMessage(0x404, TrayIconHandler)

Persistent

; ==============================================================================
; TRAY ICON HANDLER
; ==============================================================================

TrayIconHandler(wParam, lParam, msg, hwnd) {

    ; WM_RBUTTONUP
    if (lParam = 0x205)
        g_TrayMenu.Show()
}

; ==============================================================================
; PARSE CONFIG
; ==============================================================================

ParseConfig() {

    global g_APODir
    global g_VP, g_HP, g_IP
    global g_ActiveVP, g_ActiveHP, g_ActiveIP
    global g_ConfigTemplate, g_ConvTemplate, g_MasterTemplate

    local filePath := g_APODir . "\EQManager.txt"

    if not FileExist(filePath) {

        MsgBox(
            "Cannot find EQManager.txt:`n`n" . filePath,
            "EQManager — Config Missing",
            "OK Icon!"
        )

        ExitApp
    }

    local lines := []

    loop read, filePath
        lines.Push(A_LoopReadLine)

    local inTemplates := false
    local currentKey  := ""

    local configLines := []
    local convLines   := []
    local masterLines := []

    for _, rawLine in lines {

        local line := Trim(rawLine)

        ; ----------------------------------------------------------------------
        ; PRE-TEMPLATE SECTION
        ; ----------------------------------------------------------------------

        if not inTemplates {

            if (line = "" or SubStr(line, 1, 1) = "#")
                continue
        }

        ; ----------------------------------------------------------------------
        ; TEMPLATE HEADER
        ; ----------------------------------------------------------------------

        if (line = "[Templates]") {

            inTemplates := true
            continue
        }

        ; ----------------------------------------------------------------------
        ; TEMPLATE PARSING
        ; ----------------------------------------------------------------------

        if inTemplates {

            if RegExMatch(line, "^(config_template|conv_template|master_template)=(.*)$", &m) {

                currentKey := m[1]

                local rest := Trim(m[2])

                if (rest != "") {

                    if (currentKey = "config_template")
                        configLines.Push(rest)

                    else if (currentKey = "conv_template")
                        convLines.Push(rest)

                    else if (currentKey = "master_template")
                        masterLines.Push(rest)
                }

                continue
            }

            if (currentKey = "config_template")
                configLines.Push(rawLine)

            else if (currentKey = "conv_template")
                convLines.Push(rawLine)

            else if (currentKey = "master_template")
                masterLines.Push(rawLine)

            continue
        }

        ; ----------------------------------------------------------------------
        ; ACTIVE PRESET INDICES
        ; ----------------------------------------------------------------------

        if RegExMatch(line, "^Virtualization_preset\s*=\s*(\d+)$", &m)
            g_ActiveVP := Integer(m[1])

        else if RegExMatch(line, "^Hardware_preset\s*=\s*(\d+)$", &m)
            g_ActiveHP := Integer(m[1])

        else if RegExMatch(line, "^Intent_preset\s*=\s*(\d+)$", &m)
            g_ActiveIP := Integer(m[1])

        ; ----------------------------------------------------------------------
        ; VP ENTRIES
        ; ----------------------------------------------------------------------

        else if RegExMatch(
            line,
            '^VP\d+\s*=\s*"([^"]+)"\s*;\s*"([^"]+)"\s*;\s*([0-9.]+)',
            &m
        ) {

            local entry := Map()

            entry["Label"] := m[1]
            entry["File"]  := m[2]
            entry["Vol"]   := m[3]

            g_VP.Push(entry)
        }

        ; ----------------------------------------------------------------------
        ; HP ENTRIES
        ; ----------------------------------------------------------------------

        else if RegExMatch(
            line,
            '^HP\d+\s*=\s*"([^"]+)"\s*;\s*"([^"]+)"',
            &m
        ) {

            local entry := Map()

            entry["Label"] := m[1]
            entry["File"]  := m[2]

            g_HP.Push(entry)
        }

        ; ----------------------------------------------------------------------
        ; IP ENTRIES
        ; ----------------------------------------------------------------------

        else if RegExMatch(
            line,
            '^IP\d+\s*=\s*"([^"]+)"\s*;\s*"([^"]+)"',
            &m
        ) {

            local entry := Map()

            entry["Label"] := m[1]
            entry["File"]  := m[2]

            g_IP.Push(entry)
        }
    }

    ; --------------------------------------------------------------------------
    ; BUILD TEMPLATE STRINGS
    ; --------------------------------------------------------------------------

    g_ConfigTemplate := TrimTemplateLines(configLines)
    g_ConvTemplate   := TrimTemplateLines(convLines)
    g_MasterTemplate := TrimTemplateLines(masterLines)

    ; --------------------------------------------------------------------------
    ; SANITY CHECKS
    ; --------------------------------------------------------------------------

    if (g_VP.Length = 0 or g_HP.Length = 0 or g_IP.Length = 0) {

        MsgBox(
            "EQManager.txt is missing VP/HP/IP entries.",
            "EQManager — Parse Error",
            "OK Icon!"
        )

        ExitApp
    }

    if (
        g_ConfigTemplate = ""
     or g_ConvTemplate = ""
     or g_MasterTemplate = ""
    ) {

        MsgBox(
            "EQManager.txt is missing template blocks.",
            "EQManager — Template Error",
            "OK Icon!"
        )

        ExitApp
    }

    ; --------------------------------------------------------------------------
    ; STARTUP LOGIC
    ; --------------------------------------------------------------------------

    ; VP
    if (g_ActiveVP = 0)
        DetectCurrentVP()
    else
        g_ActiveVP := Max(1, Min(g_ActiveVP, g_VP.Length))

    ; HP
    if (g_ActiveHP = 0)
        DetectCurrentHP()
    else
        g_ActiveHP := Max(1, Min(g_ActiveHP, g_HP.Length))

    ; IP
    if (g_ActiveIP = 0)
        DetectCurrentIP()
    else
        g_ActiveIP := Max(1, Min(g_ActiveIP, g_IP.Length))
}

; ==============================================================================
; TRIM TEMPLATE LINES
; ==============================================================================

TrimTemplateLines(lines) {

    local start := 1

    while (start <= lines.Length and Trim(lines[start]) = "")
        start++

    local end := lines.Length

    while (end >= 1 and Trim(lines[end]) = "")
        end--

    if (start > end)
        return ""

    local result := ""

    loop (end - start + 1) {

        local idx := start + A_Index - 1
        result .= lines[idx] . "`n"
    }

    return RTrim(result, "`n")
}

; ==============================================================================
; DETECT CURRENT HP
; ==============================================================================

DetectCurrentHP() {

    global g_APODir
    global g_HP
    global g_ActiveHP

    local configText := ""

    try
        configText := FileRead(g_APODir . "\config.txt", "UTF-8")

    catch
        return

    g_ActiveHP := 1

    for idx, preset in g_HP {

        local escaped := RegexEscape(preset["File"])

        if RegExMatch(
            configText,
            "im)^\s*Include:\s*" . escaped . "\s*$"
        ) {
            g_ActiveHP := idx
            break
        }
    }
}

; ==============================================================================
; DETECT CURRENT IP
; ==============================================================================

DetectCurrentIP() {

    global g_APODir
    global g_IP
    global g_ActiveIP

    local configText := ""

    try
        configText := FileRead(g_APODir . "\config.txt", "UTF-8")

    catch
        return

    g_ActiveIP := 1

    for idx, preset in g_IP {

        local escaped := RegexEscape(preset["File"])

        if RegExMatch(
            configText,
            "im)^\s*Include:\s*" . escaped . "\s*$"
        ) {
            g_ActiveIP := idx
            break
        }
    }
}

; ==============================================================================
; DETECT CURRENT VP
; ==============================================================================

DetectCurrentVP() {

    global g_APODir
    global g_VP
    global g_ActiveVP

    local convText := ""

    try
        convText := FileRead(g_APODir . "\HeSuVi\conv.txt", "UTF-8")

    catch
        return

    g_ActiveVP := 1

    for idx, preset in g_VP {

        local escaped := RegexEscape(preset["File"])

        if RegExMatch(convText, "i)hrir\\" . escaped) {
            g_ActiveVP := idx
            break
        }
    }
}

; ==============================================================================
; REGEX ESCAPE
; ==============================================================================

RegexEscape(str) {

    static chars := "\.^$|()[]{}*+?"

    for _, ch in StrSplit(chars)
        str := StrReplace(str, ch, "\" . ch)

    return str
}

; ==============================================================================
; BUILD TRAY MENU
; ==============================================================================

BuildTrayMenu() {

    global g_TrayMenu
    global g_VP, g_HP, g_IP
    global g_ActiveVP, g_ActiveHP, g_ActiveIP

    try g_TrayMenu.Delete()

    g_TrayMenu := Menu()

    ; --------------------------------------------------------------------------
    ; VIRTUALIZATION
    ; --------------------------------------------------------------------------

    for idx, preset in g_VP {

        local label := "Virtualization: " . preset["Label"]
        local capturedIdx := idx

        g_TrayMenu.Add(label, MakeVPHandler(capturedIdx))

        if (idx = g_ActiveVP)
            g_TrayMenu.Check(label)
    }

    g_TrayMenu.Add()

    ; --------------------------------------------------------------------------
    ; HARDWARE
    ; --------------------------------------------------------------------------

    for idx, preset in g_HP {

        local label := "Hardware: " . preset["Label"]
        local capturedIdx := idx

        g_TrayMenu.Add(label, MakeHPHandler(capturedIdx))

        if (idx = g_ActiveHP)
            g_TrayMenu.Check(label)
    }

    g_TrayMenu.Add()

    ; --------------------------------------------------------------------------
    ; INTENT
    ; --------------------------------------------------------------------------

    for idx, preset in g_IP {

        local label := "Intent: " . preset["Label"]
        local capturedIdx := idx

        g_TrayMenu.Add(label, MakeIPHandler(capturedIdx))

        if (idx = g_ActiveIP)
            g_TrayMenu.Check(label)
    }

    g_TrayMenu.Add()

    g_TrayMenu.Add("Exit EQManager", (*) => ExitApp())
}

; ==============================================================================
; HANDLER FACTORIES
; ==============================================================================

MakeVPHandler(idx) {
    return (*) => OnVPClick(idx)
}

MakeHPHandler(idx) {
    return (*) => OnHPClick(idx)
}

MakeIPHandler(idx) {
    return (*) => OnIPClick(idx)
}

; ==============================================================================
; CLICK HANDLERS
; ==============================================================================

OnVPClick(idx) {

    global g_ActiveVP

    g_ActiveVP := idx

    GlobalWrite()
    BuildTrayMenu()
}

OnHPClick(idx) {

    global g_ActiveHP

    g_ActiveHP := idx

    GlobalWrite()
    BuildTrayMenu()
}

OnIPClick(idx) {

    global g_ActiveIP

    g_ActiveIP := idx

    GlobalWrite()
    BuildTrayMenu()
}

; ==============================================================================
; GLOBAL WRITE
; ==============================================================================

GlobalWrite() {

    global g_APODir
    global g_VP, g_HP, g_IP
    global g_ActiveVP, g_ActiveHP, g_ActiveIP
    global g_ConfigTemplate, g_ConvTemplate, g_MasterTemplate

    local vp := g_VP[g_ActiveVP]
    local hp := g_HP[g_ActiveHP]
    local ip := g_IP[g_ActiveIP]

    ; config.txt

    local configContent := g_ConfigTemplate

    configContent := StrReplace(configContent, "{HP}", hp["File"])
    configContent := StrReplace(configContent, "{IP}", ip["File"])

    ; conv.txt

    local convContent := g_ConvTemplate

    convContent := StrReplace(convContent, "{WAV}", vp["File"])

    ; master.txt

    local masterContent := g_MasterTemplate

    masterContent := StrReplace(masterContent, "{VOL}", vp["Vol"])

    ; write files

    WriteFile(g_APODir . "\config.txt",        configContent)
    WriteFile(g_APODir . "\HeSuVi\conv.txt",   convContent)
    WriteFile(g_APODir . "\HeSuVi\master.txt", masterContent)
}

; ==============================================================================
; WRITE FILE
; ==============================================================================

WriteFile(path, content) {

    try {

        local f := FileOpen(path, "w", "UTF-8-RAW")

        if not IsObject(f)
            throw Error("Could not open file for writing.")

        f.Write(content)
        f.Close()
    }

    catch as e {

        MsgBox(
            "Fatal write error:`n`n"
            . path
            . "`n`n"
            . e.Message,
            "EQManager — Write Failed",
            "OK Icon!"
        )

        ExitApp
    }
}