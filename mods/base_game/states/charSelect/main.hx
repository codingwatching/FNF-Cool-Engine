/**
 * ═══════════════════════════════════════════════════════════════════════════════
 *  CHARACTER SELECT  —  fiel a V-Slice
 * ═══════════════════════════════════════════════════════════════════════════════
 ─── PARÁMETROS DEL GRID (idénticos a V-Slice) ────────────────────────────────*/
var GRID_BASE_X   = 482;
var GRID_BASE_Y   = 155;
var GRID_X_SPREAD = 107;
var GRID_Y_SPREAD = 127;
var ICON_SIZE     = 70;

// ─── PARÁMETROS DEL CURSOR (idénticos a V-Slice) ──────────────────────────────
var CURSOR_FACTOR   = 110.0;
var CURSOR_OFFSET_X = -16.0;
var CURSOR_OFFSET_Y = -48.0;

// ─── ESTADO ───────────────────────────────────────────────────────────────────
var availableChars = [];   // Array<String|null>  — 9 slots, null = bloqueado
var cursorX  = 0;          // −1, 0, 1
var cursorY  = 0;          // −1, 0, 1
var curChar        = 'bf';
var rememberedChar = '';
var lastValidChar  = '';
var availableGfIds = [];

var allowInput    = false;
var pressedSelect = false;
var _swapping     = false;

// Lerp del cursor
var cursorIntendedX = 0.0;
var cursorIntendedY = 0.0;

// Hold timers para movimiento continuo (igual que V-Slice spamOnStep)
var holdTmrUp    = 0.0;
var holdTmrDown  = 0.0;
var holdTmrLeft  = 0.0;
var holdTmrRight = 0.0;
var INIT_SPAM    = 0.5;

// ─── SPRITES ─────────────────────────────────────────────────────────────────

// Fondos y decoración (FunkinSprite para los que son atlas)
var bgSpr;             // PNG estático
var crowdSpr;          // FunkinSprite — Animate atlas
var stageSpr;          // FunkinSprite — Animate atlas
var curtainsSpr;       // PNG estático
var barthingSpr;       // FunkinSprite — Animate atlas
var charLightSpr;      // PNG estático
var charLightGFSpr;    // PNG estático

// Personajes (FunkinSprite — Animate atlas)
var gfSpr;
var playerOutSpr;
var playerSpr;

// Foreground (mix de Sparrow y PNG)
var speakersSpr;       // FunkinSprite — Animate atlas
var fgBlurSpr;         // PNG estático
var dipshitBlurSpr;    // FunkinSprite — Sparrow
var dipshitBackingSpr; // FunkinSprite — Sparrow
var chooseDipshitSpr;  // FlxSprite   — PNG estático
var nametagSpr;        // FlxSprite   — PNG estático

// Grid de iconos (FunkinSprite para los atlas, FlxSprite para PNG plano)
var grpIcons    = [];  // Array<FunkinSprite>
var grpIsLocked = [];  // Array<Bool>

// Cursor (3 capas: darkBlue, lightBlue, main — PNG plano coloreado + Sparrow para confirm/deny)
var cursorDark;
var cursorLight;
var cursorMain;
var cursorConfirm;     // FunkinSprite — Sparrow
var cursorDenied;      // FunkinSprite — Sparrow

// Overlay de intro
var blackScreen;

// Sprite por defecto cuando no hay personaje (randomChill Sparrow)
var randomChillSpr;

// Overlay de desbloqueo (lockedChill atlas — se muestra al confirmar slot bloqueado)
var unlockOverlaySpr;

// SFX precargados
var sfxSelect;
var sfxLocked;
var sfxConfirm;
var sfxStatic;

// ═══════════════════════════════════════════════════════════════════════════════
//  onCreate
// ═══════════════════════════════════════════════════════════════════════════════

