// schoolErect.hx — Stage script portado de V-Slice a Cool Engine
//
// BUG FIX: el crash "Null Object Reference" en onUpdate ocurría porque:
//   1. Los personajes aún no están completamente inicializados en el primer frame.
//   2. uFrameBounds / angOffset de DropShadowShader no existen hasta que el
//      shader haya compilado y el sprite haya renderizado su primer frame.
//
// Solución:
//   - Inicializar en onStageCreate() (personajes ya existen) en vez de onUpdate().
//   - Actualizar uFrameBounds cada frame SÓLO si el sprite tiene un frame activo.
//   - Envolver todo en try/catch para que un fallo no rompa el stage.

var _shBF   = null;
var _shGF   = null;
var _shDad  = null;

// ─── Setup: se llama una vez cuando el stage ya tiene todos los personajes ────

function onStageCreate()
{
    try { _setupBF();  } catch (e:Dynamic) { trace("[schoolErect] BF setup error: " + e); }
    try { _setupGF();  } catch (e:Dynamic) { trace("[schoolErect] GF setup error: " + e); }
    try { _setupDad(); } catch (e:Dynamic) { trace("[schoolErect] Dad setup error: " + e); }
}

// ─── Update: mantiene uFrameBounds sincronizado con el frame actual ────────────
// El DropShadowShader necesita saber las coordenadas UV del frame en el atlas.
// Sin esto el rim light se "rompe" al cambiar de animación.

function onUpdate(elapsed)
{
    _updateShader(chars.bf(),  _shBF);
    _updateShader(chars.gf(),  _shGF);
    _updateShader(chars.dad(), _shDad);
}

function _updateShader(sprite, shader)
{
    if (sprite == null || shader == null) return;
    try
    {
        var frame = sprite.frame;
        if (frame == null) return;
        // updateFrameInfo actualiza uFrameBounds y angOffset con los UVs reales del frame
        shader.updateFrameInfo(frame);
    }
    catch (e:Dynamic) {}
}

// ─── Limpieza ─────────────────────────────────────────────────────────────────

function onDestroy()
{
    try { clearFilters(chars.bf());  } catch (_:Dynamic) {}
    try { clearFilters(chars.gf());  } catch (_:Dynamic) {}
    try { clearFilters(chars.dad()); } catch (_:Dynamic) {}
    _shBF  = null;
    _shGF  = null;
    _shDad = null;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function _applyFilter(sprite, shader)
{
    if (sprite == null || shader == null) return false;
    // NO setar uFrameBounds manualmente aquí — dejar que onUpdate lo haga
    // con el frame real. Setearlo a [0,0,1,1] causaba que el shader leyera
    // fuera de los UVs correctos en atlases con múltiples frames.
    var filter = makeShaderFilter(shader);
    if (filter == null) return false;
    setFilters(sprite, [filter]);
    return true;
}

function _setupBF()
{
    var bf = chars.bf();
    if (bf == null) { trace("[schoolErect] BF null — skip"); return; }

    var rim = new DropShadowShader();
    rim.setAdjustColor(-66, -10, 24, -23);
    rim.color        = 0xFF52351D;
    rim.antialiasAmt = 0;
    rim.distance     = 5;
    rim.angle        = 90;
    rim.strength     = 1;
    rim.threshold    = 0.1;
    rim.useAltMask   = false;

    if (_applyFilter(bf, rim))
    {
        _shBF = rim;
        trace("[schoolErect] BF OK");
    }
    else trace("[schoolErect] BF FAIL — makeShaderFilter returned null");
}

function _setupGF()
{
    var gf = chars.gf();
    if (gf == null) { trace("[schoolErect] GF null — skip"); return; }

    var rim = new DropShadowShader();
    rim.setAdjustColor(-42, -10, 5, -25);
    rim.color        = 0xFF52351D;
    rim.antialiasAmt = 0;
    rim.distance     = 3;
    rim.angle        = 90;
    rim.threshold    = 0.3;
    rim.strength     = 1;
    rim.useAltMask   = false;

    if (_applyFilter(gf, rim))
    {
        _shGF = rim;
        trace("[schoolErect] GF OK");
    }
    else trace("[schoolErect] GF FAIL — makeShaderFilter returned null");
}

function _setupDad()
{
    var dad = chars.dad();
    if (dad == null) { trace("[schoolErect] Dad null — skip"); return; }

    var rim = new DropShadowShader();
    rim.setAdjustColor(-66, -10, 24, -23);
    rim.color        = 0xFF52351D;
    rim.antialiasAmt = 0;
    rim.distance     = 5;
    rim.angle        = 90;
    rim.strength     = 1;
    rim.threshold    = 0.1;
    rim.useAltMask   = false;

    if (_applyFilter(dad, rim))
    {
        _shDad = rim;
        trace("[schoolErect] Dad OK");
    }
    else trace("[schoolErect] Dad FAIL — makeShaderFilter returned null");
}
