package extensions;

// ─────────────────────────────────────────────────────────────────────────────
// FrameLimiterAPI — Mejora la precisión del timer del OS para FPS altos.
//
// El problema con FPS altos en Windows:
//   • El timer multimedia de Windows tiene resolución ~15.6ms por defecto.
//   • Lime/OpenFL usa Sleep() internamente para limitar el framerate.
//   • Con 15.6ms de resolución, Sleep(1) puede dormir hasta 15ms reales
//     → el engine nunca supera ~64fps aunque stage.frameRate sea 240+.
//
// Solución: llamar timeBeginPeriod(1) una sola vez al arrancar.
//   • Sube la resolución del timer a 1ms en todo el proceso.
//   • Con 1ms, stage.frameRate funciona correctamente hasta ~1000fps.
//   • No requiere cambiar nada más en el loop de Lime/OpenFL.
//
// Uso:
//   FrameLimiterAPI.init();                  // UNA vez al arrancar (en Main)
//   var hz = FrameLimiterAPI.getMonitorHz(); // Hz del monitor para UI
//
// ─────────────────────────────────────────────────────────────────────────────

#if (cpp && windows)

@:buildXml('
<target id="haxe">
    <lib name="winmm.lib"  if="windows" />
    <lib name="user32.lib" if="windows" />
    <lib name="gdi32.lib"  if="windows" />
</target>
')
@:headerCode('
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <mmsystem.h>

static bool _fl_timer_inited = false;
static UINT _fl_timer_res    = 1;

static int _fl_getMonitorHz() {
    DEVMODEW dm = {};
    dm.dmSize = sizeof(dm);
    if (EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &dm))
        return (int)dm.dmDisplayFrequency;
    HDC hdc = GetDC(nullptr);
    int hz = GetDeviceCaps(hdc, VREFRESH);
    ReleaseDC(nullptr, hdc);
    return (hz > 0) ? hz : 60;
}
#undef TRUE
#undef FALSE
#undef NO_ERROR
')
class FrameLimiterAPI
{
    /**
     * Sube la resolucion del timer multimedia de Windows a 1ms.
     * Llamar UNA vez al arrancar, antes de createGame().
     * Efecto: stage.frameRate funciona con precision real hasta ~1000fps.
     */
    @:functionCode('
        if (_fl_timer_inited) return;
        _fl_timer_inited = true;
        TIMECAPS tc;
        if (timeGetDevCaps(&tc, sizeof(tc)) == MMSYSERR_NOERROR)
            _fl_timer_res = tc.wPeriodMin;
        timeBeginPeriod(_fl_timer_res);
    ')
    public static function init():Void {}

    /** Devuelve la frecuencia de refresco del monitor principal en Hz. */
    @:functionCode('
        return _fl_getMonitorHz();
    ')
    public static function getMonitorHz():Int { return 60; }

    /** Libera el timer al cerrar la app. */
    @:functionCode('
        if (_fl_timer_inited) {
            timeEndPeriod(_fl_timer_res);
            _fl_timer_inited = false;
        }
    ')
    public static function destroy():Void {}
}

#elseif (cpp && linux)

@:headerCode('
#include <stdio.h>
#include <stdlib.h>

static int _fl_linux_getMonitorHz() {
    FILE* f = fopen("/sys/class/drm/card0-HDMI-A-1/modes", "r");
    if (!f) f = fopen("/sys/class/drm/card0-DP-1/modes", "r");
    if (f) {
        char buf[64];
        if (fgets(buf, sizeof(buf), f)) {
            fclose(f);
            char* p = buf;
            while (*p && *p != (char)112 && *p != (char)105) p++;
            if (*p) return atoi(p + 1);
        } else fclose(f);
    }
    return 60;
}
')
class FrameLimiterAPI
{
    public static inline function init():Void {}

    @:functionCode('return _fl_linux_getMonitorHz();')
    public static function getMonitorHz():Int { return 60; }

    public static inline function destroy():Void {}
}

#elseif (cpp && mac)

@:headerCode('
#include <CoreVideo/CVDisplayLink.h>

static int _fl_mac_getMonitorHz() {
    CVDisplayLinkRef link;
    if (CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess) {
        CVTime t = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link);
        CVDisplayLinkRelease(link);
        if (!(t.flags & kCVTimeIsIndefinite) && t.timeValue > 0)
            return (int)(t.timeScale / t.timeValue);
    }
    return 60;
}
')
@:buildXml('
<target id="haxe">
    <lib name="-framework"  if="mac" />
    <lib name="CoreVideo"   if="mac" />
</target>
')
class FrameLimiterAPI
{
    public static inline function init():Void {}

    @:functionCode('return _fl_mac_getMonitorHz();')
    public static function getMonitorHz():Int { return 60; }

    public static inline function destroy():Void {}
}

#else

// Stubs HTML5 / mobile
class FrameLimiterAPI
{
    public static inline function init():Void {}
    public static inline function getMonitorHz():Int return 60;
    public static inline function destroy():Void {}
}

#end
