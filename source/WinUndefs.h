// WinUndefs.h
// Undefs Windows SDK macros that conflict with HaxeFlixel constants.
// This file is force-included at the start of every translation unit via MSVC's /FI
// flag, which WinMacroFix.hx injects into the generated Build.xml.
//
// The #ifdef guard before each #undef makes this safe to include even when
// the macro is not defined — it becomes a no-op in that case.
//
// DO NOT remove or rename this file. It is referenced by WinMacroFix.hx.
#pragma once

// ── FlxKey conflicts (Windows SDK defines these as numeric macros) ─────────────
#ifdef NONE
#undef NONE
#endif
#ifdef ANY
#undef ANY
#endif
#ifdef A
#undef A
#endif
#ifdef B
#undef B
#endif
#ifdef C
#undef C
#endif
#ifdef D
#undef D
#endif
#ifdef E
#undef E
#endif
#ifdef F
#undef F
#endif
#ifdef G
#undef G
#endif
#ifdef H
#undef H
#endif
#ifdef I
#undef I
#endif
#ifdef J
#undef J
#endif
#ifdef K
#undef K
#endif
#ifdef L
#undef L
#endif
#ifdef M
#undef M
#endif
#ifdef N
#undef N
#endif
#ifdef O
#undef O
#endif
#ifdef P
#undef P
#endif
#ifdef Q
#undef Q
#endif
#ifdef R
#undef R
#endif
#ifdef S
#undef S
#endif
#ifdef T
#undef T
#endif
#ifdef U
#undef U
#endif
#ifdef V
#undef V
#endif
#ifdef W
#undef W
#endif
#ifdef X
#undef X
#endif
#ifdef Y
#undef Y
#endif
#ifdef Z
#undef Z
#endif
#ifdef ZERO
#undef ZERO
#endif
#ifdef ONE
#undef ONE
#endif
#ifdef TWO
#undef TWO
#endif
#ifdef THREE
#undef THREE
#endif
#ifdef FOUR
#undef FOUR
#endif
#ifdef FIVE
#undef FIVE
#endif
#ifdef SIX
#undef SIX
#endif
#ifdef SEVEN
#undef SEVEN
#endif
#ifdef EIGHT
#undef EIGHT
#endif
#ifdef NINE
#undef NINE
#endif
#ifdef NUMPAD_0
#undef NUMPAD_0
#endif
#ifdef NUMPAD_1
#undef NUMPAD_1
#endif
#ifdef NUMPAD_2
#undef NUMPAD_2
#endif
#ifdef NUMPAD_3
#undef NUMPAD_3
#endif
#ifdef NUMPAD_4
#undef NUMPAD_4
#endif
#ifdef NUMPAD_5
#undef NUMPAD_5
#endif
#ifdef NUMPAD_6
#undef NUMPAD_6
#endif
#ifdef NUMPAD_7
#undef NUMPAD_7
#endif
#ifdef NUMPAD_8
#undef NUMPAD_8
#endif
#ifdef NUMPAD_9
#undef NUMPAD_9
#endif
#ifdef NUMPAD_DECIMAL
#undef NUMPAD_DECIMAL
#endif
#ifdef NUMPAD_ADD
#undef NUMPAD_ADD
#endif
#ifdef NUMPAD_SUBTRACT
#undef NUMPAD_SUBTRACT
#endif
#ifdef NUMPAD_MULTIPLY
#undef NUMPAD_MULTIPLY
#endif
#ifdef NUMPAD_DIVIDE
#undef NUMPAD_DIVIDE
#endif
#ifdef F1
#undef F1
#endif
#ifdef F2
#undef F2
#endif
#ifdef F3
#undef F3
#endif
#ifdef F4
#undef F4
#endif
#ifdef F5
#undef F5
#endif
#ifdef F6
#undef F6
#endif
#ifdef F7
#undef F7
#endif
#ifdef F8
#undef F8
#endif
#ifdef F9
#undef F9
#endif
#ifdef F10
#undef F10
#endif
#ifdef F11
#undef F11
#endif
#ifdef F12
#undef F12
#endif
#ifdef HOME
#undef HOME
#endif
#ifdef END
#undef END
#endif
#ifdef PAGE_UP
#undef PAGE_UP
#endif
#ifdef PAGE_DOWN
#undef PAGE_DOWN
#endif
#ifdef UP
#undef UP
#endif
#ifdef DOWN
#undef DOWN
#endif
#ifdef LEFT
#undef LEFT
#endif
#ifdef RIGHT
#undef RIGHT
#endif
#ifdef ESCAPE
#undef ESCAPE
#endif
#ifdef BACKSPACE
#undef BACKSPACE
#endif
#ifdef TAB
#undef TAB
#endif
#ifdef ENTER
#undef ENTER
#endif
#ifdef SHIFT
#undef SHIFT
#endif
#ifdef CONTROL
#undef CONTROL
#endif
#ifdef ALT
#undef ALT
#endif
#ifdef CAPS_LOCK
#undef CAPS_LOCK
#endif
#ifdef NUM_LOCK
#undef NUM_LOCK
#endif
#ifdef SCROLL_LOCK
#undef SCROLL_LOCK
#endif
#ifdef INSERT
#undef INSERT
#endif
#ifdef DELETE
#undef DELETE
#endif
#ifdef SPACE
#undef SPACE
#endif
#ifdef MINUS
#undef MINUS
#endif
#ifdef PLUS
#undef PLUS
#endif
#ifdef PERIOD
#undef PERIOD
#endif
#ifdef COMMA
#undef COMMA
#endif
#ifdef SLASH
#undef SLASH
#endif
#ifdef BACK_SLASH
#undef BACK_SLASH
#endif
#ifdef GRAVEACCENT
#undef GRAVEACCENT
#endif
#ifdef QUOTE
#undef QUOTE
#endif
#ifdef SEMICOLON
#undef SEMICOLON
#endif
#ifdef LBRACKET
#undef LBRACKET
#endif
#ifdef RBRACKET
#undef RBRACKET
#endif
#ifdef WINDOWS
#undef WINDOWS
#endif
#ifdef COMMAND
#undef COMMAND
#endif
#ifdef BREAK
#undef BREAK
#endif
#ifdef PRINTSCREEN
#undef PRINTSCREEN
#endif
#ifdef PAUSE
#undef PAUSE
#endif
#ifdef PRINT
#undef PRINT
#endif
#ifdef ERROR
#undef ERROR
#endif
#ifdef BOOL
#undef BOOL
#endif
#ifdef VOID
#undef VOID
#endif
#ifdef TRUE
#undef TRUE
#endif
#ifdef FALSE
#undef FALSE
#endif
#ifdef IGNORE
#undef IGNORE
#endif
#ifdef INFINITE
#undef INFINITE
#endif
#ifdef DOMAIN
#undef DOMAIN
#endif
#ifdef OVERFLOW
#undef OVERFLOW
#endif
#ifdef UNDERFLOW
#undef UNDERFLOW
#endif
#ifdef PASCAL
#undef PASCAL
#endif
#ifdef CALLBACK
#undef CALLBACK
#endif
#ifdef FAR
#undef FAR
#endif
#ifdef NEAR
#undef NEAR
#endif

// ── FlxColor conflicts (wingdi.h / winbase.h) ──────────────────────────────────
#ifdef TRANSPARENT
#undef TRANSPARENT
#endif
#ifdef OPAQUE
#undef OPAQUE
#endif
#ifdef BLACK
#undef BLACK
#endif
#ifdef WHITE
#undef WHITE
#endif
#ifdef RED
#undef RED
#endif
#ifdef GREEN
#undef GREEN
#endif
#ifdef BLUE
#undef BLUE
#endif
#ifdef GRAY
#undef GRAY
#endif
#ifdef LIGHT_GRAY
#undef LIGHT_GRAY
#endif
#ifdef DARK_GRAY
#undef DARK_GRAY
#endif
#ifdef LIME
#undef LIME
#endif
#ifdef MAGENTA
#undef MAGENTA
#endif
#ifdef CYAN
#undef CYAN
#endif
#ifdef YELLOW
#undef YELLOW
#endif
#ifdef ORANGE
#undef ORANGE
#endif
#ifdef PURPLE
#undef PURPLE
#endif
#ifdef PINK
#undef PINK
#endif
#ifdef BROWN
#undef BROWN
#endif
