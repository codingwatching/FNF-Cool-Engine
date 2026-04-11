// LinuxUndefs.h
// Undefs X11/Xlib macros that conflict with HaxeFlixel on Linux and macOS.
// This file is force-included at the start of every translation unit via
// GCC/Clang's -include flag, which WinMacroFix.hx injects into Build.xml.
// That is the Linux/macOS equivalent of MSVC's /FI flag used by WinUndefs.h.
//
// The #ifdef guard before each #undef is safe to include even when the macro
// is not defined — it becomes a no-op in that case.
//
// DO NOT remove or rename this file. It is referenced by WinMacroFix.hx.
#pragma once

// ── X11 / Xlib.h conflicts ────────────────────────────────────────────────────
// X11 defines these as macros (mostly #define Status int, #define Bool int, etc.)
// They clash with Haxe/HXCPP-generated parameter names in flixel headers,
// most notably: bool checkStatus(::Dynamic KeyCode, int Status) in FlxKeyManager.h

#ifdef Status
#undef Status
#endif

#ifdef Bool
#undef Bool
#endif

#ifdef True
#undef True
#endif

#ifdef False
#undef False
#endif

// X11 event/return-code macros that shadow common identifiers
#ifdef None
#undef None
#endif

#ifdef Success
#undef Success
#endif

#ifdef Always
#undef Always
#endif

#ifdef Expose
#undef Expose
#endif

// ── Additional X11 / POSIX / glibc conflicts ──────────────────────────────────
#ifdef ERROR
#undef ERROR
#endif

#ifdef OVERFLOW
#undef OVERFLOW
#endif

#ifdef UNDERFLOW
#undef UNDERFLOW
#endif

#ifdef DOMAIN
#undef DOMAIN
#endif