function onCreate() {
    trace('[CharSelect] A - inicio onCreate');
    rememberedChar = (save != null && save.selectedBF != null) ? save.selectedBF : '';
    trace('[CharSelect] B - save OK, rememberedChar=' + rememberedChar);

    availableChars = _loadCharSelectList();
    trace('[CharSelect] C - chars cargados: ' + availableChars.length);

    var startIdx = 4;
    if (rememberedChar != '') {
        for (i in 0...availableChars.length)
            if (availableChars[i] == rememberedChar) { startIdx = i; break; }
    }
    trace('[CharSelect] D - startIdx=' + startIdx);

    if (availableChars[startIdx] == null) {
        for (j in 0...availableChars.length) {
            if (availableChars[j] != null) { startIdx = j; break; }
        }
    }
    trace('[CharSelect] E - startIdx final=' + startIdx);

    _setCursorFromIndex(startIdx, true);
    curChar       = (availableChars[startIdx] != null) ? availableChars[startIdx] : 'bf';
    lastValidChar = curChar;
    trace('[CharSelect] paso 1 - cursor OK, curChar=' + curChar);

    // ── Música ────────────────────────────────────────────────────────────────
    try { ui.playMusic('stayFunky/stayFunky', 0.0); } catch(e:Dynamic) {
        try { FlxG.sound.playMusic(Paths.music('stayFunky/stayFunky'), 0.0); } catch(e2:Dynamic) {}
    }
    trace('[CharSelect] paso 2 - musica OK');

    // ── Escena ────────────────────────────────────────────────────────────────
    _buildBackground();
    trace('[CharSelect] paso 3 - background OK');
    _buildCharacters();
    trace('[CharSelect] paso 4 - characters OK');
    _buildForeground();
    trace('[CharSelect] paso 5 - foreground OK');
    _buildGrid();
    trace('[CharSelect] paso 6 - grid OK');
    _buildCursor();
    trace('[CharSelect] paso 7 - cursor OK');
    _buildBlackScreen();
    trace('[CharSelect] paso 8 - blackscreen OK');

    // ── Intro ─────────────────────────────────────────────────────────────────
    _doIntro();
    trace('[CharSelect] paso 9 - intro OK');

    // ── Pre-cargar SFX ────────────────────────────────────────────────────────
    _preloadSFX();
    trace('[CharSelect] paso 10 - onCreate completo');
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ESCENA — FONDO
// ═══════════════════════════════════════════════════════════════════════════════

function _buildBackground() {
    // charSelectBG — PNG estático, scrollFactor 0.1
    bgSpr = new FlxSprite(-153, -150);
    try { bgSpr.loadGraphic(Paths.getBitmap('charSelect/charSelectBG')); }
    catch(e:Dynamic) { bgSpr.makeGraphic(FlxG.width + 200, FlxG.height + 200, 0xFF1A1A2E); }
    bgSpr.scrollFactor.set(0.1, 0.1);
    ui.add(bgSpr);

    // crowd — Animate atlas, scrollFactor 0.3
    crowdSpr = new FunkinSprite(0, 250);
    try {
        crowdSpr.loadAnimateAtlas(Paths.animateAtlas('images/charSelect/crowd'));
        crowdSpr.addAnim('idle', '', 24, true);
        crowdSpr.playAnim('idle');
    } catch(e:Dynamic) { crowdSpr.makeGraphic(1, 1, 0x00000000); }
    crowdSpr.scrollFactor.set(0.3, 0.3);
    ui.add(crowdSpr);

    // charSelectStage — Animate atlas
    stageSpr = new FunkinSprite(-2, 401);
    try {
        stageSpr.loadAnimateAtlas(Paths.animateAtlas('images/charSelect/charSelectStage'));
        stageSpr.addAnim('idle', '', 24, true);
        stageSpr.playAnim('idle');
    } catch(e:Dynamic) {
        try { stageSpr.loadGraphic(Paths.getBitmap('charSelect/charSelectStage')); }
        catch(e2:Dynamic) { stageSpr.makeGraphic(1, 1, 0x00000000); }
    }
    ui.add(stageSpr);

    // curtains — PNG estático, scrollFactor 1.4
    curtainsSpr = new FlxSprite(-212, 0);
    try { curtainsSpr.loadGraphic(Paths.getBitmap('charSelect/curtains')); }
    catch(e:Dynamic) { curtainsSpr.makeGraphic(1, 1, 0x00000000); }
    curtainsSpr.scrollFactor.set(1.4, 1.4);
    ui.add(curtainsSpr);

    // barThing — Animate atlas, BlendMode MULTIPLY, scale.x=2.5
    barthingSpr = new FunkinSprite(0, 50);
    try {
        barthingSpr.loadAnimateAtlas(Paths.animateAtlas('images/charSelect/barThing'));
        barthingSpr.addAnim('idle', '', 24, true);
        barthingSpr.playAnim('idle');
    } catch(e:Dynamic) {
        try { barthingSpr.loadGraphic(Paths.getBitmap('charSelect/barThing')); }
        catch(e2:Dynamic) { barthingSpr.makeGraphic(1, 1, 0x00000000); }
    }
    barthingSpr.blend  = 'multiply';
    barthingSpr.scale.x = 2.5;
    barthingSpr.scrollFactor.set(0, 0);
    ui.add(barthingSpr);

    // Intro anim: barthing baja 80px y luego sube (igual que V-Slice)
    barthingSpr.y += 80;
    ui.tween(barthingSpr, {y: barthingSpr.y - 80}, 1.3, {ease: 'expoOut'});

    // charLight — PNG estático (luz detrás del BF)
    charLightSpr = new FlxSprite(800, 250);
    try { charLightSpr.loadGraphic(Paths.getBitmap('charSelect/charLight')); }
    catch(e:Dynamic) { charLightSpr.makeGraphic(1, 1, 0x00000000); }
    ui.add(charLightSpr);

    // charLightGF — PNG estático (luz detrás de la GF)
    charLightGFSpr = new FlxSprite(180, 240);
    try { charLightGFSpr.loadGraphic(Paths.getBitmap('charSelect/charLight')); }
    catch(e:Dynamic) { charLightGFSpr.makeGraphic(1, 1, 0x00000000); }
    ui.add(charLightGFSpr);

    var _bgSlide = 200;
    bgSpr.y -= _bgSlide;        bgSpr.alpha = 0;        ui.tween(bgSpr,        {y: bgSpr.y        + _bgSlide, alpha: 1}, 1.0, {ease: 'expoOut'});
    crowdSpr.y -= _bgSlide;     crowdSpr.alpha = 0;     ui.tween(crowdSpr,     {y: crowdSpr.y     + _bgSlide, alpha: 1}, 1.1, {ease: 'expoOut'});
    stageSpr.y -= _bgSlide;     stageSpr.alpha = 0;     ui.tween(stageSpr,     {y: stageSpr.y     + _bgSlide, alpha: 1}, 1.1, {ease: 'expoOut'});
    curtainsSpr.y -= _bgSlide;  curtainsSpr.alpha = 0;  ui.tween(curtainsSpr,  {y: curtainsSpr.y  + _bgSlide, alpha: 1}, 1.2, {ease: 'expoOut'});
    barthingSpr.y -= _bgSlide;  barthingSpr.alpha = 0;  ui.tween(barthingSpr,  {y: barthingSpr.y  + _bgSlide, alpha: 1}, 1.0, {ease: 'expoOut'});
    charLightGFSpr.y -= _bgSlide; charLightGFSpr.alpha = 0; ui.tween(charLightGFSpr, {y: charLightGFSpr.y + _bgSlide, alpha: 1}, 1.1, {ease: 'expoOut'});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ESCENA — PERSONAJES
// ═══════════════════════════════════════════════════════════════════════════════

var _charBfSprites = [];   // FunkinSprite BF precargado por slot
var _charGfSprites = [];   // FunkinSprite GF precargado por slot

function _buildCharacters() {
    var startIdx    = _getGridIndex();
    var startCharId = (availableChars[startIdx] != null) ? availableChars[startIdx] : 'bf';

    // Precargar todos los char sprites — se mantienen FUERA DE PANTALLA (x=-9999)
    // en vez de exists=false. exists=false impide el update() de FlxAnimate y deja
    // el estado OpenGL sin inicializar, corrompiendo el render al activarlos.
    _charBfSprites = [];
    _charGfSprites = [];
    for (i in 0...availableChars.length) {
        var charId = availableChars[i];
        if (charId != null) {
            var bfS = new FunkinSprite(-9999, -9999);
            bfS.scrollFactor.set(0, 0);
            _loadCharAtlas(bfS, _bfAtlasPath(charId));
            ui.add(bfS);
            ui.timer(0.1, function(t) {
            if (bfS == null) return;
                _charPlayAnim(bfS, 'idle');
                bfS.exists  = true;
                bfS.visible = true;
            });
            _charBfSprites.push(bfS);

            var gfId = _getGfId(i);
            var gfS  = new FunkinSprite(-9999, -9999);
            gfS.scrollFactor.set(0, 0);
            _loadCharAtlas(gfS, _gfAtlasPath(gfId));
            ui.add(gfS);
            ui.timer(0.1, function(t) {
            if (gfS == null) return;
                _charPlayAnim(gfS, 'idle');
                gfS.exists  = true;
                gfS.visible = true;
            });
            _charGfSprites.push(gfS);
        } else {
            _charBfSprites.push(null);
            _charGfSprites.push(null);
        }
    }

    // Mover el slot inicial a posición visible
    playerSpr    = _charBfSprites[startIdx];
    gfSpr        = _charGfSprites[startIdx];
    playerOutSpr = null;

    ui.timer(0.1, function(t) {
        if (playerSpr != null) { playerSpr.x = 650; playerSpr.y = 150; }
        if (gfSpr     != null) { gfSpr.x = 0;       gfSpr.y = 200; }
    });

    // randomChill — sprite por defecto para slots sin personaje
    randomChillSpr = new FunkinSprite(650, 150);
    try {
        randomChillSpr.frames = Paths.getSparrowAtlas('charSelect/randomChill');
        randomChillSpr.animation.addByPrefix('idle', 'LOCKED MAN instance', 24, true);
        randomChillSpr.animation.play('idle');
    } catch(e:Dynamic) { randomChillSpr.makeGraphic(150, 300, 0xFF888888); }
    randomChillSpr.scrollFactor.set(0, 0);
    randomChillSpr.visible = false;
    ui.add(randomChillSpr);

    // unlockOverlaySpr — animación de desbloqueo (lockedChill Animate atlas)
    // Assets: images/charSelect/lockedChill/ (Animation.json + spritemap1.json + spritemap1.png)
    unlockOverlaySpr = new FunkinSprite(0, 0);
    try {
        unlockOverlaySpr.loadAnimateAtlas(Paths.animateAtlas('images/charSelect/lockedChill'));
        // Registrar solo los labels que existan en el atlas (los que fallen se ignoran)
        try { unlockOverlaySpr.addAnim('idle',    'idle',    24, true);  } catch(e:Dynamic) {}
        try { unlockOverlaySpr.addAnim('clicked', 'clicked', 24, false); } catch(e:Dynamic) {}
        try { unlockOverlaySpr.addAnim('unlock',  'unlock',  24, false); } catch(e:Dynamic) {}
        // Intentar reproducir idle si existe; si no, dejar el primer frame
        try { unlockOverlaySpr.playAnim('idle'); } catch(e:Dynamic) {}
    } catch(e:Dynamic) { unlockOverlaySpr.makeGraphic(1, 1, 0x00000000); }
    unlockOverlaySpr.scrollFactor.set(0, 0);
    unlockOverlaySpr.visible = false;
    ui.add(unlockOverlaySpr);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ESCENA — PRIMER PLANO Y UI
// ═══════════════════════════════════════════════════════════════════════════════

function _buildForeground() {
    // charSelectSpeakers — Animate atlas, scrollFactor 1.8
    speakersSpr = new FunkinSprite(-60, 500);
    try {
        speakersSpr.loadAnimateAtlas(Paths.animateAtlas('images/charSelect/charSelectSpeakers'));
        speakersSpr.addAnim('idle', '', 24, true);
        speakersSpr.playAnim('idle');
    } catch(e:Dynamic) { speakersSpr.makeGraphic(1, 1, 0x00000000); }
    speakersSpr.scrollFactor.set(1.8, 1.8);
    speakersSpr.scale.set(1.05, 1.05);
    ui.add(speakersSpr);

    // foregroundBlur — PNG estático, BlendMode MULTIPLY
    fgBlurSpr = new FlxSprite(-125, 170);
    try {
        fgBlurSpr.loadGraphic(Paths.getBitmap('charSelect/foregroundBlur'));
        fgBlurSpr.blend = 'multiply';
    } catch(e:Dynamic) { fgBlurSpr.makeGraphic(1, 1, 0x00000000); }
    ui.add(fgBlurSpr);

    // dipshitBlur — Sparrow atlas, BlendMode ADD
    dipshitBlurSpr = new FunkinSprite(419, -65);
    try {
        dipshitBlurSpr.frames = Paths.getSparrowAtlas('charSelect/dipshitBlur');
        dipshitBlurSpr.animation.addByPrefix('idle', 'CHOOSE vertical offset instance 1', 24, true);
        dipshitBlurSpr.animation.play('idle');
        dipshitBlurSpr.blend = 'add';
    } catch(e:Dynamic) { dipshitBlurSpr.makeGraphic(1, 1, 0x00000000); }
    dipshitBlurSpr.scrollFactor.set(0, 0);
    ui.add(dipshitBlurSpr);

    // dipshitBacking — Sparrow atlas, BlendMode ADD
    dipshitBackingSpr = new FunkinSprite(423, -17);
    try {
        dipshitBackingSpr.frames = Paths.getSparrowAtlas('charSelect/dipshitBacking');
        dipshitBackingSpr.animation.addByPrefix('idle', 'CHOOSE horizontal offset instance 1', 24, true);
        dipshitBackingSpr.animation.play('idle');
        dipshitBackingSpr.blend = 'add';
    } catch(e:Dynamic) { dipshitBackingSpr.makeGraphic(1, 1, 0x00000000); }
    dipshitBackingSpr.scrollFactor.set(0, 0);
    ui.add(dipshitBackingSpr);

    // chooseDipshit — PNG estático ("CHOOSE YOUR CHARACTER")
    chooseDipshitSpr = new FlxSprite(426, -13);
    try { chooseDipshitSpr.loadGraphic(Paths.getBitmap('charSelect/chooseDipshit')); }
    catch(e:Dynamic) { chooseDipshitSpr.makeGraphic(1, 1, 0x00000000); }
    chooseDipshitSpr.scrollFactor.set(0, 0);
    ui.add(chooseDipshitSpr);

    // Nametag — PNG estático, centrado en midpoint (1008, 100) igual que V-Slice
    nametagSpr = new FlxSprite(0, 0);
    _loadNametag(curChar);
    _positionNametag();
    nametagSpr.scrollFactor.set(0, 0);
    ui.add(nametagSpr);

    // ── Intro: foreground entra desde ARRIBA bajando ────────────────────────
    dipshitBackingSpr.y -= 210; dipshitBackingSpr.alpha = 0;
    ui.tween(dipshitBackingSpr, {y: dipshitBackingSpr.y + 210, alpha: 1}, 1.1, {ease: 'expoOut'});
    chooseDipshitSpr.y -= 200;  chooseDipshitSpr.alpha = 0;
    ui.tween(chooseDipshitSpr,  {y: chooseDipshitSpr.y  + 200, alpha: 1}, 1.0, {ease: 'expoOut'});
    dipshitBlurSpr.y -= 220;    dipshitBlurSpr.alpha = 0;
    ui.tween(dipshitBlurSpr,    {y: dipshitBlurSpr.y    + 220, alpha: 1}, 1.2, {ease: 'expoOut'});
    nametagSpr.y -= 200;        nametagSpr.alpha = 0;
    ui.tween(nametagSpr,        {y: nametagSpr.y        + 200, alpha: 1}, 1.0, {ease: 'expoOut'});
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ESCENA — GRID DE ICONOS
// ═══════════════════════════════════════════════════════════════════════════════

function _buildGrid() {
    for (i in 0...9) {
        var charId = availableChars[i];
        var col    = i % 3;
        var row    = Math.floor(i / 3);
        var ix     = col * GRID_X_SPREAD + GRID_BASE_X;
        var iy     = row * GRID_Y_SPREAD + GRID_BASE_Y;

        var iconSpr = new FunkinSprite(ix, iy);

        if (charId != null) {
            // ── Slot desbloqueado: icono del personaje ────────────────────────
            // En V-Slice se usa PixelatedIcon (extiende FlxSprite con pixel-art).
            // Aquí simplemente cargamos el PNG del icono (icons/icon-{id}.png).
            // Si tu engine tiene PixelatedIcon expuesto en ScriptAPI, úsalo en su lugar.
            var loaded = false;
            try {
                iconSpr.loadGraphic(Paths.getBitmap('icons/icon-' + charId), true, 150, 150);
                iconSpr.animation.add('normal',  [0], 0, false);
                iconSpr.animation.add('confirm', [0], 0, false);
                if (iconSpr.frames.numFrames > 1)
                    iconSpr.animation.add('losing', [1], 0, false);
                iconSpr.animation.play('normal');
                iconSpr.x += 10;
                loaded = true;
            } catch(e:Dynamic) {}

            if (!loaded) {
                iconSpr.makeGraphic(ICON_SIZE, ICON_SIZE, FlxColor.fromHSB(i * 40, 0.7, 0.85));
            }
            grpIsLocked.push(false);
        } else {
            // ── Slot bloqueado: Sparrow atlas locks.png/xml ───────────────────
            // Usa 6 variantes de color (LOCK FULL 1-6):
            //   row 0 → verde (1/2), row 1 → teal (3/4), row 2 → azul (5/6)
            var lockBase     = (row * 2) + 1;        // 1, 3, 5
            var lockSelected = lockBase + 1;          // 2, 4, 6
            var lockLoaded = false;
            try {
                iconSpr.frames = Paths.getSparrowAtlas('charSelect/locks');
                iconSpr.animation.addByPrefix('idle',
                    'LOCK FULL ' + lockBase     + ' instance', 24, true);
                iconSpr.animation.addByPrefix('selected',
                    'LOCK FULL ' + lockSelected + ' instance', 24, true);
                iconSpr.animation.play('idle');
                iconSpr.x += 15;
                lockLoaded = true;
            } catch(e:Dynamic) {}

            if (!lockLoaded) iconSpr.makeGraphic(ICON_SIZE, ICON_SIZE, 0xFF2A2A44);
            grpIsLocked.push(true);
        }

        // FIX: V-Slice solo hace setGraphicSize(128, 128) + updateHitbox().
        // El scale.set(2.0, 2.0) extra duplicaba el tamaño (128→256px), causando
        // que los iconos ocupasen toda la pantalla. Eliminado.
        iconSpr.setGraphicSize(ICON_SIZE, ICON_SIZE);
        iconSpr.updateHitbox();
        iconSpr.scrollFactor.set(0, 0);

        // Intro: entran desde ARRIBA en cascada
        iconSpr.y   -= 300;
        iconSpr.alpha = 0;
        ui.tween(iconSpr, {y: iconSpr.y + 300, alpha: 1.0}, 1.0,
            {ease: 'expoOut', delay: 0.05 + i * 0.03});

        ui.add(iconSpr);
        grpIcons.push(iconSpr);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ESCENA — CURSOR
// ═══════════════════════════════════════════════════════════════════════════════

function _buildCursor() {
    // V-Slice: 3 capas del mismo PNG (charSelect/charSelector.png) con colores
    // diferentes y BlendMode.SCREEN para crear el efecto de trail luminoso.

    // Capa darkBlue — lag más lento (0.404), BlendMode SCREEN
    cursorDark = new FunkinSprite(0, -40);
    _loadCursorLayer(cursorDark, 0xFF3C74F7, 'screen');
    ui.add(cursorDark);

    // Capa lightBlue — lag medio (0.202), BlendMode SCREEN
    cursorLight = new FunkinSprite(0, -40);
    _loadCursorLayer(cursorLight, 0xFF3EBBFF, 'screen');
    ui.add(cursorLight);

    // Capa main — sin lag, amarillo con ping-pong de color
    cursorMain = new FunkinSprite(0, -40);
    _loadCursorLayer(cursorMain, 0xFFFFFF00, null);
    // Pingpong de color amarillo → naranja igual que V-Slice
    var colorOpts = {};
    Reflect.setField(colorOpts, 'type', 3);
    FlxTween.color(cursorMain, 0.2, 0xFFFFFF00, 0xFFFFCC00, colorOpts);
    ui.add(cursorMain);

    // cursorConfirm — Sparrow atlas
    cursorConfirm = new FunkinSprite(0, -40);
    try {
        cursorConfirm.frames = Paths.getSparrowAtlas('charSelect/charSelectorConfirm');
        cursorConfirm.animation.addByPrefix('idle', 'cursor ACCEPTED instance 1', 24, true);
    } catch(e:Dynamic) { cursorConfirm.makeGraphic(150, 150, 0x00000000); }
    cursorConfirm.visible = false;
    cursorConfirm.scrollFactor.set(0, 0);
    ui.add(cursorConfirm);

    // cursorDenied — Sparrow atlas
    cursorDenied = new FunkinSprite(0, -40);
    try {
        cursorDenied.frames = Paths.getSparrowAtlas('charSelect/charSelectorDenied');
        cursorDenied.animation.addByPrefix('idle', 'cursor DENIED instance 1', 24, false);
    } catch(e:Dynamic) { cursorDenied.makeGraphic(150, 150, 0x00000000); }
    cursorDenied.visible = false;
    cursorDenied.scrollFactor.set(0, 0);
    ui.add(cursorDenied);

    // Posición inicial del cursor (sin lerp, instant)
    _updateCursorTarget();
    _snapCursor();
}

function _buildBlackScreen() {
    blackScreen = new FlxSprite(-FlxG.width * 0.5, -FlxG.height * 0.5);
    blackScreen.makeGraphic(Std.int(FlxG.width * 2), Std.int(FlxG.height * 2), 0xFF000000);
    blackScreen.scrollFactor.set(0, 0);
    ui.add(blackScreen);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  INTRO (igual que IntroSubState de V-Slice)
// ═══════════════════════════════════════════════════════════════════════════════

function _doIntro() {
    var skipIntro = (save != null && save.charSelectOldChar != null) ? save.charSelectOldChar : false;

    ui.timer(0.4, function(t) {
        ui.tween(blackScreen, {alpha: 0}, 0.3, {ease: 'quadOut',
            onComplete: function(t) {
                blackScreen.visible = false;

                if (!skipIntro) {
                    FlxG.camera.flash(0xFFFFFFFF, 0.25);
                    try { FlxG.sound.play(Paths.getSound(Paths.sound('CS_Lights')), 1.0); } catch(e:Dynamic) {}
                }

                ui.tween(FlxG.sound.music, {volume: 1.0}, 0.8, {ease: 'quadOut'});

                if (save != null) save.charSelectOldChar = true;
                FlxG.save.flush();

                allowInput = true;
                _updateCurrentChar(false);
            }
        });
    });
}

function _preloadSFX() {
    // Usamos Paths.getSound() para cargar desde disco (mods sin recompilar).
    // FlxG.sound.load(pathString) falla con archivos de mod porque pasa por
    // OpenFL Assets.getSound() que solo conoce assets compilados.
    try { sfxSelect  = FlxG.sound.load(Paths.getSound(Paths.sound('CS_select')));           } catch(e:Dynamic) {}
    try { sfxLocked  = FlxG.sound.load(Paths.getSound(Paths.sound('CS_locked')));           } catch(e:Dynamic) {}
    try { sfxConfirm = FlxG.sound.load(Paths.getSound(Paths.sound('CS_confirm')));          } catch(e:Dynamic) {}
    try {
        sfxStatic = FlxG.sound.load(Paths.getSound(Paths.sound('static loop')), 0.6, true);
    } catch(e:Dynamic) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LÓGICA DE SELECCIÓN
// ═══════════════════════════════════════════════════════════════════════════════

function _updateCurrentChar(playSound) {
    var idx    = _getGridIndex();
    trace('[CS:UCC] idx=' + idx + ' grpIsLocked.len=' + grpIsLocked.length + ' grpIcons.len=' + grpIcons.length);
    var charId = availableChars[idx];
    var locked = (grpIsLocked.length > idx && grpIsLocked[idx] == true);
    trace('[CS:UCC] charId=' + charId + ' locked=' + locked);

    if (!locked && charId != null) {
        trace('[CS:UCC] branch desbloqueado');
        if (charId != curChar) {
            trace('[CS:UCC] swap a ' + charId);
            var gfId = _getGfId(idx);
            _swapCharSprites(charId, gfId);
            curChar       = charId;
            lastValidChar = charId;
            if (sfxStatic != null) sfxStatic.stop();
        }
        trace('[CS:UCC] visibilidad sprites');
        if (randomChillSpr != null) randomChillSpr.visible = false;
        if (playerSpr      != null) { playerSpr.visible = true; playerSpr.alpha = 1.0; }
        if (gfSpr          != null) { gfSpr.visible = true;     gfSpr.alpha = 1.0; }
    } else {
        trace('[CS:UCC] branch bloqueado/null');
        curChar = 'locked';
        if (sfxStatic != null) sfxStatic.play();
        if (playerSpr      != null) playerSpr.visible = false;
        if (playerOutSpr   != null) playerOutSpr.visible = false;
        if (gfSpr          != null) gfSpr.visible = false;
        if (randomChillSpr != null) {
            randomChillSpr.visible = true;
            try { randomChillSpr.animation.play('idle', false); } catch(e:Dynamic) {}
        }
    }

    trace('[CS:UCC] nametag');
    _loadNametag(curChar);
    _positionNametag();

    trace('[CS:UCC] iconos loop');
    for (i in 0...grpIcons.length) {
        if (grpIcons[i] == null) continue;
        var targetSize = (i == idx) ? Std.int(ICON_SIZE * 1.25) : ICON_SIZE;
        try { grpIcons[i].setGraphicSize(targetSize, targetSize); grpIcons[i].updateHitbox(); } catch(e:Dynamic) {}
        if (grpIsLocked.length > i && grpIsLocked[i] == true) {
            var anim = (i == idx) ? 'selected' : 'idle';
            try { grpIcons[i].animation.play(anim); } catch(e:Dynamic) {}
        }
    }

    trace('[CS:UCC] updateCursorTarget');
    _updateCursorTarget();

    trace('[CS:UCC] sonido');
    if (playSound) {
        if (sfxSelect != null) sfxSelect.play(true);
        else try { FlxG.sound.play(Paths.getSound(Paths.sound('CS_select')), 0.8); } catch(e:Dynamic) {}
    }
    trace('[CS:UCC] fin');
}

function _swapCharSprites(newId, gfId) {
    // Mandar sprites actuales fuera de pantalla (no exists=false — corrompe OpenGL)
    if (playerSpr != null) { playerSpr.x = -9999; playerSpr.y = -9999; }
    if (gfSpr     != null) { gfSpr.x     = -9999; gfSpr.y     = -9999; }

    // Buscar slot del nuevo personaje
    var newIdx = -1;
    for (i in 0...availableChars.length) {
        if (availableChars[i] == newId) { newIdx = i; break; }
    }

    if (newIdx >= 0 && newIdx < _charBfSprites.length) {
        playerSpr = _charBfSprites[newIdx];
        gfSpr     = _charGfSprites[newIdx];
        if (playerSpr != null) { playerSpr.x = 650; playerSpr.y = 150; }
        if (gfSpr     != null) { gfSpr.x = 0;       gfSpr.y = 200; }
    }
    _swapping = false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CURSOR — POSICIONAMIENTO Y LERP
// ═══════════════════════════════════════════════════════════════════════════════

function _updateCursorTarget() {
    var w = (cursorMain != null) ? cursorMain.width  : 150;
    var h = (cursorMain != null) ? cursorMain.height : 150;
    // Fórmula exacta de V-Slice:
    cursorIntendedX = CURSOR_FACTOR * cursorX + FlxG.width  / 2 - w / 2 + CURSOR_OFFSET_X;
    cursorIntendedY = CURSOR_FACTOR * cursorY + FlxG.height / 2 - h / 2 + CURSOR_OFFSET_Y;
}

function _snapCursor() {
    _placeCursor(cursorMain,  cursorIntendedX, cursorIntendedY);
    _placeCursor(cursorLight, cursorIntendedX, cursorIntendedY);
    _placeCursor(cursorDark,  cursorIntendedX, cursorIntendedY);
    _syncConfirmDeny();
}

function _lerpCursor(dt) {
    if (cursorMain == null) return;

    // main: snap rápido (smoothLerp halfLife=0.1)
    cursorMain.x = _slerp(cursorMain.x, cursorIntendedX, dt, 0.1);
    cursorMain.y = _slerp(cursorMain.y, cursorIntendedY, dt, 0.1);

    // lightBlue: sigue al main con halfLife=0.202
    cursorLight.x = _slerp(cursorLight.x, cursorMain.x, dt, 0.202);
    cursorLight.y = _slerp(cursorLight.y, cursorMain.y, dt, 0.202);

    // darkBlue: sigue al target directo con halfLife=0.404
    cursorDark.x = _slerp(cursorDark.x, cursorIntendedX, dt, 0.404);
    cursorDark.y = _slerp(cursorDark.y, cursorIntendedY, dt, 0.404);

    _syncConfirmDeny();
}

function _syncConfirmDeny() {
    if (cursorMain == null) return;
    _placeCursor(cursorConfirm, cursorMain.x - 2, cursorMain.y - 4);
    _placeCursor(cursorDenied,  cursorMain.x - 2, cursorMain.y - 4);
}

function _placeCursor(spr, x, y) { if (spr != null) { spr.x = x; spr.y = y; } }

function _showConfirmCursor() {
    if (cursorConfirm != null) {
        cursorConfirm.visible = true;
        try { cursorConfirm.animation.play('idle', true); } catch(e:Dynamic) {}
    }
    if (cursorMain  != null) cursorMain.visible  = false;
    if (cursorLight != null) cursorLight.visible = false;
    if (cursorDark  != null) cursorDark.visible  = false;
}

function _showDenyCursor() {
    if (cursorDenied == null) return;
    cursorDenied.visible = true;
    try { cursorDenied.animation.play('idle', true); } catch(e:Dynamic) {}
    // Ocultar tras ~0.5s (duración aprox. de la anim denied)
    ui.timer(0.5, function(t) { if (cursorDenied != null) cursorDenied.visible = false; });
}

function _resetCursor() {
    if (cursorConfirm != null) cursorConfirm.visible = false;
    if (cursorMain    != null) cursorMain.visible    = true;
    if (cursorLight   != null) cursorLight.visible   = true;
    if (cursorDark    != null) cursorDark.visible    = true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CONFIRMAR / VOLVER
// ═══════════════════════════════════════════════════════════════════════════════

function _doConfirm() {
    var idx    = _getGridIndex();
    var charId = availableChars[idx];

    if (grpIsLocked[idx] || charId == null) {
        if (sfxLocked != null) sfxLocked.play(true);
        else try { FlxG.sound.play(Paths.getSound(Paths.sound('CS_locked')), 1.0); } catch(e:Dynamic) {}

        // Reproducir animación 'clicked' en el icono del slot
        if (idx < grpIcons.length && grpIcons[idx] != null) {
            try { grpIcons[idx].animation.play('selected'); } catch(e:Dynamic) {}
        }

        // Mostrar overlay de desbloqueo (lockedChill atlas) sobre el icono
        if (unlockOverlaySpr != null && idx < grpIcons.length && grpIcons[idx] != null) {
            var icon = grpIcons[idx];
            unlockOverlaySpr.x = icon.x - 20;
            unlockOverlaySpr.y = icon.y - 20;
            unlockOverlaySpr.visible = true;
            unlockOverlaySpr.alpha   = 1.0;
            _charPlayAnim(unlockOverlaySpr, 'clicked');
            // Al terminar 'clicked', reproduce 'unlock' si tiene esa animación
            ui.timer(0.55, function(t) {
                if (unlockOverlaySpr == null) return;
                _charPlayAnim(unlockOverlaySpr, 'unlock');
                // Ocultar overlay al terminar la animación unlock (~3.1s)
                ui.timer(3.2, function(t2) {
                    if (unlockOverlaySpr != null)
                        ui.tween(unlockOverlaySpr, {alpha: 0}, 0.4, {
                            onComplete: function(tw) {
                                if (unlockOverlaySpr != null) unlockOverlaySpr.visible = false;
                            }
                        });
                });
            });
        } else {
            _showDenyCursor();
            _charPlayAnim(playerSpr, 'cannot select Label');
        }
        return;
    }

    pressedSelect = true;
    allowInput    = false;

    if (sfxConfirm != null) sfxConfirm.play(true);
    else try { FlxG.sound.play(Paths.getSound(Paths.sound('CS_confirm')), 1.0); } catch(e:Dynamic) {}

    _showConfirmCursor();
    _charPlayAnim(playerSpr, 'select');
    _charPlayAnim(gfSpr,     'confirm');

    // Música baja el volumen igual que V-Slice (pitch no está disponible en HScript)
    ui.tween(FlxG.sound.music, {volume: 0.0}, 1.5, {ease: 'quadInOut'});
    FlxG.sound.music.stop();
    FlxG.sound.music.volume = 1;

    if (save != null) save.selectedBF = charId;
    FlxG.save.flush();

    ui.timer(1.5, function(t) { _goToFreeplay(false); });
}

function _goBack() {
    allowInput = false;
    try { FlxG.sound.play(Paths.getSound(Paths.sound('menus/cancelMenu')), 1.0); } catch(e:Dynamic) {}
    ui.tween(FlxG.sound.music, {volume: 0.0}, 0.7, {ease: 'quadInOut'});
    ui.timer(0.8, function(t) { _goToFreeplay(true); });
}

function _goToFreeplay(wentBack) {
    // Exit: todo sube fuera de pantalla
    if (cursorMain  != null) ui.tween(cursorMain,  {alpha: 0, y: cursorMain.y  - 200}, 0.6, {ease: 'backIn'});
    if (cursorLight != null) ui.tween(cursorLight, {alpha: 0, y: cursorLight.y - 200}, 0.6, {ease: 'backIn'});
    if (cursorDark  != null) ui.tween(cursorDark,  {alpha: 0, y: cursorDark.y  - 200}, 0.6, {ease: 'backIn'});

    if (barthingSpr       != null) ui.tween(barthingSpr,       {y: barthingSpr.y       - 250, alpha: 0}, 0.7,  {ease: 'backIn'});
    if (nametagSpr        != null) ui.tween(nametagSpr,        {y: nametagSpr.y        - 200, alpha: 0}, 0.65, {ease: 'backIn'});
    if (dipshitBackingSpr != null) ui.tween(dipshitBackingSpr, {y: dipshitBackingSpr.y - 250, alpha: 0}, 0.65, {ease: 'backIn'});
    if (chooseDipshitSpr  != null) ui.tween(chooseDipshitSpr,  {y: chooseDipshitSpr.y  - 200, alpha: 0}, 0.65, {ease: 'backIn'});
    if (dipshitBlurSpr    != null) ui.tween(dipshitBlurSpr,    {y: dipshitBlurSpr.y    - 260, alpha: 0}, 0.7,  {ease: 'backIn'});

    for (i in 0...grpIcons.length) {
        var icon = grpIcons[grpIcons.length - 1 - i];
        if (icon != null) ui.tween(icon, {y: icon.y - 300, alpha: 0}, 0.7,
            {ease: 'backIn', delay: i * 0.02});
    }

    if (playerSpr   != null) ui.tween(playerSpr,   {alpha: 0, y: playerSpr.y   - 200}, 0.7, {ease: 'backIn'});
    if (gfSpr       != null) ui.tween(gfSpr,       {alpha: 0, y: gfSpr.y       - 200}, 0.7, {ease: 'backIn'});
    if (speakersSpr != null) ui.tween(speakersSpr, {alpha: 0, y: speakersSpr.y - 150}, 0.8, {ease: 'quadIn'});
    if (fgBlurSpr   != null) ui.tween(fgBlurSpr,   {alpha: 0},                         0.6, {ease: 'quadIn'});

    if (bgSpr       != null) ui.tween(bgSpr,       {y: bgSpr.y       - 150, alpha: 0}, 0.9, {ease: 'quadIn'});
    if (crowdSpr    != null) ui.tween(crowdSpr,    {y: crowdSpr.y    - 150, alpha: 0}, 0.9, {ease: 'quadIn'});
    if (stageSpr    != null) ui.tween(stageSpr,    {y: stageSpr.y    - 150, alpha: 0}, 0.9, {ease: 'quadIn'});
    if (curtainsSpr != null) ui.tween(curtainsSpr, {y: curtainsSpr.y - 150, alpha: 0}, 0.9, {ease: 'quadIn'});

    ui.timer(1.0, function(t) { ui.switchState('FreeplayState'); });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  UPDATE
// ═══════════════════════════════════════════════════════════════════════════════

function onUpdate(dt) {
    _lerpCursor(dt);

    if (!allowInput || pressedSelect) return;

    // Hold timers para spam de movimiento (igual que V-Slice)
    var moved = false;

    if (FlxG.keys.pressed.UP    || FlxG.keys.pressed.W) { holdTmrUp    += dt; if (holdTmrUp    >= INIT_SPAM) { cursorY--; cursorY = _wrap(cursorY,-1,1); holdTmrUp    = 0; moved = true; } }
    else holdTmrUp    = 0;

    if (FlxG.keys.pressed.DOWN  || FlxG.keys.pressed.S) { holdTmrDown  += dt; if (holdTmrDown  >= INIT_SPAM) { cursorY++; cursorY = _wrap(cursorY,-1,1); holdTmrDown  = 0; moved = true; } }
    else holdTmrDown  = 0;

    if (FlxG.keys.pressed.LEFT  || FlxG.keys.pressed.A) { holdTmrLeft  += dt; if (holdTmrLeft  >= INIT_SPAM) { cursorX--; cursorX = _wrap(cursorX,-1,1); holdTmrLeft  = 0; moved = true; } }
    else holdTmrLeft  = 0;

    if (FlxG.keys.pressed.RIGHT || FlxG.keys.pressed.D) { holdTmrRight += dt; if (holdTmrRight >= INIT_SPAM) { cursorX++; cursorX = _wrap(cursorX,-1,1); holdTmrRight = 0; moved = true; } }
    else holdTmrRight = 0;

    if (moved) _updateCurrentChar(true);
}

function onKeyJustPressed(key) {
    if (!allowInput) {
        // Permitir cancelar la confirmación (V-Slice: BACK cancela si pressedSelect)
        if (pressedSelect && key == 'ESCAPE') {
            _resetCursor();
            _charPlayAnim(playerSpr, 'deselect');
            _charPlayAnim(gfSpr,     'deselect');
            ui.tween(FlxG.sound.music, {volume: 1.0}, 1.0, {ease: 'quartInOut'});
            pressedSelect = false;
            allowInput    = true;
        }
        return;
    }

    if (key == 'UP'    || key == 'W')     { cursorY--; cursorY = _wrap(cursorY,-1,1); _updateCurrentChar(true);  return; }
    if (key == 'DOWN'  || key == 'S')     { cursorY++; cursorY = _wrap(cursorY,-1,1); _updateCurrentChar(true);  return; }
    if (key == 'LEFT'  || key == 'A')     { cursorX--; cursorX = _wrap(cursorX,-1,1); _updateCurrentChar(true);  return; }
    if (key == 'RIGHT' || key == 'D')     { cursorX++; cursorX = _wrap(cursorX,-1,1); _updateCurrentChar(true);  return; }
    if (key == 'ENTER' || key == 'SPACE') { _doConfirm(); return; }
    if (key == 'ESCAPE')                  { _goBack();    return; }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  onBeatHit — BF y GF bailan al ritmo (igual que V-Slice)
// ═══════════════════════════════════════════════════════════════════════════════

function onBeatHit(beat) {
    if (_swapping) return;
    if (!pressedSelect) try { _charPlayAnim(playerSpr, 'idle'); } catch(e:Dynamic) {}
    if (beat % 2 == 0)  try { _charPlayAnim(gfSpr,    'idle'); } catch(e:Dynamic) {}
}

function onDestroy() {
    availableChars  = [];
    grpIcons        = [];
    grpIsLocked     = [];
    randomChillSpr   = null;
    unlockOverlaySpr = null;
    availableGfIds   = [];
    if (sfxStatic != null) { try { sfxStatic.stop(); } catch(e:Dynamic) {} sfxStatic = null; }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/** Índice 0..8 del slot actualmente seleccionado */
function _getGridIndex() {
    return (cursorX + 1) + (cursorY + 1) * 3;
}

/** Ajusta cursorX/Y desde un índice 0..8 */
function _setCursorFromIndex(idx, instant) {
    cursorX = idx % 3 - 1;
    cursorY = Math.floor(idx / 3) - 1;
    if (instant) { _updateCursorTarget(); _snapCursor(); }
}

/** Wrap entero en [-1, 1] */
function _wrap(v, mn, mx) {
    if (v < mn) return mx;
    if (v > mx) return mn;
    return v;
}

/** Smooth lerp exponencial (MathUtil.smoothLerpPrecision de V-Slice) */
function _slerp(a, b, dt, halfLife) {
    return b + (a - b) * Math.pow(0.5, dt / halfLife);
}

/** Ruta del atlas Animate del BF en el charSelect */
function _bfAtlasPath(charId) {
    if (charId == null || charId == '') charId = 'bf';
    return 'images/charSelect/' + charId + 'Chill';
}

/** Ruta del atlas Animate de la GF para cada personaje */
function _gfAtlasPath(charId) {
    if (charId == null || charId == '') charId = 'bf';
    return 'images/charSelect/' + charId + 'Chill';
}

/**
 * Carga un Animate atlas en un FunkinSprite y registra las animaciones
 * estándar del charSelect (idle, slidein, slideout, select, deselect, confirm,
 * cannot select Label).
 * Si falla el atlas, intenta Sparrow, luego PNG estático, luego sprite invisible.
 */
function _loadCharAtlas(spr, atlasPath) {
    var ok = false;

    // Intentar Animate atlas (tiene Animation.json)
    try {
        spr.loadAnimateAtlas(Paths.animateAtlas(atlasPath));
        spr.addAnim('idle',                  'idle',                  24, true);
        spr.addAnim('slidein',               'slidein',               24, false);
        spr.addAnim('slideout',              'slideout',              24, false);
        spr.addAnim('select',                'select',                24, false);
        spr.addAnim('deselect',              'deselect',              24, false);
        spr.addAnim('deselect loop start',   'deselect loop start',   24, true);
        spr.addAnim('confirm',               'confirm',               24, true);
        spr.addAnim('cannot select Label',   'cannot select Label',   24, false);
        spr.addAnim('unlock',                'unlock',                24, false);
        ok = true;
    } catch(e:Dynamic) {}

    // Fallback: Sparrow
    if (!ok) {
        var spPath = atlasPath.replace('images/', '');  // getSparrowAtlas ya añade images/
        try {
            spr.frames = Paths.getSparrowAtlas(spPath);
            spr.animation.addByPrefix('idle',     'idle',     24, true);
            spr.animation.addByPrefix('slidein',  'slidein',  24, false);
            spr.animation.addByPrefix('slideout', 'slideout', 24, false);
            spr.animation.addByPrefix('select',   'select',   24, false);
            spr.animation.addByPrefix('deselect', 'deselect', 24, false);
            spr.animation.addByPrefix('confirm',  'confirm',  24, true);
            ok = true;
        } catch(e2:Dynamic) {}
    }

    // Fallback final: sprite invisible
    if (!ok) { try { spr.makeGraphic(1, 1, 0x00000000); } catch(e:Dynamic) {} }
}

/**
 * Reproduce una animación en un FunkinSprite de forma segura.
 * Soporta tanto atlas (addAnim/playAnim) como Sparrow (animation.play).
 */
function _charPlayAnim(spr, animName) {
    if (spr == null) return;
    try {
        if (spr.hasAnim(animName))
            spr.playAnim(animName, true);
        else if (spr.animation != null)
            spr.animation.play(animName, true);
    } catch(e:Dynamic) {}
}

/**
 * Carga el preview estático de un personaje en un FlxSprite normal.
 * Intenta en orden: Nametag PNG, icono 150x150, color sólido.
 * Usar FlxSprite (no FunkinSprite) evita el crash de RuntimePostEffectShader.
 */
function _loadCharPreview(spr, charId, isGf) {
    if (spr == null || charId == null) return;
    var loaded = false;
    // Intentar PNG de nametag como preview grande
    if (!loaded) try {
        var path = (charId == 'bf') ? 'boyfriend' : charId;
        spr.loadGraphic(Paths.getBitmap('charSelect/' + path + 'Nametag'));
        spr.setGraphicSize(0, 200);
        spr.updateHitbox();
        loaded = true;
    } catch(e:Dynamic) {}
    // Fallback: icono
    if (!loaded) try {
        spr.loadGraphic(Paths.getBitmap('icons/icon-' + charId), true, 150, 150);
        spr.animation.add('idle', [0], 0, false);
        spr.animation.play('idle');
        spr.setGraphicSize(180, 180);
        spr.updateHitbox();
        loaded = true;
    } catch(e:Dynamic) {}
    // Fallback final: color
    if (!loaded) spr.makeGraphic(150, 300, isGf ? 0xFF994499 : 0xFF3344AA);
    spr.alpha = 1.0;
}

/** Carga el PNG del cursor (charSelector.png) con el color indicado */
function _loadCursorLayer(spr, col, blend) {
    try { spr.loadGraphic(Paths.getBitmap('charSelect/charSelector')); }
    catch(e:Dynamic) { spr.makeGraphic(150, 150, col); }
    spr.color = col;
    if (blend != null) spr.blend = blend;
    spr.scrollFactor.set(0, 0);
}

/** Carga el nametag PNG del personaje */
function _loadNametag(charId) {
    if (nametagSpr == null) return;
    var path = (charId == 'bf') ? 'boyfriend' : charId;
    try {
        nametagSpr.loadGraphic(Paths.getBitmap('charSelect/' + path + 'Nametag'));
        nametagSpr.updateHitbox();
        nametagSpr.scale.set(0.77, 0.77);
        nametagSpr.updateHitbox();
    } catch(e:Dynamic) {
        nametagSpr.makeGraphic(1, 1, 0x00000000);
    }
}

/** Centra el nametag alrededor del midpoint (1008, 100) igual que V-Slice */
function _positionNametag() {
    if (nametagSpr == null) return;
    nametagSpr.x = 1008 - nametagSpr.width  / 2;
    nametagSpr.y = 100  - nametagSpr.height / 2;
}

/**
 * Posiciona un sprite de personaje (BF o GF) después de cargar su atlas.
 * En V-Slice la posición está baked via applyStageMatrix — aquí la calculamos
 * manualmente basándonos en el tamaño del atlas cargado.
 *
 * @param spr     El FunkinSprite del personaje
 * @param isPlayer  true = BF (lado derecho del panel), false = GF (lado izquierdo)
 */
function _positionCharSprite(spr, isPlayer) {
    if (spr == null) return;
    spr.updateHitbox();

    if (isPlayer) {
        // BF: centrado en el área izquierda de la pantalla (panel de preview)
        // En V-Slice con cutoutSize=0 el BF queda aproximadamente en x=180, y=30
        spr.x = 190 - spr.width  * 0.5;
        spr.y = 20  - spr.height * 0.05;
    } else {
        // GF: ligeramente a la izquierda del BF y más atrás
        spr.x = 30 - spr.width  * 0.3;
        spr.y = 40 - spr.height * 0.05;
    }
}

/**
 * Carga la lista de personajes para el CharSelect.
 *
 * Prioridad:
 *   1. mods/{mod}/data/charSelectChars.json  ← configurable por el modder
 *   2. CharacterList.boyfriends filtrado (excluye variantes pixel/christmas/etc.)
 *
 * Formatos del JSON soportados (retrocompatibles):
 *   Strings simples: ["bf", "pico", null, null, ...]
 *   Objetos con GF:  [{"id":"bf","gf":"bf"}, {"id":"pico"}, null, ...]
 *   Mixto:           ["bf", {"id":"pico","gf":"picoGF"}, null, ...]
 *
 * El campo "gf" define la ruta del atlas GFChill. Si se omite, usa el propio charId.
 * Siempre devuelve exactamente 9 elementos.
 */
function _loadCharSelectList() {
    var list   = null;
    var gfList = null;

    try {
        var content = Paths.getText('data/charSelectChars.json');
        if (content != null && content != '') {
            list   = [];
            gfList = [];
            // Parser manual — no requiere Json.parse ni imports externos
            // Normaliza espacios/saltos, luego parte por comas de nivel raíz
            var s = content;
            // Quitar corchetes externos
            var startB = s.indexOf('[');
            var endB   = s.lastIndexOf(']');
            if (startB >= 0 && endB > startB)
                s = s.substring(startB + 1, endB);
            // Partir en tokens respetando llaves {}
            var tokens = [];
            var depth = 0;
            var cur   = '';
            var si    = 0;
            while (si < s.length) {
                var ch = s.charAt(si); si++;
                if (ch == '{') { depth++; cur += ch; }
                else if (ch == '}') { depth--; cur += ch; }
                else if (ch == ',' && depth == 0) {
                    tokens.push(cur); cur = '';
                } else { cur += ch; }
            }
            if (cur != '') tokens.push(cur);

            for (tok in tokens) {
                // Trim manual
                var t = tok.split(' ').join('').split('	').join('')
                            .split('
').join('').split('
').join('');
                if (t == 'null' || t == '') {
                    list.push(null); gfList.push(null);
                } else if (t.charAt(0) == '{') {
                    // Objeto {"id":"bf","gf":"gf"}
                    // Extraer valor de "id"
                    var idVal  = _extractJsonStr(t, 'id');
                    var gfVal  = _extractJsonStr(t, 'gf');
                    if (idVal != null && idVal != '') {
                        list.push(idVal);
                        gfList.push((gfVal != null && gfVal != '') ? gfVal : idVal);
                    } else {
                        list.push(null); gfList.push(null);
                    }
                } else {
                    // String simple "bf"
                    var plain = t.split('"').join('').split("'").join('');
                    if (plain != '' && plain != 'null') {
                        list.push(plain); gfList.push(plain);
                    } else {
                        list.push(null); gfList.push(null);
                    }
                }
            }
        }
    } catch(e:Dynamic) { trace('[CharSelect] Error leyendo charSelectChars.json: ' + e); }

    if (list == null) { list = []; gfList = []; }

    // Normalizar a exactamente 9 slots
    if (gfList == null) gfList = [];
    while (list.length < 9)   { list.push(null);   gfList.push(null); }
    if (list.length > 9)      { list   = list.slice(0, 9);
                                 gfList = gfList.slice(0, 9); }

    availableGfIds = gfList;
    return list;
}

/** Obtiene el GF ID para el slot idx (usa charId como fallback). */
function _getGfId(idx) {
    if (availableGfIds == null || idx < 0 || idx >= availableGfIds.length) return availableChars[idx];
    var gfId = availableGfIds[idx];
    if (gfId == null || gfId == '') gfId = availableChars[idx];
    return gfId;
}

/**
 * Parser legacy — ya no se usa. _loadCharSelectList usa Json.parse() directamente.
 * Se conserva como fallback por compatibilidad.
 */
function _parseJsonStringArray(raw) {
    // FIX: String.trim(), .startsWith() no funcionan en HScript via Reflect.
    // Se reemplazan por operaciones básicas: split/join para trim,
    // y charAt(0) == '"' para detectar strings entre comillas.
    var result = [];
    // Quitar corchetes — sin .trim() (no funciona en HScript)
    var trimmed = raw.split('[').join('').split(']').join('')
                     .split(' ').join('').split('\t').join('')
                     .split('\r').join('').split('\n').join('');
    var parts = trimmed.split(',');
    for (part in parts) {
        // Trim manual: quitar espacios, tabs y saltos de línea
        var p = part.split(' ').join('').split('\t').join('')
                    .split('\r').join('').split('\n').join('');
        // Detectar string entre comillas: charAt(0) en vez de startsWith
        var firstCh = (p.length > 0) ? p.charAt(0) : '';
        if (firstCh == '"' || firstCh == "'") {
            p = p.split('"').join('').split("'").join('');
            if (p != '') result.push(p);
            else result.push(null);
        } else if (p == 'null' || p == '') {
            result.push(null);
        } else if (p != '') {
            result.push(p);
        }
    }
    return result;
}
/**
 * Extrae el valor de una clave string dentro de un fragmento JSON tipo objeto.
 * Ejemplo: _extractJsonStr('{"id":"bf","gf":"gf"}', 'id') => 'bf'
 * No depende de Json.parse — usa solo operaciones de string básicas.
 */
function _extractJsonStr(obj, key) {
    var needle = '"' + key + '"';
    var ki = obj.indexOf(needle);
    if (ki < 0) return null;
    var rest = obj.substring(ki + needle.length);
    // buscar ':'
    var ci = rest.indexOf(':');
    if (ci < 0) return null;
    rest = rest.substring(ci + 1);
    // buscar '"' de apertura
    var q1 = rest.indexOf('"');
    if (q1 < 0) return null;
    rest = rest.substring(q1 + 1);
    // buscar '"' de cierre
    var q2 = rest.indexOf('"');
    if (q2 < 0) return null;
    return rest.substring(0, q2);
}
