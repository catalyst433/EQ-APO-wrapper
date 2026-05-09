==============================================================================

EQManager.ahk — AutoHotkey v2
Tray-based state manager for Equalizer APO + HeSuVi

==============================================================================

COMPILATION COMMAND:
   .\Ahk2Exe.exe /in "EQManagerx.ahk" /out "EQManagerx.exe" /icon "audiox.ico" /base "AutoHotkey64.exe"

ARCHITECTURE OVERVIEW:
   1. Parse EQManager.txt into memory:
        - preset definitions
        - template blocks
        - optional startup overrides

   2. Determine active state:
        - preset > 0  → explicit startup preset
        - preset = 0  → detect live APO state from config.txt / conv.txt

   3. Build tray menu reflecting the detected active configuration.

   4. On user click:
        - update active selection
        - regenerate APO files from templates
        - rebuild tray menu checkmarks

   5. No polling. No timers. Fully event-driven.

FILE LAYOUT:
   EQManagerx.exe
       Compiled tray application.

   audiox.ico
       Embedded tray icon at compile time.

   %ProgramFiles%\EqualizerAPO\config\EQManager.txt
       Preset database + template source.

APO FILES MANAGED:
   %ProgramFiles%\EqualizerAPO\config\config.txt
       Main Equalizer APO pipeline.

   %ProgramFiles%\EqualizerAPO\config\HeSuVi\conv.txt
       Active convolution preset.

   %ProgramFiles%\EqualizerAPO\config\HeSuVi\master.txt
       Virtualization master gain.

DESIGN PRINCIPLES:
   - Single source of truth = live APO files
   - EQManager.txt defines available presets, not active state
   - Full-file regeneration only (never partial edits)
   - Stateless event-driven runtime
==============================================================================
