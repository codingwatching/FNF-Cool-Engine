package funkin.scripting;

import funkin.scripting.IScript;
import funkin.scripting.ScriptEvent;

// ── Lua support ───────────────────────────────────────────────────────────────
//
//  Requiere linc_lua (usa llua.*):
//    Descargar zip: https://github.com/snowkit/linc_lua/archive/refs/heads/master.zip
//    Instalar:      haxelib dev linc_lua ruta/a/linc_lua-master
//    Project.xml:   <haxedef name="LUA_ALLOWED"/> <haxelib name="linc_lua"/>
//
//  NO usar hxlua — su paquete lua.* es incompatible con el target cpp.
//
#if (LUA_ALLOWED && linc_luajit)
import llua.Lua;
import llua.LuaL;
import llua.State;
#end

// Alias para que el resto del código use un único flag
#if (LUA_ALLOWED && linc_luajit)
@:noCompletion private typedef _LuaState = State;
#end

/**
 * LuaScriptInstance v2 — paridad total con HScript.
 *
 *
 * ─── Object Registry ─────────────────────────────────────────────────────────
 *
 *  Lua no puede guardar referencias a objetos Haxe directamente.
 *  Solución: cada objeto se registra en un Map<Int, Dynamic> y Lua recibe
 *  un entero (handle). Con ese handle puede llamar métodos y leer/escribir
 *  cualquier propiedad del objeto real en Haxe.
 *
 *    local spr = newObject('FlxSprite', 0, 0)    -- handle
 *    setProp(spr, 'x', 300)
 *    callMethod(spr, 'loadGraphic', 'myImage')
 *    addToState(spr)
 *
 * ─── Sistema de clases Lua (metatables) ──────────────────────────────────────
 *
 *    MyChar = Class {
 *        init = function(self, x, y)
 *            self.sprite = makeFunkinSprite('char', x, y)
 *            loadSparrow(self.sprite, 'characters/myChar')
 *            addAnim(self.sprite, 'idle', 'idle0', 24, true)
 *            addToState(self.sprite)
 *        end,
 *        onBeat = function(self, beat)
 *            if beat % 2 == 0 then playAnim(self.sprite, 'idle', false) end
 *        end
 *    }
 *    myChar = MyChar.new(400, 200)
 *
 * ─── Estado propio desde Lua ──────────────────────────────────────────────────
 *
 *    switchState('FreeplayState')
 *    switchState('PlayState')
 *
 * ─── Health icon ──────────────────────────────────────────────────────────────
 *
 *    setHealthIcon('player',   'myIcon')
 *    setHealthIcon('opponent', 'bossIcon')
 *    setHealthIconScale('player', 1.5)
 *    setHealthIconOffset('player', -10, 0)
 *
 * ─── Strumlines ───────────────────────────────────────────────────────────────
 *
 *    setStrumAlpha(0, 0.0)            -- ocultar notas del jugador
 *    setStrumPosition(0, 100, 50)     -- mover strumline
 *    setStrumScale(1, 0.8)
 *
 * ─── Menú/UI completo ────────────────────────────────────────────────────────
 *
 *    local title = makeText(0, 0, 1280, 'Mi Mod', 64)
 *    setTextAlign(title, 'center')
 *    setTextBorder(title, 2, Color.BLACK)
 *    setTextColor(title, Color.WHITE)
 *    setProp(title, 'y', 100)
 *    addToState(title)
 *
 *    local bg = newObject('FlxSprite', 0, 0)
 *    loadImage(bg, 'menuBg')
 *    setSpriteScrollFactor(bg, 0, 0)
 *    addToState(bg, false)     -- atrás del todo
 *
 * ─── Tweens y Timers ──────────────────────────────────────────────────────────
 *
 *    tweenProp(spr, 'alpha', 0, 1.0, Ease.quadOut)
 *    tweenProp(spr, 'x',    500, 0.5, Ease.sineOut)
 *    tweenColor(spr, 0.5, Color.RED, Color.WHITE)
 *    timer(2.0, 'myCallback')    -- llama la función global myCallback()
 *
 * ─── Input ────────────────────────────────────────────────────────────────────
 *
 *    function onUpdate(elapsed)
 *        if keyJustPressed('SPACE') then doJump() end
 *        if mouseJustPressed() then handleClick(mouseX(), mouseY()) end
 *    end
 *
 * ─── Cutscenes ────────────────────────────────────────────────────────────────
 *
 *    function onSongStart()
 *        local b = newCutscene()
 *        cutsceneDefineRect(b, 'bg', 'BLACK')
 *        cutsceneAdd(b, 'bg')
 *        cutsceneStageAnim(b, 'bf', 'intro')
 *        cutsceneWait(b, 1.5)
 *        cutscenePlay(b)
 *    end
 *
 * @author  Cool Engine Team
 * @since   0.7.0
 */
class LuaScriptInstance implements IScript
{
	public var id       :String;
	public var filePath (default, null):Null<String>;
	public var active   :Bool = false;
	public var errored  :Bool = false;
	public var lastError:Null<String> = null;

	#if (LUA_ALLOWED && linc_luajit)
	var _lua:Dynamic;

	/** Source code cache for hotReload(). Set by loadString(). */
	var _source:String = '';

	// ── Object Registry ──────────────────────────────────────────────────────
	static var _reg    : Map<Int, Dynamic> = new Map();
	static var _regCtr : Int = 1;

	// Mapa tag → handle (para compatibilidad makeSprite/tag de Psych)
	static var _tags   : Map<String, Int>  = new Map();

	// Factories para newObject()
	static var _factories : Map<String, Array<Dynamic>->Dynamic> = _defaultFactories();

	// Mapa handle de timer → instancia del script (para callbacks Lua reales)
	static var _timerScripts : Map<Int, LuaScriptInstance> = new Map();
	#end

	public function new(id:String, ?filePath:String)
	{
		this.id = id; this.filePath = filePath;
		#if (LUA_ALLOWED && linc_luajit)
		_lua = LuaL.newstate();
		LuaL.openlibs(_lua);
		_registerAll();
		LuaL.dostring(_lua, _getSTDLIB());
		#end
	}

	public function loadFile(?path:String):LuaScriptInstance
	{
		#if (LUA_ALLOWED && sys)
		final p = path ?? filePath;
		if (p == null) { _error('loadFile() sin ruta'); return this; }
		filePath = p;
		if (!sys.FileSystem.exists(p)) { _error('No encontrado: $p'); return this; }
		try { return loadString(sys.io.File.getContent(p)); }
		catch (e:Dynamic) { _error('Error leyendo $p: $e'); }
		#end
		return this;
	}

	public function loadString(src:String):LuaScriptInstance
	{
		#if (LUA_ALLOWED && linc_luajit)
		active = errored = false;
		if (src != null) _source = src;
		if (LuaL.dostring(_lua, src) != 0)
		{
			final e = Lua.tostring(_lua, -1); Lua.pop(_lua, 1);
			_error('[$id] $e'); return this;
		}
		active = true;
		// Registrar esta instancia para que los timers puedan llamar callbacks
		final selfHandle = register(this);
		_timerScripts.set(selfHandle, this);
		Lua.pushnumber(_lua, selfHandle); Lua.setglobal(_lua, '__scriptHandle');
		#end
		return this;
	}

	public function call(fn:String, ?args:Array<Dynamic>):Dynamic
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (!active) return null;
		if (args == null) args = [];
		_sCurrentLua = _lua;
		Lua.getglobal(_lua, fn);
		if (Lua.type(_lua, -1) != 6) { Lua.pop(_lua, 1); return null; }
		for (a in args) _push(_lua, a);
		if (Lua.pcall(_lua, args.length, 1, 0) != 0)
		{
			final e = Lua.tostring(_lua, -1); Lua.pop(_lua, 1);
			trace('[Lua:$id] $fn — $e'); return null;
		}
		return _pop(_lua);
		#else return null; #end
	}

	public function set(name:String, v:Dynamic):Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua == null) return; _push(_lua, v); Lua.setglobal(_lua, name);
		#end
	}

	public function get(name:String):Dynamic
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua == null) return null; Lua.getglobal(_lua, name); return _pop(_lua);
		#else return null; #end
	}

	public function hasFunction(name:String):Bool
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua == null) return false;
		Lua.getglobal(_lua, name);
		final r = Lua.type(_lua, -1) == 6; Lua.pop(_lua, 1); return r;
		#else return false; #end
	}

	public function destroy():Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		active = false; if (_lua != null) { Lua.close(_lua); _lua = null; }
		#end
	}

	/**
	 * Alias for destroy() — matches HScriptInstance.dispose() API.
	 */
	public inline function dispose():Void destroy();

	/**
	 * hotReload() — reloads the Lua script from disk (or cached source).
	 *
	 * Steps:
	 *  1. If filePath exists on disk, re-reads the file to pick up changes.
	 *  2. Closes the current Lua state and opens a fresh one.
	 *  3. Re-registers all C functions and stdlib.
	 *  4. Re-executes the source code.
	 *  5. Calls onCreate() and postCreate() if defined.
	 *
	 * Returns true on success, false if the source is missing or there's an error.
	 */
	public function hotReload():Bool
	{
		#if (LUA_ALLOWED && linc_luajit)
		// Re-read from disk if we have a file path
		#if sys
		if (filePath != null && filePath != '' && sys.FileSystem.exists(filePath))
		{
			try { _source = sys.io.File.getContent(filePath); }
			catch (e:Dynamic)
			{
				_error('hotReload: cannot read $filePath: $e');
				return false;
			}
		}
		#end
		if (_source == null || _source.length == 0)
		{
			trace('[LuaScript:$id] hotReload: no source to reload.');
			return false;
		}

		// Close old state, open a fresh one
		if (_lua != null) { Lua.close(_lua); _lua = null; }
		_lua = LuaL.newstate();
		LuaL.openlibs(_lua);
		_registerAll();
		LuaL.dostring(_lua, _getSTDLIB());

		// Execute the cached source
		active = errored = false;
		if (LuaL.dostring(_lua, _source) != 0)
		{
			final e = Lua.tostring(_lua, -1); Lua.pop(_lua, 1);
			_error('[$id] hotReload error: $e');
			return false;
		}
		active = true;

		// Re-register self handle so timer callbacks still work
		final h = register(this);
		_timerScripts.set(h, this);
		Lua.pushnumber(_lua, h); Lua.setglobal(_lua, '__scriptHandle');

		// Lifecycle hooks
		call('onCreate');
		call('postCreate');

		trace('[LuaScript:$id] Hot-reloaded: ${filePath ?? "(in-memory)"}');
		return true;
		#else
		return false;
		#end
	}

	// ── Registro de clases adicionales ───────────────────────────────────────
	public static function registerClass(name:String, factory:Array<Dynamic>->Dynamic):Void
	{
		#if (LUA_ALLOWED && linc_luajit) _factories.set(name, factory); #end
	}

	// ── Object Registry helpers ───────────────────────────────────────────────
	#if (LUA_ALLOWED && linc_luajit)
	public static function register(obj:Dynamic):Int
	{
		final h = _regCtr++; _reg.set(h, obj); return h;
	}
	public static inline function resolve(h:Int):Dynamic return _reg.get(h);
	public static inline function release(h:Int):Void  _reg.remove(h);

	// ─────────────────────────────────────────────────────────────────────────
	// REGISTRO DE FUNCIONES
	// ─────────────────────────────────────────────────────────────────────────
	function _registerAll():Void
	{
		inline function r(n, f) Lua.register(_lua, n, f);

		// Object Registry
		r('newObject',        _fnNew);
		r('getProp',          _fnGetProp);
		r('setProp',          _fnSetProp);
		r('callMethod',       _fnCall);
		r('destroyObject',    _fnDestroy);

		// Escena
		r('addToState',       _fnAddState);
		r('removeFromState',  _fnRemState);
		r('addToGroup',       _fnAddGroup);
		r('removeFromGroup',  _fnRemGroup);
		r('switchState',      _fnSwitch);

		// Propiedades path-style (Psych-compat)
		r('getProperty',      _fnGetPath);
		r('setProperty',      _fnSetPath);
		r('getPropertyOf',    _fnGetOf);
		r('setPropertyOf',    _fnSetOf);

		// Personajes
		r('triggerAnim',      _fnTriggerAnim);
		r('characterDance',   _fnDance);
		r('getCharHandle',    _fnCharHandle);

		// Health icons
		r('setHealthIcon',        _fnSetHIcon);
		r('setHealthIconScale',   _fnSetHIconScale);
		r('setHealthIconOffset',  _fnSetHIconOffset);
		r('getHealthIconHandle',  _fnGetHIconHandle);

		// Strumlines
		r('setStrumAlpha',    _fnStrumAlpha);
		r('setStrumScale',    _fnStrumScale);
		r('setStrumPosition', _fnStrumPos);
		r('hideStrumNotes',   _fnStrumHide);
		r('getStrumHandle',   _fnStrumHandle);

		// Sprites
		r('makeSprite',          _fnMakeSprite);
		r('makeFunkinSprite',    _fnMakeFunkin);
		r('loadImage',           _fnLoadImg);
		r('loadGraphic',         _fnLoadImg);
		r('loadSparrow',         _fnLoadSparrow);
		r('loadAtlas',           _fnLoadAtlas);
		r('addAnim',             _fnAddAnim);
		r('addAnimOffset',       _fnAddAnimOff);
		r('playAnim',            _fnPlayAnim);
		r('stopAnim',            _fnStopAnim);
		r('addSprite',           _fnAddSpr);
		r('removeSprite',        _fnRemSpr);
		r('setSpriteScale',      _fnSprScale);
		r('setSpriteFlip',       _fnSprFlip);
		r('setSpriteAlpha',      _fnSprAlpha);
		r('setSpriteColor',      _fnSprColor);
		r('setSpritePosition',   _fnSprPos);
		r('setSpriteScrollFactor', _fnSprScroll);
		r('setAntialiasing',     _fnSprAA);
		r('screenCenter',        _fnSprCenter);

		// Texto
		r('makeText',       _fnMakeText);
		r('setText',        _fnSetText);
		r('setTextSize',    _fnTextSize);
		r('setTextFont',    _fnTextFont);
		r('setTextBold',    _fnTextBold);
		r('setTextAlign',   _fnTextAlign);
		r('setTextBorder',  _fnTextBorder);
		r('setTextColor',   _fnTextColor);

		// Cámara
		r('setCamZoom',       _fnCamZoom);
		r('setCamZoomTween',  _fnCamZoomTween);
		r('cameraFlash',      _fnCamFlash);
		r('cameraShake',      _fnCamShake);
		r('cameraFade',       _fnCamFade);
		r('cameraPan',        _fnCamPan);
		r('cameraSnapTo',     _fnCamSnap);
		r('getCamHandle',     _fnCamHandle);
		r('makeCam',          _fnMakeCam);

		// Tweens
		r('tweenProp',    _fnTweenProp);
		r('tween',        _fnTweenProp);   // alias
		r('tweenColor',   _fnTweenColor);
		r('tweenCancel',  _fnTweenCancel);

		// Timers
		r('timer',        _fnTimer);
		r('timerCancel',  _fnTimerCancel);

		// Cutscenes
		r('newCutscene',          _fnCutNew);
		r('cutsceneSkippable',    _fnCutSkip);
		r('cutsceneDefineRect',   _fnCutRect);
		r('cutsceneDefineSprite', _fnCutSpr);
		r('cutsceneAdd',          _fnCutAdd);
		r('cutsceneRemove',       _fnCutRem);
		r('cutsceneWait',         _fnCutWait);
		r('cutsceneStageAnim',    _fnCutAnim);
		r('cutscenePlaySound',    _fnCutSound);
		r('cutsceneCameraZoom',   _fnCutCamZ);
		r('cutsceneCameraFlash',  _fnCutCamF);
		r('cutscenePlay',         _fnCutPlay);

		// Gameplay
		r('addScore',    _fnAddScore);    r('setScore',   _fnSetScore);
		r('getScore',    _fnGetScore);    r('addHealth',  _fnAddHealth);
		r('setHealth',   _fnSetHealth);   r('getHealth',  _fnGetHealth);
		r('setMisses',   _fnSetMisses);   r('getMisses',  _fnGetMisses);
		r('setCombo',    _fnSetCombo);    r('getCombo',   _fnGetCombo);
		r('endSong',     _fnEndSong);     r('gameOver',   _fnGameOver);
		r('pauseGame',   _fnPause);       r('resumeGame', _fnResume);

		// Notas
		r('spawnNote',   _fnSpawnNote);
		r('getNoteDir',  _fnNoteDir);
		r('getNoteTime', _fnNoteTime);

		// Audio
		r('playMusic',    _fnPlayMusic);  r('stopMusic',   _fnStopMusic);
		r('pauseMusic',   _fnPauseMusic); r('resumeMusic', _fnResumeMusic);
		r('playSound',    _fnPlaySound);
		r('getMusicPos',  _fnMusicPos);   r('setMusicPos', _fnSetMusicPos);
		r('setMusicPitch',_fnMusicPitch);

		// Config
		r('setConfig',  _fnSetConfig);    r('getConfig',  _fnGetConfig);

		// Input
		r('keyPressed',       _fnKeyP);   r('keyJustPressed',   _fnKeyJP);
		r('keyJustReleased',  _fnKeyJR);
		r('mouseX',           _fnMouseX); r('mouseY',           _fnMouseY);
		r('mousePressed',     _fnMouseP); r('mouseJustPressed', _fnMouseJP);

		// Utils
		r('trace',        _fnTrace);      r('log',         _fnTrace);
		r('getBeat',      _fnBeat);       r('getStep',     _fnStep);
		r('getBPM',       _fnBPM);        r('getSongPos',  _fnSongPos);
		r('randomInt',    _fnRndInt);     r('randomFloat', _fnRndFlt);
		r('colorRGB',     _fnRGB);        r('colorRGBA',   _fnRGBA);
		r('colorHex',     _fnHex);
		r('lerp',         _fnLerp);       r('clamp',       _fnClamp);
		r('fileExists',   _fnFileEx);     r('fileRead',    _fnFileR);
		r('fileWrite',    _fnFileW);

		// ── Datos compartidos entre scripts ──────────────────────────────────
		r('setShared',    _fnSetShared);  r('getShared',   _fnGetShared);
		r('deleteShared', _fnDelShared);

		// ── Comunicación con otros scripts ───────────────────────────────────
		r('broadcast',      _fnBroadcast);
		r('callOnScripts',  _fnCallScripts);
		r('setScriptVar',   _fnSetScriptVar);
		r('getScriptVar',   _fnGetScriptVar);

		// ── Personajes: control extendido ────────────────────────────────────
		r('setCharPos',         _fnCharPos);
		r('setCharX',           _fnCharX);
		r('setCharY',           _fnCharY);
		r('getCharX',           _fnCharGetX);
		r('getCharY',           _fnCharGetY);
		r('setCharScale',       _fnCharScale);
		r('setCharVisible',     _fnCharVisible);
		r('setCharAlpha',       _fnCharAlpha);
		r('setCharColor',       _fnCharColor);
		r('setCharAngle',       _fnCharAngle);
		r('setCharFlip',        _fnCharFlip);
		r('setCharScrollFactor',_fnCharScroll);
		r('getCharAnim',        _fnCharGetAnim);
		r('isAnimFinished',     _fnCharAnimDone);
		r('lockCharacter',      _fnCharLock);
		r('setCharPlaybackRate',_fnCharRate);
		r('setBF',              _fnSetBF);
		r('setDAD',             _fnSetDAD);
		r('setGF',              _fnSetGF);
		r('getSongName',        _fnSongName);
		r('getSongArtist',      _fnSongArtist);

		// ── Gameplay extendido ───────────────────────────────────────────────
		r('isStoryMode',   _fnIsStory);
		r('getDifficulty', _fnGetDiff);
		r('getAccuracy',   _fnGetAcc);
		r('getSicks',      _fnGetSicks);
		r('getGoods',      _fnGetGoods);
		r('getBads',       _fnGetBads);
		r('getShits',      _fnGetShits);
		r('setSicks',      _fnSetSicks);
		r('setScrollSpeed',_fnSetScroll);
		r('getScrollSpeed',_fnGetScroll);
		r('setNoteAlpha',  _fnNoteAlpha);
		r('setNoteColor',  _fnNoteColor);
		r('skipNote',      _fnSkipNote);
		r('setNoteSkin',   _fnNoteSkin);

		// ── Notas: generación dinámica ───────────────────────────────────────
		r('forEachNote',   _fnForNote);

		// ── Modchart ─────────────────────────────────────────────────────────
		r('setModifier',   _fnSetMod);
		r('getModifier',   _fnGetMod);
		r('clearModifiers',_fnClearMods);
		r('noteModifier',  _fnNoteMod);

		// ── Vocales ──────────────────────────────────────────────────────────
		r('setVocalsVolume',    _fnVocVol);
		r('setPlayerVocals',    _fnVocP);
		r('setOpponentVocals',  _fnVocOp);
		r('muteVocals',         _fnMuteVoc);

		// ── Eventos ──────────────────────────────────────────────────────────
		r('triggerEvent',   _fnTriggerEv);
		r('registerEvent',  _fnRegisterEv);
		// getEventDef(name)              → tabla con { name, description, color, contexts, params }
		r('getEventDef',    _fnGetEventDef);
		// listEvents(?context)           → tabla de nombres de eventos
		r('listEvents',     _fnListEvents);
		// registerEventDef(table)        → registra una nueva definición en EventRegistry
		r('registerEventDef', _fnRegisterEventDef);

		// ── Tweens extendidos ────────────────────────────────────────────────
		r('tweenAngle',    _fnTweenAngle);
		r('tweenPosition', _fnTweenPos);
		r('tweenAlpha',    _fnTweenAlpha);
		r('tweenScale',    _fnTweenScale);
		r('tweenNumTween', _fnNumTween);

		// ── Texto extendido ──────────────────────────────────────────────────
		r('setTextItalic', _fnTextItalic);
		r('setTextShadow', _fnTextShadow);
		r('getText',       _fnGetText);

		// ── Sprites extendidos ───────────────────────────────────────────────
		r('setSpriteAngle',    _fnSprAngle);
		r('setSpriteVisible',  _fnSprVisible);
		r('getSpriteX',        _fnSprGetX);
		r('getSpriteY',        _fnSprGetY);
		r('getSpriteWidth',    _fnSprGetW);
		r('getSpriteHeight',   _fnSprGetH);
		r('updateHitbox',      _fnUpdateHitbox);
		r('setFrameSize',      _fnFrameSize);
		r('addAnimByIndices',  _fnAddAnimIdx);
		r('getCurAnim',        _fnGetCurAnim);
		r('isAnimPlaying',     _fnIsAnimPlay);
		r('setAnimFPS',        _fnSetAnimFPS);
		r('addSpriteToCamera', _fnSprCam);

		// ── Cámara: control fino ──────────────────────────────────────────────
		r('setCamTarget',     _fnCamTarget);
		r('setCamFollowStyle',_fnCamFollow);
		r('setCamLerp',       _fnCamLerp);
		r('getCamZoom',       _fnGetCamZoom);
		r('setCamScrollX',    _fnCamScrollX);
		r('setCamScrollY',    _fnCamScrollY);
		r('removeCam',        _fnRemoveCam);

		// ── Shaders ───────────────────────────────────────────────────────────
		r('addShader',       _fnAddShader);
		r('removeShader',    _fnRemoveShader);
		r('setShaderProp',   _fnShaderProp);

		// ── UI / Diálogos (usa ScriptDialog — misma clase que HScript) ───────
		r('showNotification', _fnNotif);
		r('newDialog',        _fnNewDialog);
		r('dialogAddLine',    _fnDialogAddLine);
		r('dialogSetPortrait',   _fnDialogPortrait);
		r('dialogSetTypeSpeed',  _fnDialogTypeSpeed);
		r('dialogSetAutoAdvance',_fnDialogAutoAdv);
		r('dialogSetSpeakerColor',_fnDialogSpColor);
		r('dialogSetBgColor',    _fnDialogBgColor);
		r('dialogSetAllowSkip',  _fnDialogAllowSkip);
		r('dialogOnFinish',   _fnDialogOnFinish);
		r('dialogOnLine',     _fnDialogOnLine);
		r('dialogShow',       _fnDialogShow);
		r('dialogClose',      _fnDialogClose);
		r('dialogSkipAll',    _fnDialogSkipAll);
		r('showDialog',       _fnDialogQuick);     // atajo: una línea
		r('dialogSequence',   _fnDialogSequence);  // atajo: varias líneas
		r('closeDialog',      _fnCloseAllDialogs);

		// ── Datos persistentes (JSON por mod) ─────────────────────────────────
		r('dataSave',  _fnDataSave);
		r('dataLoad',  _fnDataLoad);
		r('dataExists',_fnDataExists);
		r('dataDelete',_fnDataDelete);

		// ── JSON ──────────────────────────────────────────────────────────────
		r('jsonEncode', _fnJsonEnc);
		r('jsonDecode', _fnJsonDec);

		// ── Strings / Tablas ──────────────────────────────────────────────────
		r('stringSplit',    _fnStrSplit);
		r('stringContains', _fnStrContains);
		r('stringTrim',     _fnStrTrim);
		r('stringReplace',  _fnStrReplace);
		r('tableLength',    _fnTableLen);

		// ── Input extendido ───────────────────────────────────────────────────
		r('gamepadPressed',      _fnPadP);
		r('gamepadJustPressed',  _fnPadJP);
		r('mouseRightPressed',   _fnMouseRP);
		r('mouseRightJustPressed',_fnMouseRJP);

		// ── Notas: splash / holds ─────────────────────────────────────────────
		r('showNoteSplash',  _fnNoteSplash);
		r('holdNoteActive',  _fnHoldActive);

		// ── Transiciones ─────────────────────────────────────────────────────
		r('fadeIn',   _fnFadeIn);
		r('fadeOut',  _fnFadeOut);

		// ── Subtítulos ────────────────────────────────────────────────────────
		// showSubtitle(text, duration, ?optsTable)
		// showSubtitle("Hello", 3.0)
		// showSubtitle("Hello", 2.0, { size=28, color=0xFFFF00, bgAlpha=0.7 })
		r('showSubtitle',        _fnSubShow);
		// hideSubtitle(?instant)   -- sin args = fade suave, true = instantáneo
		r('hideSubtitle',        _fnSubHide);
		// clearSubtitles()         -- hide + vacía la cola
		r('clearSubtitles',      _fnSubClear);
		// queueSubtitle(table)     -- tabla de { text, duration[, size, color...] }
		r('queueSubtitle',       _fnSubQueue);
		// setSubtitleStyle(table)  -- estilo global para futuros showSubtitle()
		r('setSubtitleStyle',    _fnSubStyle);
		// resetSubtitleStyle()     -- restaura defaults
		r('resetSubtitleStyle',  _fnSubReset);

		// ── import(className) ────────────────────────────────────────────────
		// Resuelve una clase o enum Haxe por nombre completo y la devuelve
		// como valor Lua (objeto Dynamic). Permite acceder a constantes estáticas
		// y constructores sin necesidad de newObject().
		//
		// Uso:
		//   local FlxColor = import('flixel.util.FlxColor')
		//   local red = FlxColor.RED
		//   local col = FlxColor.fromRGB(255, 0, 0)
		//
		//   local FlxAxes = import('flixel.util.FlxAxes')
		//   local axes = FlxAxes.XY
		//
		// Nota: devuelve nil si la clase no está disponible en el build.
		r('import', function(l) {
			final fullName = Lua.tostring(l, 1);
			Lua.pop(l, 1);
			var resolved:Dynamic = Type.resolveClass(fullName);
			if (resolved == null) resolved = Type.resolveEnum(fullName);
			if (resolved == null)
			{
				trace('[Lua:$id] import: clase no encontrada: $fullName');
				Lua.pushnil(l);
			}
			else
			{
				// Registrar como global con el nombre corto (FlxAxes, FlxColor, etc.)
				// para que se pueda usar directamente sin asignar a variable.
				final shortName = fullName.split('.').pop();
				_push(l, resolved);
				Lua.pushvalue(l, -1);          // duplicar en el stack
				Lua.setglobal(l, shortName);   // _G[shortName] = resolved
				trace('[Lua:$id] import $fullName → global $shortName');
			}
			return 1;
		});
	}

	// ─────────────────────────────────────────────────────────────────────────
	// STDLIB Lua (auto-cargada antes del script de usuario)
	// ─────────────────────────────────────────────────────────────────────────
	static inline function _stdlib0():String return '-- ── Sistema de clases via metatables ─────────────────────────────────────────
function Class(def)
    local cls = {}; cls.__index = cls
    if def.extends then setmetatable(cls, { __index = def.extends }) end
    for k, v in pairs(def) do if k ~= "extends" then cls[k] = v end end
    cls.new = function(...)
        local inst = setmetatable({}, cls)
        if inst.init then inst:init(...) end
        return inst
    end
    return cls
end

-- ── Colores predefinidos ──────────────────────────────────────────────────────
Color = {
    WHITE = colorHex("FFFFFFFF"), BLACK = colorHex("FF000000"),
    RED   = colorHex("FFFF0000"), GREEN = colorHex("FF00FF00"),
    BLUE  = colorHex("FF0000FF"), YELLOW= colorHex("FFFFFF00"),
    CYAN  = colorHex("FF00FFFF"), MAGENTA=colorHex("FFFF00FF"),
    ORANGE= colorHex("FFFF8800"), PINK  = colorHex("FFFF69B4"),
    PURPLE= colorHex("FF800080"), GRAY  = colorHex("FF888888"),
    TRANSPARENT = 0
}

-- ── Nombres de easing ─────────────────────────────────────────────────────────
Ease = {
    linear    = "linear",
    quadIn    = "quadIn",    quadOut    = "quadOut",    quadInOut    = "quadInOut",
    cubeIn    = "cubeIn",    cubeOut    = "cubeOut",    cubeInOut    = "cubeInOut",
    sineIn    = "sineIn",    sineOut    = "sineOut",    sineInOut    = "sineInOut",
    bounceIn  = "bounceIn",  bounceOut  = "bounceOut",
    elasticIn = "elasticIn", elasticOut = "elasticOut",
    backIn    = "backIn",    backOut    = "backOut"
}

';
	static inline function _stdlib1():String return '-- ── Layout helpers ────────────────────────────────────────────────────────────
function centerX(h) setProp(h,"x",(1280-getProp(h,"width"))/2) end
function centerY(h) setProp(h,"y",(720 -getProp(h,"height"))/2) end
function center(h)  centerX(h); centerY(h) end

-- ── Compatibilidad Psych ──────────────────────────────────────────────────────
makeLuaSprite  = makeSprite
addLuaSprite   = addSprite
removeLuaSprite= removeSprite
makeGraphic    = makeSprite
luaTrace       = trace

\' + \'-- ── Keys de dirección ─────────────────────────────────────────────────────────
Key = {
    LEFT  = "LEFT",  DOWN  = "DOWN",  UP     = "UP",    RIGHT = "RIGHT",
    ENTER = "ENTER", ESCAPE= "ESCAPE",SPACE  = "SPACE",
    A="A", B="B", C="C", D="D", E="E", F="F", G="G", H="H", I="I", J="J",
    K="K", L="L", M="M", N="N", O="O", P="P", Q="Q", R="R", S="S", T="T",
    U="U", V="V", W="W", X="X", Y="Y", Z="Z",
    ONE="ONE", TWO="TWO", THREE="THREE", FOUR="FOUR",
    F1="F1", F2="F2", F3="F3", F4="F4", F5="F5",
}

-- ── Atajos de cámara ──────────────────────────────────────────────────────────
camGame = "game"
camHUD  = "hud"
camUI   = "ui"

-- ── Atajos de personaje ───────────────────────────────────────────────────────
BF       = "bf"
DAD      = "dad"
GF       = "gf"
OPPONENT = "dad"
PLAYER   = "bf"

-- ── Math helpers ──────────────────────────────────────────────────────────────
function sign(n)    return n > 0 and 1 or (n < 0 and -1 or 0) end
';
	static inline function _stdlib2():String return 'function round(n)   return math.floor(n + 0.5) end
function map(v, mn, mx, tmn, tmx) return tmn + (v - mn) / (mx - mn) * (tmx - tmn) end

-- ── Tabla / Array helpers ─────────────────────────────────────────────────────
function tableContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function tableRemove(t, v) for i, x in ipairs(t) do if x == v then table.remove(t, i) return end end end
function tableMap(t, fn) local r={} for i,v in ipairs(t) do r[i]=fn(v) end return r end
function tableFilter(t, fn) local r={} for _,v in ipairs(t) do if fn(v) then r[#r+1]=v end end return r end

-- ── String helpers ────────────────────────────────────────────────────────────
function startsWith(s, prefix) return s:sub(1, #prefix) == prefix end
function endsWith(s, suffix)   return s:sub(-#suffix) == suffix end
function capitalize(s)         return s:sub(1,1):upper() .. s:sub(2):lower() end

-- ── Tweens: atajos ────────────────────────────────────────────────────────────
\' + \'function tweenX(spr, to, dur, ease)     return tweenProp(spr, "x", to, dur, ease or "linear") end
function tweenY(spr, to, dur, ease)     return tweenProp(spr, "y", to, dur, ease or "linear") end
function tweenXY(spr, tx, ty, dur, ease) return tweenPosition(spr, tx, ty, dur, ease or "linear") end
function fadeInSprite(spr, dur, ease)   return tweenAlpha(spr, 1, dur or 0.5, ease or "linear") end
';
	static inline function _stdlib3():String return 'function fadeOutSprite(spr, dur, ease)  return tweenAlpha(spr, 0, dur or 0.5, ease or "linear") end

-- ── Personajes: atajos ────────────────────────────────────────────────────────
function bfAnim(anim, force)   triggerAnim("bf",  anim, force or false) end
function dadAnim(anim, force)  triggerAnim("dad", anim, force or false) end
function gfAnim(anim, force)   triggerAnim("gf",  anim, force or false) end
function bfDance()   characterDance("bf")  end
function dadDance()  characterDance("dad") end
function gfDance()   characterDance("gf")  end

-- ── Cámara: atajos ────────────────────────────────────────────────────────────
function zoomCamera(z, dur, ease)  if dur then setCamZoomTween(z, dur, ease or "linear") else setCamZoom(z) end end
function flashCamera(col, dur)     cameraFlash(col or "WHITE", dur or 0.5) end
function shakeCamera(i, dur)       cameraShake(i or 0.03, dur or 0.2) end
function snapCameraTo(x, y)        cameraSnapTo(x, y) end

-- ── Notificaciones cortas ─────────────────────────────────────────────────────
function notify(msg, dur) showNotification(msg, dur or 2.5) end

-- ── Datos del mod (guardar/cargar) ─────────────────────────────────────────────
function saveData(key, value) dataSave(key, value) end
function loadData(key, default)
    local v = dataLoad(key)
    if v == nil then return default end
    return v
end

-- ── Sistema de estados ────────────────────────────────────────────────────────
';
	static inline function _stdlib4():String return '-- Máquina de estados liviana para lógica de cutscenes o jefes
StateMachine = Class {
    init = function(self, states)
\' + \'        self.states  = states or {}
        self.current = nil
    end,
    go = function(self, name, ...)
        if self.current and self.states[self.current] and self.states[self.current].exit then
            self.states[self.current]:exit()
        end
        self.current = name
        if self.states[name] and self.states[name].enter then
            self.states[name]:enter(...)
        end
    end,
    update = function(self, elapsed)
        if self.current and self.states[self.current] and self.states[self.current].update then
            self.states[self.current]:update(elapsed)
        end
    end
}

-- ── Sistema de diálogos: API fluida ──────────────────────────────────────────
-- Permite encadenar configuración como objeto:
--
--   Dialog.new()
--     :line("Boyfriend", "¡Hola!")
--     :line("Daddy Dearest", "...", Color.RED)
--     :typeSpeed(0.03)
--     :onFinish("miCallback")
--     :show()
--
Dialog = {}
Dialog.__index = Dialog

function Dialog.new()
    local self = setmetatable({}, Dialog)
    self._handle = newDialog()
    return self
end

function Dialog:line(speaker, text, color, autoAdvance)
    dialogAddLine(self._handle, speaker, text, color or 0, autoAdvance or 0)
    return self
end

function Dialog:portrait(key, path)
    dialogSetPortrait(self._handle, key, path)
    return self
end

function Dialog:typeSpeed(s)
';
	static inline function _stdlib5():String return '    dialogSetTypeSpeed(self._handle, s)
    return self
end

function Dialog:autoAdvance(s)
    dialogSetAutoAdvance(self._handle, s)
    return self
end

function Dialog:speakerColor(c)
    dialogSetSpeakerColor(self._handle, c)
    return self
end

function Dialog:bgColor(c)
    dialogSetBgColor(self._handle, c)
    return self
end

function Dialog:allowSkip(v)
    dialogSetAllowSkip(self._handle, v ~= false)
    return self
end

function Dialog:onFinish(fn)
    dialogOnFinish(self._handle, fn)
    return self
end

function Dialog:onLine(fn)
    dialogOnLine(self._handle, fn)
    return self
end

function Dialog:show()
\' + \'    dialogShow(self._handle)
    return self
end

function Dialog:close()
    dialogClose(self._handle)
    return self
end

function Dialog:skip()
    dialogSkipAll(self._handle)
    return self
end
BossBar = Class {
    init = function(self, label, color)
        self.bg  = makeText(0, 0, 1280, "", 18)
        self.bar = newObject("FlxSprite", 0, 0)
        self.txt = makeText(0, 0, 1280, label or "BOSS", 20)
        self.max = 100
        self.val = 100
        self.col = color or Color.RED

        callMethod(self.bar, "makeGraphic", 1280, 20, self.col)
        setProp(self.bg, "y", 695)
        setProp(self.bar, "y", 695)
        setProp(self.txt, "y", 692)
        setTextAlign(self.txt, "center")
        setTextBold(self.txt, true)
        setSpriteScrollFactor(self.bar, 0, 0)
        setProp(self.bg, "scrollFactor.x", 0)
';
	static inline function _stdlib6():String return '        setProp(self.bg, "scrollFactor.y", 0)
        setProp(self.txt, "scrollFactor.x", 0)
        setProp(self.txt, "scrollFactor.y", 0)
        addToState(self.bg)
        addToState(self.bar)
        addToState(self.txt)
    end,
    set = function(self, value)
        self.val = math.max(0, math.min(self.max, value))
        local ratio = self.val / self.max
        callMethod(self.bar, "setGraphicSize", math.floor(1280 * ratio), 20)
        callMethod(self.bar, "updateHitbox")
    end,
    damage = function(self, amount) self:set(self.val - amount) end,
    heal   = function(self, amount) self:set(self.val + amount) end,
    isDead = function(self) return self.val <= 0 end
}';
	static function _getSTDLIB():String return _stdlib0() + _stdlib1() + _stdlib2() + _stdlib3() + _stdlib4() + _stdlib5() + _stdlib6();



	// ─────────────────────────────────────────────────────────────────────────
	// FACTORIES por defecto
	// ─────────────────────────────────────────────────────────────────────────
	static function _defaultFactories():Map<String, Array<Dynamic>->Dynamic>
	{
		return [
			'FlxSprite'      => a -> new flixel.FlxSprite(
				a.length > 0 ? (a[0]:Float) : 0, a.length > 1 ? (a[1]:Float) : 0),
			'FlxText'        => a -> new flixel.text.FlxText(
				a.length > 0 ? (a[0]:Float) : 0, a.length > 1 ? (a[1]:Float) : 0,
				a.length > 2 ? Std.int(a[2]) : 0,
				a.length > 3 ? Std.string(a[3]) : '', a.length > 4 ? Std.int(a[4]) : 16),
			'FlxSpriteGroup' => _ -> new flixel.group.FlxSpriteGroup(),
			'FlxGroup'       => _ -> new flixel.group.FlxGroup(),
			'FlxCamera'      => a -> new flixel.FlxCamera(
				a.length > 0 ? Std.int(a[0]) : 0, a.length > 1 ? Std.int(a[1]) : 0,
				a.length > 2 ? Std.int(a[2]) : flixel.FlxG.width,
				a.length > 3 ? Std.int(a[3]) : flixel.FlxG.height),
			'FlxTimer'       => _ -> new flixel.util.FlxTimer(),
			'FunkinSprite'   => a -> new animationdata.FunkinSprite(
				a.length > 0 ? (a[0]:Float) : 0, a.length > 1 ? (a[1]:Float) : 0),
		];
	}

	// ─────────────────────────────────────────────────────────────────────────
	// IMPLEMENTACIONES
	// ─────────────────────────────────────────────────────────────────────────

	// ── Object Registry ───────────────────────────────────────────────────────

	static function _fnNew(l:Dynamic):Int
	{
		final cls  = Lua.tostring(l, 1);
		final nArg = Lua.gettop(l) - 1;
		final args = [for (i in 0...nArg) _read(l, i + 2)];
		Lua.settop(l, 0);
		final factory = _factories.get(cls);
		try
		{
			final obj = factory != null ? factory(args)
				: Type.createInstance(Type.resolveClass(cls) ?? Type.resolveClass('funkin.gameplay.$cls')
					?? Type.resolveClass('funkin.menus.$cls') ?? Type.resolveClass('funkin.states.$cls'), args);
			if (obj == null) { Lua.pushnil(l); return 1; }
			Lua.pushnumber(l, register(obj));
		}
		catch (e:Dynamic) { trace('[Lua] newObject($cls): $e'); Lua.pushnil(l); }
		return 1;
	}

	static function _fnGetProp(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final f = Lua.tostring(l, 2); Lua.settop(l, 0);
		_push(l, _resolvePath(f, resolve(h))); return 1;
	}

	static function _fnSetProp(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final f = Lua.tostring(l, 2); final v = _read(l, 3);
		Lua.settop(l, 0); _applyPath(f, v, resolve(h)); return 0;
	}

	static function _fnCall(l:Dynamic):Int
	{
		final h  = Std.int(Lua.tonumber(l, 1)); final m = Lua.tostring(l, 2);
		final na = Lua.gettop(l) - 2;
		final ar = [for (i in 0...na) _read(l, i + 3)]; Lua.settop(l, 0);
		final ob = resolve(h); if (ob == null) { Lua.pushnil(l); return 1; }
		try { _push(l, Reflect.callMethod(ob, Reflect.getProperty(ob, m), ar)); }
		catch (e:Dynamic) { trace('[Lua] callMethod($m): $e'); Lua.pushnil(l); }
		return 1;
	}

	static function _fnDestroy(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); Lua.settop(l, 0);
		final o = resolve(h); if (o != null) { try (o:Dynamic).destroy() catch(_) {}; release(h); }
		return 0;
	}

	// ── Escena ────────────────────────────────────────────────────────────────

	static function _fnAddState(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final front = Lua.gettop(l) > 1 && Lua.toboolean(l, 2);
		Lua.settop(l, 0); final o = resolve(h); if (o == null) return 0;
		if (front) flixel.FlxG.state.add(o) else flixel.FlxG.state.insert(0, o);
		return 0;
	}
	static function _fnRemState(l:Dynamic):Int
	{
		final o = resolve(Std.int(Lua.tonumber(l, 1))); Lua.settop(l, 0);
		if (o != null) flixel.FlxG.state.remove(o, true); return 0;
	}
	static function _fnAddGroup(l:Dynamic):Int
	{
		final g = resolve(Std.int(Lua.tonumber(l, 1))); final o = resolve(Std.int(Lua.tonumber(l, 2)));
		Lua.settop(l, 0); if (g != null && o != null) try (g:Dynamic).add(o) catch(_) {};
		return 0;
	}
	static function _fnRemGroup(l:Dynamic):Int
	{
		final g = resolve(Std.int(Lua.tonumber(l, 1))); final o = resolve(Std.int(Lua.tonumber(l, 2)));
		Lua.settop(l, 0); if (g != null && o != null) try (g:Dynamic).remove(o, true) catch(_) {};
		return 0;
	}
	static function _fnSwitch(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1); Lua.settop(l, 0);
		final cls  = Type.resolveClass(name) ?? Type.resolveClass('funkin.menus.$name')
			?? Type.resolveClass('funkin.states.$name') ?? Type.resolveClass('funkin.gameplay.$name');
		if (cls == null) { trace('[Lua] switchState: no encontrado — $name'); return 0; }
		flixel.FlxG.switchState(Type.createInstance(cls, []));
		return 0;
	}

	// ── Propiedades path ──────────────────────────────────────────────────────

	static function _fnGetPath(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1); Lua.settop(l, 0);
		_push(l, _resolvePath(p, _ps())); return 1;
	}
	static function _fnSetPath(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1); final v = _read(l, 2); Lua.settop(l, 0);
		_applyPath(p, v, _ps()); return 0;
	}
	static function _fnGetOf(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final p = Lua.tostring(l, 2); Lua.settop(l, 0);
		_push(l, _resolvePath(p, resolve(h))); return 1;
	}
	static function _fnSetOf(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final p = Lua.tostring(l, 2); final v = _read(l, 3);
		Lua.settop(l, 0); _applyPath(p, v, resolve(h)); return 0;
	}

	// ── Personajes ────────────────────────────────────────────────────────────

	static function _fnTriggerAnim(l:Dynamic):Int
	{
		final w = Lua.tostring(l, 1); final a = Lua.tostring(l, 2);
		final f = Lua.gettop(l) > 2 && Lua.toboolean(l, 3); Lua.settop(l, 0);
		final c = _char(w); if (c != null) c.playAnim(a, f); return 0;
	}
	static function _fnDance(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1)); Lua.settop(l, 0);
		if (c != null) try c.dance() catch(_) c.playAnim('idle', false); return 0;
	}
	static function _fnCharHandle(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1)); Lua.settop(l, 0);
		if (c == null) { Lua.pushnil(l); return 1; }
		Lua.pushnumber(l, register(c)); return 1;
	}

	// ── Health Icons ──────────────────────────────────────────────────────────

	static function _fnSetHIcon(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1); final key = Lua.tostring(l, 2); Lua.settop(l, 0);
		final ps = _ps(); if (ps == null) return 0;
		try { final ic = who == 'player' ? ps.healthIconP1 : ps.healthIconP2;
		      if (ic != null) ic.loadHealthIcon(key); } catch(e:Dynamic) trace('[Lua] setHealthIcon: $e');
		return 0;
	}
	static function _fnSetHIconScale(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1); final sc = Lua.tonumber(l, 2); Lua.settop(l, 0);
		final ps = _ps(); if (ps == null) return 0;
		try { final ic = who == 'player' ? ps.healthIconP1 : ps.healthIconP2;
		      if (ic != null) ic.setGraphicSize(Std.int(ic.width * sc)); } catch(_) {};
		return 0;
	}
	static function _fnSetHIconOffset(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1); final dx = Lua.tonumber(l, 2); final dy = Lua.tonumber(l, 3);
		Lua.settop(l, 0); final ps = _ps(); if (ps == null) return 0;
		try { final ic = who == 'player' ? ps.healthIconP1 : ps.healthIconP2;
		      if (ic != null) { ic.offset.x = dx; ic.offset.y = dy; } } catch(_) {};
		return 0;
	}
	static function _fnGetHIconHandle(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1); Lua.settop(l, 0); final ps = _ps();
		if (ps == null) { Lua.pushnil(l); return 1; }
		final ic = try who == 'player' ? ps.healthIconP1 : ps.healthIconP2 catch(_) null;
		if (ic == null) { Lua.pushnil(l); return 1; }
		Lua.pushnumber(l, register(ic)); return 1;
	}

	// ── Strumlines ────────────────────────────────────────────────────────────

	static inline function _strum(idx:Int):Dynamic
	{
		final ps = _ps(); if (ps == null) return null;
		return try idx == 0 ? ps.playerStrumline : ps.opponentStrumline catch(_) null;
	}
	static function _fnStrumAlpha(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1))); final a = Lua.tonumber(l, 2); Lua.settop(l, 0);
		if (s != null) s.alpha = a; return 0;
	}
	static function _fnStrumScale(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1))); final sc = Lua.tonumber(l, 2); Lua.settop(l, 0);
		if (s != null) { s.scale.x = sc; s.scale.y = sc; } return 0;
	}
	static function _fnStrumPos(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1)));
		final x = Lua.tonumber(l, 2); final y = Lua.tonumber(l, 3); Lua.settop(l, 0);
		if (s != null) { s.x = x; s.y = y; } return 0;
	}
	static function _fnStrumHide(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1))); final h = Lua.toboolean(l, 2); Lua.settop(l, 0);
		if (s != null) s.visible = !h; return 0;
	}
	static function _fnStrumHandle(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1))); Lua.settop(l, 0);
		if (s == null) { Lua.pushnil(l); return 1; }
		Lua.pushnumber(l, register(s)); return 1;
	}

	// ── Sprites ───────────────────────────────────────────────────────────────

	static function _spr(l:State, idx:Int = 1):Dynamic
	{
		return Lua.type(l, idx) == 3
			? resolve(Std.int(Lua.tonumber(l, idx)))
			: resolve(_tags.get(Lua.tostring(l, idx)) ?? -1);
	}

	static function _fnMakeSprite(l:Dynamic):Int
	{
		final tag = Lua.tostring(l, 1);
		final x = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.0;
		final y = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0; Lua.settop(l, 0);
		final h = register(new flixel.FlxSprite(x, y)); _tags.set(tag, h);
		Lua.pushnumber(l, h); return 1;
	}
	static function _fnMakeFunkin(l:Dynamic):Int
	{
		final tag = Lua.tostring(l, 1);
		final x = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.0;
		final y = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0; Lua.settop(l, 0);
		final h = register(new animationdata.FunkinSprite(x, y)); _tags.set(tag, h);
		Lua.pushnumber(l, h); return 1;
	}
	static function _fnLoadImg(l:Dynamic):Int
	{
		final s = _spr(l); final k = Lua.tostring(l, 2); Lua.settop(l, 0);
		if (s != null) try s.loadGraphic(flixel.FlxG.bitmap.add(k)) catch(e:Dynamic) trace('[Lua] loadImage: $e');
		return 0;
	}
	static function _fnLoadSparrow(l:Dynamic):Int
	{
		final s = _spr(l); final k = Lua.tostring(l, 2); Lua.settop(l, 0);
		if (s != null) try s.loadSparrow(k) catch(e:Dynamic) trace('[Lua] loadSparrow: $e');
		return 0;
	}
	static function _fnLoadAtlas(l:Dynamic):Int
	{
		final s = _spr(l); final k = Lua.tostring(l, 2); Lua.settop(l, 0);
		if (s != null) try s.loadAtlas(k) catch(e:Dynamic) trace('[Lua] loadAtlas: $e');
		return 0;
	}
	static function _fnAddAnim(l:Dynamic):Int
	{
		final s = _spr(l); final n = Lua.tostring(l, 2); final p = Lua.tostring(l, 3);
		final f = Lua.gettop(l) > 3 ? Std.int(Lua.tonumber(l, 4)) : 24;
		final lo = Lua.gettop(l) > 4 && Lua.toboolean(l, 5); Lua.settop(l, 0);
		if (s != null) try s.animation.addByPrefix(n, p, f, lo) catch(e:Dynamic) trace('[Lua] addAnim: $e');
		return 0;
	}
	static function _fnAddAnimOff(l:Dynamic):Int
	{
		final s = _spr(l); final n = Lua.tostring(l, 2);
		final dx = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0;
		final dy = Lua.gettop(l) > 3 ? Lua.tonumber(l, 4) : 0.0; Lua.settop(l, 0);
		if (s != null) try Reflect.callMethod(s, Reflect.field(s, 'addOffset'), [n, dx, dy]) catch(_) {};
		return 0;
	}
	static function _fnPlayAnim(l:Dynamic):Int
	{
		final s = _spr(l); final n = Lua.tostring(l, 2); final f = Lua.gettop(l) > 2 && Lua.toboolean(l, 3);
		Lua.settop(l, 0); if (s != null) try s.animation.play(n, f) catch(_) {};
		return 0;
	}
	static function _fnStopAnim(l:Dynamic):Int
	{
		final s = _spr(l); Lua.settop(l, 0); if (s != null) try s.animation.stop() catch(_) {};
		return 0;
	}
	static function _fnAddSpr(l:Dynamic):Int
	{
		final s = _spr(l); final front = Lua.gettop(l) > 1 && Lua.toboolean(l, 2); Lua.settop(l, 0);
		if (s == null) return 0;
		if (front) flixel.FlxG.state.add(s) else flixel.FlxG.state.insert(0, s);
		return 0;
	}
	static function _fnRemSpr(l:Dynamic):Int
	{
		final s = _spr(l); Lua.settop(l, 0);
		if (s != null) { flixel.FlxG.state.remove(s, true); s.destroy(); }
		return 0;
	}
	static function _fnSprScale(l:Dynamic):Int
	{
		final s = _spr(l); final sx = Lua.tonumber(l, 2); final sy = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : sx;
		Lua.settop(l, 0); if (s != null) { s.scale.x = sx; s.scale.y = sy; s.updateHitbox(); }
		return 0;
	}
	static function _fnSprFlip(l:Dynamic):Int
	{
		final s = _spr(l); final fx = Lua.toboolean(l, 2); final fy = Lua.gettop(l) > 2 && Lua.toboolean(l, 3);
		Lua.settop(l, 0); if (s != null) { s.flipX = fx; s.flipY = fy; }
		return 0;
	}
	static function _fnSprAlpha(l:Dynamic):Int
	{
		final s = _spr(l); final a = Lua.tonumber(l, 2); Lua.settop(l, 0);
		if (s != null) s.alpha = a; return 0;
	}
	static function _fnSprColor(l:Dynamic):Int
	{
		final s = _spr(l); final c = Std.int(Lua.tonumber(l, 2)); Lua.settop(l, 0);
		if (s != null) s.color = c; return 0;
	}
	static function _fnSprPos(l:Dynamic):Int
	{
		final s = _spr(l); final x = Lua.tonumber(l, 2); final y = Lua.tonumber(l, 3); Lua.settop(l, 0);
		if (s != null) { s.x = x; s.y = y; } return 0;
	}
	static function _fnSprScroll(l:Dynamic):Int
	{
		final s = _spr(l); final sx = Lua.tonumber(l, 2); final sy = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : sx;
		Lua.settop(l, 0); if (s != null) s.scrollFactor.set(sx, sy); return 0;
	}
	static function _fnSprAA(l:Dynamic):Int
	{
		final s = _spr(l); final v = Lua.toboolean(l, 2); Lua.settop(l, 0);
		if (s != null) s.antialiasing = v; return 0;
	}
	static function _fnSprCenter(l:Dynamic):Int
	{
		final s = _spr(l); Lua.settop(l, 0); if (s != null) try s.screenCenter() catch(_) {};
		return 0;
	}

	// ── Texto ─────────────────────────────────────────────────────────────────

	static function _fnMakeText(l:Dynamic):Int
	{
		final x = Lua.tonumber(l, 1); final y = Lua.tonumber(l, 2);
		final w = Lua.gettop(l) > 2 ? Std.int(Lua.tonumber(l, 3)) : 0;
		final t = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : '';
		final s = Lua.gettop(l) > 4 ? Std.int(Lua.tonumber(l, 5)) : 16; Lua.settop(l, 0);
		Lua.pushnumber(l, register(new flixel.text.FlxText(x, y, w, t, s))); return 1;
	}
	static function _fnSetText(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final t = Lua.tostring(l, 2); Lua.settop(l, 0);
		try resolve(h).text = t catch(_) {}; return 0;
	}
	static function _fnTextSize(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final s = Std.int(Lua.tonumber(l, 2)); Lua.settop(l, 0);
		try resolve(h).size = s catch(_) {}; return 0;
	}
	static function _fnTextFont(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final f = Lua.tostring(l, 2); Lua.settop(l, 0);
		try resolve(h).font = f catch(_) {}; return 0;
	}
	static function _fnTextBold(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final v = Lua.toboolean(l, 2); Lua.settop(l, 0);
		try resolve(h).bold = v catch(_) {}; return 0;
	}
	static function _fnTextAlign(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final a = Lua.tostring(l, 2); Lua.settop(l, 0);
		try resolve(h).alignment = a catch(_) {}; return 0;
	}
	static function _fnTextBorder(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final sz = Lua.tonumber(l, 2); final c = Std.int(Lua.tonumber(l, 3));
		Lua.settop(l, 0);
		try resolve(h).setBorderStyle(flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, c, sz) catch(_) {};
		return 0;
	}
	static function _fnTextColor(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final c = Std.int(Lua.tonumber(l, 2)); Lua.settop(l, 0);
		try resolve(h).color = c catch(_) {}; return 0;
	}

	// ── Cámara ────────────────────────────────────────────────────────────────

	static function _cam(l:State, idx:Int):flixel.FlxCamera
	{
		if (Lua.gettop(l) >= idx)
		{
			if (Lua.type(l, idx) == 4)
			{
				final ps = _ps();
				return switch Lua.tostring(l, idx) {
					case 'hud': try ps?.camHUD ?? flixel.FlxG.camera catch(_) flixel.FlxG.camera;
					case 'ui':  try ps?.camUI  ?? flixel.FlxG.camera catch(_) flixel.FlxG.camera;
					default:    flixel.FlxG.camera;
				};
			}
			if (Lua.type(l, idx) == 3)
			{
				final o = resolve(Std.int(Lua.tonumber(l, idx)));
				if (Std.isOfType(o, flixel.FlxCamera)) return o;
			}
		}
		return flixel.FlxG.camera;
	}
	static function _fnCamZoom(l:Dynamic):Int
	{
		final z = Lua.tonumber(l, 1); final c = _cam(l, 2); Lua.settop(l, 0); c.zoom = z; return 0;
	}
	static function _fnCamZoomTween(l:Dynamic):Int
	{
		final z = Lua.tonumber(l, 1); final d = Lua.tonumber(l, 2);
		final e = Lua.gettop(l) > 2 && Lua.type(l, 3) == 4 ? Lua.tostring(l, 3) : 'linear';
		final c = _cam(l, 4); Lua.settop(l, 0);
		flixel.tweens.FlxTween.tween(c, {zoom: z}, d, {ease: _ease(e)}); return 0;
	}
	static function _fnCamFlash(l:Dynamic):Int
	{
		final col = Lua.gettop(l) > 0 && Lua.type(l, 1) == 4 ? Lua.tostring(l, 1) : 'WHITE';
		final dur = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.5; final c = _cam(l, 3); Lua.settop(l, 0);
		c.flash(flixel.util.FlxColor.fromString(col), dur); return 0;
	}
	static function _fnCamShake(l:Dynamic):Int
	{
		final i = Lua.gettop(l) > 0 ? Lua.tonumber(l, 1) : 0.03;
		final d = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.2; final c = _cam(l, 3); Lua.settop(l, 0);
		c.shake(i, d); return 0;
	}
	static function _fnCamFade(l:Dynamic):Int
	{
		final col = Lua.gettop(l) > 0 && Lua.type(l, 1) == 4 ? Lua.tostring(l, 1) : 'BLACK';
		final dur = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.5;
		final fi  = Lua.gettop(l) > 2 && Lua.toboolean(l, 3); final c = _cam(l, 4); Lua.settop(l, 0);
		c.fade(flixel.util.FlxColor.fromString(col), dur, fi); return 0;
	}
	static function _fnCamPan(l:Dynamic):Int
	{
		final x = Lua.tonumber(l, 1); final y = Lua.tonumber(l, 2); final d = Lua.tonumber(l, 3);
		final e = Lua.gettop(l) > 3 && Lua.type(l, 4) == 4 ? Lua.tostring(l, 4) : 'linear';
		final c = _cam(l, 5); Lua.settop(l, 0);
		flixel.tweens.FlxTween.tween(c, {scrollX: x, scrollY: y}, d, {ease: _ease(e)}); return 0;
	}
	static function _fnCamSnap(l:Dynamic):Int
	{
		final x = Lua.tonumber(l, 1); final y = Lua.tonumber(l, 2); final c = _cam(l, 3); Lua.settop(l, 0);
		c.scroll.set(x, y); return 0;
	}
	static function _fnCamHandle(l:Dynamic):Int
	{
		final c = _cam(l, 1); Lua.settop(l, 0); Lua.pushnumber(l, register(c)); return 1;
	}
	static function _fnMakeCam(l:Dynamic):Int
	{
		final tag = Lua.tostring(l, 1); Lua.settop(l, 0);
		final c = new flixel.FlxCamera(); c.bgColor = flixel.util.FlxColor.TRANSPARENT;
		flixel.FlxG.cameras.add(c, false);
		final h = register(c); _tags.set(tag, h); Lua.pushnumber(l, h); return 1;
	}

	// ── Tweens ────────────────────────────────────────────────────────────────

	static function _fnTweenProp(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final prop = Lua.tostring(l, 2);
		final to = Lua.tonumber(l, 3); final dur = Lua.tonumber(l, 4);
		final e  = Lua.gettop(l) > 4 ? Lua.tostring(l, 5) : 'linear'; Lua.settop(l, 0);
		final obj = resolve(h); if (obj == null) { Lua.pushnil(l); return 1; }
		final props:Dynamic = {}; Reflect.setField(props, prop, to);
		final tw = flixel.tweens.FlxTween.tween(obj, props, dur, {ease: _ease(e)});
		Lua.pushnumber(l, register(tw)); return 1;
	}
	static function _fnTweenColor(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final dur = Lua.tonumber(l, 2);
		final fr = Std.int(Lua.tonumber(l, 3)); final to = Std.int(Lua.tonumber(l, 4));
		final e  = Lua.gettop(l) > 4 ? Lua.tostring(l, 5) : 'linear'; Lua.settop(l, 0);
		final obj = resolve(h); if (obj == null) { Lua.pushnil(l); return 1; }
		final tw = flixel.tweens.FlxTween.color(obj, dur, fr, to, {ease: _ease(e)});
		Lua.pushnumber(l, register(tw)); return 1;
	}
	static function _fnTweenCancel(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); Lua.settop(l, 0);
		final tw = resolve(h); if (tw != null) try tw.cancel() catch(_) {}; release(h); return 0;
	}

	// ── Timers ────────────────────────────────────────────────────────────────
	// Los timers con callback Lua se resuelven pasando el nombre de función global.

	static function _fnTimer(l:Dynamic):Int
	{
		final dur   = Lua.tonumber(l, 1);
		final fn    = Lua.gettop(l) > 1 ? Lua.tostring(l, 2) : null;
		final loops = Lua.gettop(l) > 2 ? Std.int(Lua.tonumber(l, 3)) : 1; Lua.settop(l, 0);
		final tm    = new flixel.util.FlxTimer();
		final h     = register(tm);
		if (fn != null)
		{
			// Capturar la instancia de script activa en el momento de crear el timer
			// consultando _timerScripts por el selfHandle almacenado en __scriptHandle
			Lua.getglobal(_sCurrentLua, '__scriptHandle');
			final selfH = _sCurrentLua != null ? Std.int(Lua.tonumber(_sCurrentLua, -1)) : -1;
			if (_sCurrentLua != null) Lua.pop(_sCurrentLua, 1);
			final script = selfH >= 0 ? _timerScripts.get(selfH) : null;
			_timerScripts.set(h, script);
			final fnName = fn;
			tm.start(dur, function(_:flixel.util.FlxTimer) {
				final sc = _timerScripts.get(h);
				if (sc != null && sc.active) sc.call(fnName);
			}, loops);
		}
		else
		{
			tm.start(dur, null, loops);
		}
		Lua.pushnumber(l, h); return 1;
	}
	static function _fnTimerCancel(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); Lua.settop(l, 0);
		final tm = resolve(h); if (tm != null) try tm.cancel() catch(_) {}; release(h); return 0;
	}

	// ── Cutscenes ─────────────────────────────────────────────────────────────

	static function _fnCutNew(l:Dynamic):Int
	{
		Lua.pushnumber(l, register(new funkin.cutscenes.CutsceneBuilder())); return 1;
	}
	static function _fnCutSkip(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final v = Lua.toboolean(l, 2); Lua.settop(l, 0);
		if (b != null) b.skippable(v); return 0;
	}
	static function _fnCutRect(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final id = Lua.tostring(l, 2);
		final c = Lua.gettop(l) > 2 ? Lua.tostring(l, 3) : 'BLACK'; Lua.settop(l, 0);
		if (b != null) b.defineRect(id, c); return 0;
	}
	static function _fnCutSpr(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final id = Lua.tostring(l, 2);
		final d = Lua.tostring(l, 3); Lua.settop(l, 0);
		if (b != null) try b.defineSprite(id, haxe.Json.parse(d)) catch(_) {};
		return 0;
	}
	static function _fnCutAdd(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final id = Lua.tostring(l, 2);
		Lua.settop(l, 0); if (b != null) b.add(id); return 0;
	}
	static function _fnCutRem(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final id = Lua.tostring(l, 2);
		Lua.settop(l, 0); if (b != null) b.remove(id); return 0;
	}
	static function _fnCutWait(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final t = Lua.tonumber(l, 2);
		Lua.settop(l, 0); if (b != null) b.wait(t); return 0;
	}
	static function _fnCutAnim(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1)));
		final w = Lua.tostring(l, 2); final a = Lua.tostring(l, 3); Lua.settop(l, 0);
		if (b != null) b.stageAnim(w, a); return 0;
	}
	static function _fnCutSound(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); final k = Lua.tostring(l, 2);
		Lua.settop(l, 0); if (b != null) b.playSound(k); return 0;
	}
	static function _fnCutCamZ(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1)));
		final z = Lua.tonumber(l, 2); final d = Lua.tonumber(l, 3); Lua.settop(l, 0);
		if (b != null) b.cameraZoom(z, d); return 0;
	}
	static function _fnCutCamF(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1)));
		final c = Lua.gettop(l) > 1 ? Lua.tostring(l, 2) : 'WHITE';
		final d = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.5; Lua.settop(l, 0);
		if (b != null) b.cameraFlash(c, d); return 0;
	}
	static function _fnCutPlay(l:Dynamic):Int
	{
		final b = resolve(Std.int(Lua.tonumber(l, 1))); Lua.settop(l, 0);
		if (b != null) b.play(); return 0;
	}

	// ── Gameplay ──────────────────────────────────────────────────────────────

	static function _fnAddScore(l:Dynamic):Int  { final p=_ps(); if(p!=null)p.score+=Std.int(Lua.tonumber(l,1)); Lua.settop(l,0); return 0; }
	static function _fnSetScore(l:Dynamic):Int  { final p=_ps(); if(p!=null)p.score=Std.int(Lua.tonumber(l,1)); Lua.settop(l,0); return 0; }
	static function _fnGetScore(l:Dynamic):Int  { final p=_ps(); Lua.pushnumber(l,p!=null?p.score:0); return 1; }
	static function _fnAddHealth(l:Dynamic):Int { final p=_ps(); if(p!=null)p.health=Math.min(2,p.health+Lua.tonumber(l,1)); Lua.settop(l,0); return 0; }
	static function _fnSetHealth(l:Dynamic):Int { final p=_ps(); if(p!=null)p.health=Math.max(0,Math.min(2,Lua.tonumber(l,1))); Lua.settop(l,0); return 0; }
	static function _fnGetHealth(l:Dynamic):Int { final p=_ps(); Lua.pushnumber(l,p!=null?p.health:1.0); return 1; }
	static function _fnSetMisses(l:Dynamic):Int { final p=_ps(); if(p!=null)try p.misses=Std.int(Lua.tonumber(l,1)) catch(_){}; Lua.settop(l,0); return 0; }
	static function _fnGetMisses(l:Dynamic):Int { final p=_ps(); Lua.pushnumber(l,p!=null?try p.misses catch(_) 0:0); return 1; }
	static function _fnSetCombo(l:Dynamic):Int  { final p=_ps(); if(p!=null)try p.combo=Std.int(Lua.tonumber(l,1)) catch(_){}; Lua.settop(l,0); return 0; }
	static function _fnGetCombo(l:Dynamic):Int  { final p=_ps(); Lua.pushnumber(l,p!=null?try p.combo catch(_) 0:0); return 1; }
	static function _fnEndSong(l:Dynamic):Int   { final p=_ps(); if(p!=null)p.endSong(); return 0; }
	static function _fnGameOver(l:Dynamic):Int  { final p=_ps(); if(p!=null)p.health=0; return 0; }
	static function _fnPause(l:Dynamic):Int     { final p=_ps(); if(p!=null)try p.pauseSong() catch(_) flixel.FlxG.timeScale=0; return 0; }
	static function _fnResume(l:Dynamic):Int    { final p=_ps(); if(p!=null)try p.resumeSong() catch(_) flixel.FlxG.timeScale=1; return 0; }

	// ── Notas ─────────────────────────────────────────────────────────────────

	static function _fnSpawnNote(l:Dynamic):Int
	{
		final p=_ps(); final t=Lua.tonumber(l,1); final d=Std.int(Lua.tonumber(l,2));
		final len=Lua.gettop(l)>2?Lua.tonumber(l,3):0.0; final tp=Lua.gettop(l)>3?Lua.tostring(l,4):'normal';
		Lua.settop(l,0);
		if(p!=null)try { final n=Reflect.callMethod(p,Reflect.field(p,'spawnNote'),[t,d,len,tp]); if(n!=null){Lua.pushnumber(l,register(n));return 1;} } catch(_){};
		Lua.pushnil(l); return 1;
	}
	static function _fnNoteDir(l:Dynamic):Int { final n=resolve(Std.int(Lua.tonumber(l,1))); Lua.settop(l,0); Lua.pushnumber(l,n!=null?try n.noteDir catch(_) -1:-1); return 1; }
	static function _fnNoteTime(l:Dynamic):Int{ final n=resolve(Std.int(Lua.tonumber(l,1))); Lua.settop(l,0); Lua.pushnumber(l,n!=null?try n.noteData catch(_) 0.0:0.0); return 1; }

	// ── Audio ─────────────────────────────────────────────────────────────────

	static function _fnPlayMusic(l:Dynamic):Int { final k=Lua.tostring(l,1);final v=Lua.gettop(l)>1?Lua.tonumber(l,2):1.0;Lua.settop(l,0);flixel.FlxG.sound.playMusic(k,v); return 0; }
	static function _fnStopMusic(l:Dynamic):Int  { flixel.FlxG.sound.music?.stop(); return 0; }
	static function _fnPauseMusic(l:Dynamic):Int { flixel.FlxG.sound.music?.pause(); return 0; }
	static function _fnResumeMusic(l:Dynamic):Int{ flixel.FlxG.sound.music?.resume(); return 0; }
	static function _fnPlaySound(l:Dynamic):Int  { final k=Lua.tostring(l,1);final v=Lua.gettop(l)>1?Lua.tonumber(l,2):1.0;Lua.settop(l,0);flixel.FlxG.sound.play(k,v); return 0; }
	static function _fnMusicPos(l:Dynamic):Int   { final m=flixel.FlxG.sound.music; Lua.pushnumber(l,m!=null?m.time:0.0); return 1; }
	static function _fnSetMusicPos(l:Dynamic):Int{ final t=Lua.tonumber(l,1);Lua.settop(l,0);final m=flixel.FlxG.sound.music;if(m!=null)m.time=t; return 0; }
	static function _fnMusicPitch(l:Dynamic):Int { final p=Lua.tonumber(l,1);Lua.settop(l,0);final m=flixel.FlxG.sound.music;if(m!=null)try m.pitch=p catch(_){}; return 0; }

	// ── GlobalConfig ──────────────────────────────────────────────────────────

	static function _fnSetConfig(l:Dynamic):Int { final k=Lua.tostring(l,1);final v=_read(l,2);Lua.settop(l,0);funkin.data.GlobalConfig.set(k,v); return 0; }
	static function _fnGetConfig(l:Dynamic):Int { final k=Lua.tostring(l,1);Lua.settop(l,0);_push(l,Reflect.getProperty(funkin.data.GlobalConfig.instance,k)); return 1; }

	// ── Input ─────────────────────────────────────────────────────────────────

	static function _fnKeyP(l:Dynamic):Int  { final k=_key(Lua.tostring(l,1));Lua.settop(l,0);Lua.pushboolean(l,k!=null&&flixel.FlxG.keys.anyPressed([k])); return 1; }
	static function _fnKeyJP(l:Dynamic):Int { final k=_key(Lua.tostring(l,1));Lua.settop(l,0);Lua.pushboolean(l,k!=null&&flixel.FlxG.keys.anyJustPressed([k])); return 1; }
	static function _fnKeyJR(l:Dynamic):Int { final k=_key(Lua.tostring(l,1));Lua.settop(l,0);Lua.pushboolean(l,k!=null&&flixel.FlxG.keys.anyJustReleased([k])); return 1; }
	static function _fnMouseX(l:Dynamic):Int  { Lua.pushnumber(l,flixel.FlxG.mouse.x); return 1; }
	static function _fnMouseY(l:Dynamic):Int  { Lua.pushnumber(l,flixel.FlxG.mouse.y); return 1; }
	static function _fnMouseP(l:Dynamic):Int  { Lua.pushboolean(l,flixel.FlxG.mouse.pressed); return 1; }
	static function _fnMouseJP(l:Dynamic):Int { Lua.pushboolean(l,flixel.FlxG.mouse.justPressed); return 1; }

	// ── Utils ─────────────────────────────────────────────────────────────────

	static function _fnTrace(l:Dynamic):Int
	{
		final parts=[for(i in 1...Lua.gettop(l)+1) Lua.tostring(l,i)]; Lua.settop(l,0);
		trace('[Lua] ${parts.join(" ")}'); return 0;
	}
	static function _fnBeat(l:Dynamic):Int    { final ps=_ps(); Lua.pushnumber(l, ps != null ? ps.curBeat : 0); return 1; }
	static function _fnStep(l:Dynamic):Int    { final ps=_ps(); Lua.pushnumber(l, ps != null ? ps.curStep : 0); return 1; }
	static function _fnBPM(l:Dynamic):Int     { Lua.pushnumber(l,funkin.data.Conductor.bpm); return 1; }
	static function _fnSongPos(l:Dynamic):Int { final m=flixel.FlxG.sound.music; Lua.pushnumber(l,m!=null?m.time:0.0); return 1; }
	static function _fnRndInt(l:Dynamic):Int  { final mn=Std.int(Lua.tonumber(l,1));final mx=Std.int(Lua.tonumber(l,2));Lua.settop(l,0);Lua.pushnumber(l,flixel.FlxG.random.int(mn,mx)); return 1; }
	static function _fnRndFlt(l:Dynamic):Int  { final mn=Lua.tonumber(l,1);final mx=Lua.tonumber(l,2);Lua.settop(l,0);Lua.pushnumber(l,flixel.FlxG.random.float(mn,mx)); return 1; }
	static function _fnRGB(l:Dynamic):Int     { final r=Std.int(Lua.tonumber(l,1));final g=Std.int(Lua.tonumber(l,2));final b=Std.int(Lua.tonumber(l,3));Lua.settop(l,0);Lua.pushnumber(l,flixel.util.FlxColor.fromRGB(r,g,b)); return 1; }
	static function _fnRGBA(l:Dynamic):Int    { final r=Std.int(Lua.tonumber(l,1));final g=Std.int(Lua.tonumber(l,2));final b=Std.int(Lua.tonumber(l,3));final a=Std.int(Lua.tonumber(l,4));Lua.settop(l,0);Lua.pushnumber(l,flixel.util.FlxColor.fromRGBFloat(r/255,g/255,b/255,a/255)); return 1; }
	static function _fnHex(l:Dynamic):Int     { final h=Lua.tostring(l,1);Lua.settop(l,0);Lua.pushnumber(l,flixel.util.FlxColor.fromString('#$h')); return 1; }
	static function _fnLerp(l:Dynamic):Int    { final a=Lua.tonumber(l,1);final b=Lua.tonumber(l,2);final t=Lua.tonumber(l,3);Lua.settop(l,0);Lua.pushnumber(l,a+(b-a)*t); return 1; }
	static function _fnClamp(l:Dynamic):Int   { final v=Lua.tonumber(l,1);final mn=Lua.tonumber(l,2);final mx=Lua.tonumber(l,3);Lua.settop(l,0);Lua.pushnumber(l,Math.max(mn,Math.min(mx,v))); return 1; }
	static function _fnFileEx(l:Dynamic):Int  { final p=Lua.tostring(l,1);Lua.settop(l,0);#if sys Lua.pushboolean(l,sys.FileSystem.exists(p)); #else Lua.pushboolean(l,false); #end return 1; }
	static function _fnFileR(l:Dynamic):Int   { final p=Lua.tostring(l,1);Lua.settop(l,0);#if sys try{Lua.pushstring(l,sys.io.File.getContent(p));}catch(_){Lua.pushnil(l);}#else Lua.pushnil(l);#end return 1; }
	static function _fnFileW(l:Dynamic):Int   { final p=Lua.tostring(l,1);final c=Lua.tostring(l,2);Lua.settop(l,0);#if sys try sys.io.File.saveContent(p,c) catch(_){};#end return 0; }


	// ── Datos compartidos ─────────────────────────────────────────────────────

	static function _fnSetShared(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1); final v=_read(l,2); Lua.settop(l,0);
		funkin.scripting.StateScriptHandler.setShared(k, v); return 0;
	}
	static function _fnGetShared(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1); final def=Lua.gettop(l)>1?_read(l,2):null; Lua.settop(l,0);
		_push(l, funkin.scripting.StateScriptHandler.getShared(k, def)); return 1;
	}
	static function _fnDelShared(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1); Lua.settop(l,0);
		funkin.scripting.StateScriptHandler.deleteShared(k); return 0;
	}

	// ── Comunicación con otros scripts ────────────────────────────────────────

	static function _fnBroadcast(l:Dynamic):Int
	{
		final ev=Lua.tostring(l,1);
		final n=Lua.gettop(l)-1;
		final args:Array<Dynamic>=[for(i in 0...n) _read(l,i+2)]; Lua.settop(l,0);
		funkin.scripting.StateScriptHandler.broadcast(ev, args);
		funkin.scripting.ScriptHandler.callOnScripts(ev, args); return 0;
	}
	static function _fnCallScripts(l:Dynamic):Int
	{
		final fn=Lua.tostring(l,1);
		final n=Lua.gettop(l)-1;
		final args:Array<Dynamic>=[for(i in 0...n) _read(l,i+2)]; Lua.settop(l,0);
		funkin.scripting.ScriptHandler.callOnScripts(fn, args); Lua.pushnil(l); return 1;
	}
	static function _fnSetScriptVar(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1); final v=_read(l,2); Lua.settop(l,0);
		funkin.scripting.ScriptHandler.setOnScripts(k, v); return 0;
	}
	static function _fnGetScriptVar(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1); Lua.settop(l,0);
		_push(l, funkin.scripting.ScriptHandler.getFromScripts(k)); return 1;
	}

	// ── Personajes: control extendido ─────────────────────────────────────────

	static function _fnCharPos(l:Dynamic):Int    { final c=_char(Lua.tostring(l,1));final x=Lua.tonumber(l,2);final y=Lua.tonumber(l,3);Lua.settop(l,0); if(c!=null){c.x=x;c.y=y;} return 0; }
	static function _fnCharX(l:Dynamic):Int      { final c=_char(Lua.tostring(l,1));final v=Lua.tonumber(l,2);Lua.settop(l,0); if(c!=null)c.x=v; return 0; }
	static function _fnCharY(l:Dynamic):Int      { final c=_char(Lua.tostring(l,1));final v=Lua.tonumber(l,2);Lua.settop(l,0); if(c!=null)c.y=v; return 0; }
	static function _fnCharGetX(l:Dynamic):Int   { final c=_char(Lua.tostring(l,1));Lua.settop(l,0); Lua.pushnumber(l,c!=null?c.x:0); return 1; }
	static function _fnCharGetY(l:Dynamic):Int   { final c=_char(Lua.tostring(l,1));Lua.settop(l,0); Lua.pushnumber(l,c!=null?c.y:0); return 1; }
	static function _fnCharScale(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1)); final sx=Lua.tonumber(l,2); final sy=Lua.gettop(l)>2?Lua.tonumber(l,3):sx; Lua.settop(l,0);
		if(c!=null){c.scale.x=sx;c.scale.y=sy;c.updateHitbox();} return 0;
	}
	static function _fnCharVisible(l:Dynamic):Int { final c=_char(Lua.tostring(l,1));final v=Lua.toboolean(l,2);Lua.settop(l,0); if(c!=null)c.visible=v; return 0; }
	static function _fnCharAlpha(l:Dynamic):Int   { final c=_char(Lua.tostring(l,1));final v=Lua.tonumber(l,2);Lua.settop(l,0); if(c!=null)c.alpha=v; return 0; }
	static function _fnCharColor(l:Dynamic):Int   { final c=_char(Lua.tostring(l,1));final v=Std.int(Lua.tonumber(l,2));Lua.settop(l,0); if(c!=null)c.color=v; return 0; }
	static function _fnCharAngle(l:Dynamic):Int   { final c=_char(Lua.tostring(l,1));final v=Lua.tonumber(l,2);Lua.settop(l,0); if(c!=null)c.angle=v; return 0; }
	static function _fnCharFlip(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1));final fx=Lua.toboolean(l,2);final fy=Lua.gettop(l)>2&&Lua.toboolean(l,3);Lua.settop(l,0);
		if(c!=null){c.flipX=fx;c.flipY=fy;} return 0;
	}
	static function _fnCharScroll(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1));final sx=Lua.tonumber(l,2);final sy=Lua.gettop(l)>2?Lua.tonumber(l,3):sx;Lua.settop(l,0);
		if(c!=null)c.scrollFactor.set(sx,sy); return 0;
	}
	static function _fnCharGetAnim(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1));Lua.settop(l,0);
		final name=try c?.animation?.curAnim?.name ?? '' catch(_) '';
		Lua.pushstring(l,name); return 1;
	}
	static function _fnCharAnimDone(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1));Lua.settop(l,0);
		Lua.pushboolean(l, try c?.animation?.curAnim?.finished ?? false catch(_) false); return 1;
	}
	static function _fnCharLock(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1));final v=Lua.toboolean(l,2);Lua.settop(l,0);
		if(c!=null) try Reflect.setField(c,'debugMode',v) catch(_) {}; return 0;
	}
	static function _fnCharRate(l:Dynamic):Int
	{
		final c=_char(Lua.tostring(l,1));final v=Lua.tonumber(l,2);Lua.settop(l,0);
		if(c!=null) try c.animation.timeScale=v catch(_) {}; return 0;
	}
	static function _fnSetBF(l:Dynamic):Int
	{
		final n=Lua.tostring(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try Reflect.callMethod(p,Reflect.field(p,'changeCharacter'),['bf',n]) catch(_) {}; return 0;
	}
	static function _fnSetDAD(l:Dynamic):Int
	{
		final n=Lua.tostring(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try Reflect.callMethod(p,Reflect.field(p,'changeCharacter'),['dad',n]) catch(_) {}; return 0;
	}
	static function _fnSetGF(l:Dynamic):Int
	{
		final n=Lua.tostring(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try Reflect.callMethod(p,Reflect.field(p,'changeCharacter'),['gf',n]) catch(_) {}; return 0;
	}
	static function _fnSongName(l:Dynamic):Int
	{
		final p=_ps(); Lua.settop(l,0);
		Lua.pushstring(l, p!=null ? try p.SONG.song ?? '' catch(_) '' : ''); return 1;
	}
	static function _fnSongArtist(l:Dynamic):Int
	{
		final p=_ps(); Lua.settop(l,0);
		Lua.pushstring(l, p!=null ? try p.listArtist ?? 'Unknown' catch(_) 'Unknown' : 'Unknown'); return 1;
	}

	// ── Gameplay extendido ────────────────────────────────────────────────────

	static function _fnIsStory(l:Dynamic):Int    { Lua.pushboolean(l, try funkin.gameplay.PlayState.isStoryMode catch(_) false); return 1; }
	static function _fnGetDiff(l:Dynamic):Int    { final p=_ps(); Lua.pushstring(l, p!=null ? try p.storyDifficultyText catch(_) 'normal' : 'normal'); return 1; }
	static function _fnGetAcc(l:Dynamic):Int     { final p=_ps(); Lua.pushnumber(l, p!=null ? try p.accuracy catch(_) 0.0 : 0.0); return 1; }
	static function _fnGetSicks(l:Dynamic):Int   { final p=_ps(); Lua.pushnumber(l, p!=null ? try p.sicks   catch(_) 0 : 0); return 1; }
	static function _fnGetGoods(l:Dynamic):Int   { final p=_ps(); Lua.pushnumber(l, p!=null ? try p.goods   catch(_) 0 : 0); return 1; }
	static function _fnGetBads(l:Dynamic):Int    { final p=_ps(); Lua.pushnumber(l, p!=null ? try p.bads    catch(_) 0 : 0); return 1; }
	static function _fnGetShits(l:Dynamic):Int   { final p=_ps(); Lua.pushnumber(l, p!=null ? try p.shits   catch(_) 0 : 0); return 1; }
	static function _fnSetSicks(l:Dynamic):Int   { final v=Std.int(Lua.tonumber(l,1));Lua.settop(l,0);final p=_ps(); if(p!=null) try p.sicks=v catch(_) {}; return 0; }
	static function _fnSetScroll(l:Dynamic):Int
	{
		final v=Lua.tonumber(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try p.scrollSpeed=v catch(_) try Reflect.setField(p,'scrollSpeed',v) catch(_) {}; return 0;
	}
	static function _fnGetScroll(l:Dynamic):Int
	{
		final p=_ps(); Lua.pushnumber(l, p!=null ? try p.scrollSpeed catch(_) 1.0 : 1.0); return 1;
	}
	static function _fnNoteAlpha(l:Dynamic):Int
	{
		final n=resolve(Std.int(Lua.tonumber(l,1)));final v=Lua.tonumber(l,2);Lua.settop(l,0);
		if(n!=null) try n.alpha=v catch(_) {}; return 0;
	}
	static function _fnNoteColor(l:Dynamic):Int
	{
		final n=resolve(Std.int(Lua.tonumber(l,1)));final c=Std.int(Lua.tonumber(l,2));Lua.settop(l,0);
		if(n!=null) try n.color=c catch(_) {}; return 0;
	}
	static function _fnSkipNote(l:Dynamic):Int
	{
		final n=resolve(Std.int(Lua.tonumber(l,1)));Lua.settop(l,0);
		if(n!=null) try n.wasGoodHit=true catch(_) {}; return 0;
	}
	static function _fnNoteSkin(l:Dynamic):Int
	{
		final s=Lua.tostring(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try p.noteSkin=s catch(_) try Reflect.setField(p,'noteSkin',s) catch(_) {}; return 0;
	}
	static function _fnForNote(l:Dynamic):Int
	{
		final fn=Lua.tostring(l,1); Lua.settop(l,0); final p=_ps(); if(p==null) return 0;
		try
		{
			final notes:Array<Dynamic> = try p.unspawnNotes catch(_) [];
			for(n in notes)
			{
				Lua.getglobal(_sCurrentLua, fn);
				if(Lua.type(_sCurrentLua, -1)==6)
				{
					Lua.pushnumber(_sCurrentLua, register(n));
					Lua.pcall(_sCurrentLua, 1, 0, 0);
				}
				else Lua.pop(_sCurrentLua, 1);
			}
		}
		catch(e:Dynamic) trace('[Lua] forEachNote: $e');
		return 0;
	}

	// ── Modchart ──────────────────────────────────────────────────────────────

	static function _fnSetMod(l:Dynamic):Int
	{
		final name=Lua.tostring(l,1);final val=Lua.tonumber(l,2);
		final plr=Lua.gettop(l)>2?Std.int(Lua.tonumber(l,3)):0;Lua.settop(l,0);
		final p=_ps(); if(p==null) return 0;
		try
		{
			final mm=Reflect.field(p,'modChartManager');
			if(mm!=null) Reflect.callMethod(mm, Reflect.field(mm,'setModifier'),[name,val,plr]);
		}
		catch(e:Dynamic) trace('[Lua] setModifier: $e');
		return 0;
	}
	static function _fnGetMod(l:Dynamic):Int
	{
		final name=Lua.tostring(l,1);final plr=Lua.gettop(l)>1?Std.int(Lua.tonumber(l,2)):0;Lua.settop(l,0);
		final p=_ps(); if(p==null){Lua.pushnumber(l,0);return 1;}
		try
		{
			final mm=Reflect.field(p,'modChartManager');
			if(mm!=null){_push(l, Reflect.callMethod(mm,Reflect.field(mm,'getModifier'),[name,plr]));return 1;}
		}
		catch(_){}
		Lua.pushnumber(l,0); return 1;
	}
	static function _fnClearMods(l:Dynamic):Int
	{
		Lua.settop(l,0);final p=_ps(); if(p==null) return 0;
		try{final mm=Reflect.field(p,'modChartManager');if(mm!=null)Reflect.callMethod(mm,Reflect.field(mm,'clearModifiers'),[]);}
		catch(_){} return 0;
	}
	static function _fnNoteMod(l:Dynamic):Int
	{
		final n=resolve(Std.int(Lua.tonumber(l,1)));final name=Lua.tostring(l,2);final val=Lua.tonumber(l,3);Lua.settop(l,0);
		if(n!=null) try Reflect.setField(n,name,val) catch(_) {}; return 0;
	}

	// ── Vocales ───────────────────────────────────────────────────────────────

	static function _fnVocVol(l:Dynamic):Int
	{
		final v=Lua.tonumber(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try{if(p.vocals!=null) p.vocals.volume=v;} catch(_) {}; return 0;
	}
	static function _fnVocP(l:Dynamic):Int
	{
		final v=Lua.tonumber(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try{if(p.vocalsBf!=null)p.vocalsBf.volume=v else if(p.vocals!=null)p.vocals.volume=v;} catch(_) {}; return 0;
	}
	static function _fnVocOp(l:Dynamic):Int
	{
		final v=Lua.tonumber(l,1);Lua.settop(l,0);final p=_ps();
		if(p!=null) try{if(p.vocalsDad!=null)p.vocalsDad.volume=v;} catch(_) {}; return 0;
	}
	static function _fnMuteVoc(l:Dynamic):Int
	{
		final mute=Lua.toboolean(l,1);Lua.settop(l,0);final p=_ps();
		final vol=mute?0.0:1.0;
		if(p!=null) try
		{
			if(p.vocals!=null)   p.vocals.volume=vol;
			if(p.vocalsBf!=null) p.vocalsBf.volume=vol;
			if(p.vocalsDad!=null)p.vocalsDad.volume=vol;
		}
		catch(_) {}; return 0;
	}

	// ── Eventos del juego ─────────────────────────────────────────────────────

	static function _fnTriggerEv(l:Dynamic):Int
	{
		final name=Lua.tostring(l,1);
		final v1=Lua.gettop(l)>1?Lua.tostring(l,2):'';
		final v2=Lua.gettop(l)>2?Lua.tostring(l,3):'';
		final t=Lua.gettop(l)>3?Lua.tonumber(l,4):try funkin.data.Conductor.songPosition catch(_) 0.0;
		Lua.settop(l,0);
		try
		{
			final evData:Dynamic = {name:name, value1:v1, value2:v2, time:t};
			funkin.scripting.events.EventManager.triggerEvent(evData);
		}
		catch(e:Dynamic) trace('[Lua] triggerEvent: $e');
		return 0;
	}
	static function _fnRegisterEv(l:Dynamic):Int
	{
		final name=Lua.tostring(l,1); final fn=Lua.tostring(l,2); Lua.settop(l,0);
		funkin.scripting.ScriptHandler.setOnScripts('__evHook_$name', fn);
		return 0;
	}

	/**
	 * getEventDef(name) → pushes a Lua table with the event definition fields:
	 *   { name, description, color, contexts={...}, aliases={...}, params={{name,type,defaultValue,description},...} }
	 * Returns nil if the event is not found.
	 *
	 * Usage:
	 *   local def = getEventDef("Camera Follow")
	 *   if def then
	 *     trace(def.name)
	 *     trace(def.description)
	 *     trace(#def.params)
	 *   end
	 */
	static function _fnGetEventDef(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1); Lua.settop(l, 0);
		final def = funkin.scripting.events.EventRegistry.get(name);
		if (def == null) { Lua.pushnil(l); return 1; }

		Lua.newtable(l); // root table

		Lua.pushstring(l, 'name');        Lua.pushstring(l, def.name);              Lua.settable(l, -3);
		Lua.pushstring(l, 'description'); Lua.pushstring(l, def.description ?? ''); Lua.settable(l, -3);
		Lua.pushstring(l, 'color');       Lua.pushnumber(l, def.color);             Lua.settable(l, -3);

		// contexts array
		Lua.pushstring(l, 'contexts'); Lua.newtable(l);
		for (i in 0...def.contexts.length)
		{
			Lua.pushnumber(l, i + 1); Lua.pushstring(l, def.contexts[i]); Lua.settable(l, -3);
		}
		Lua.settable(l, -3);

		// aliases array
		Lua.pushstring(l, 'aliases'); Lua.newtable(l);
		for (i in 0...def.aliases.length)
		{
			Lua.pushnumber(l, i + 1); Lua.pushstring(l, def.aliases[i]); Lua.settable(l, -3);
		}
		Lua.settable(l, -3);

		// params array of tables
		Lua.pushstring(l, 'params'); Lua.newtable(l);
		for (i in 0...def.params.length)
		{
			final p = def.params[i];
			Lua.pushnumber(l, i + 1); Lua.newtable(l);
			Lua.pushstring(l, 'name');         Lua.pushstring(l, p.name);               Lua.settable(l, -3);
			Lua.pushstring(l, 'defaultValue'); Lua.pushstring(l, p.defValue);           Lua.settable(l, -3);
			Lua.pushstring(l, 'description');  Lua.pushstring(l, p.description ?? ''); Lua.settable(l, -3);
			Lua.settable(l, -3);
		}
		Lua.settable(l, -3);

		return 1;
	}

	/**
	 * listEvents(?context) → pushes a Lua array table of event names.
	 * If context is nil/empty, returns all events.
	 *
	 * Usage:
	 *   local names = listEvents("chart")
	 *   for i, name in ipairs(names) do trace(name) end
	 */
	static function _fnListEvents(l:Dynamic):Int
	{
		final ctx = Lua.gettop(l) > 0 ? Lua.tostring(l, 1) : null; Lua.settop(l, 0);
		final names = (ctx != null && ctx != '')
			? funkin.scripting.events.EventRegistry.getNamesForContext(ctx)
			: funkin.scripting.events.EventRegistry.eventList;

		Lua.newtable(l);
		for (i in 0...names.length)
		{
			Lua.pushnumber(l, i + 1); Lua.pushstring(l, names[i]); Lua.settable(l, -3);
		}
		return 1;
	}

	/**
	 * registerEventDef(table) → registers a new event definition in EventRegistry.
	 * The table must have at least a "name" field.
	 *
	 * Usage:
	 *   registerEventDef({
	 *     name = "My Custom Event",
	 *     description = "Does something cool",
	 *     color = 0xFF88FF88,
	 *     contexts = { "chart" },
	 *     aliases = { "MCE" },
	 *     params = {
	 *       { name = "Target", type = "DropDown(bf,dad)", defaultValue = "bf" },
	 *       { name = "Value",  type = "Float(0,1)",       defaultValue = "1.0" }
	 *     }
	 *   })
	 */
	static function _fnRegisterEventDef(l:Dynamic):Int
	{
		if (Lua.type(l, 1) != 5) { Lua.settop(l, 0); return 0; }
		final opts = _luaTableToOpts(l, 1); Lua.settop(l, 0);

		final name = opts.name != null ? Std.string(opts.name) : '';
		if (name == '') return 0;

		// Parse contexts
		var contexts = ['chart'];
		if (opts.contexts != null && Std.isOfType(opts.contexts, Array))
			contexts = [for (c in (opts.contexts:Array<Dynamic>)) Std.string(c)];

		// Parse aliases
		var aliases:Array<String> = [];
		if (opts.aliases != null && Std.isOfType(opts.aliases, Array))
			aliases = [for (a in (opts.aliases:Array<Dynamic>)) Std.string(a)];

		// Parse params
		var params:Array<funkin.scripting.events.EventInfoSystem.EventParamDef> = [];
		if (opts.params != null && Std.isOfType(opts.params, Array))
		{
			for (p in (opts.params:Array<Dynamic>))
			{
				if (p == null || p.name == null) continue;
				params.push({
					name:     Std.string(p.name),
					type:     funkin.scripting.events.EventInfoSystem.parseParamType(
					              Std.string(p.type ?? 'String')),
					defValue: p.defaultValue != null ? Std.string(p.defaultValue) : '',
					description: p.description != null ? Std.string(p.description) : null
				});
			}
		}

		funkin.scripting.events.EventRegistry.register({
			name:        name,
			description: opts.description != null ? Std.string(opts.description) : null,
			color:       opts.color != null ? Std.int(opts.color) : 0xFFAAAAAA,
			contexts:    contexts,
			aliases:     aliases,
			params:      params,
			hscriptPath: opts.hscriptPath != null ? Std.string(opts.hscriptPath) : null,
			luaPath:     opts.luaPath     != null ? Std.string(opts.luaPath)     : null,
			sourceDir:   null
		});
		return 0;
	}

	// ── Tweens extendidos ─────────────────────────────────────────────────────

	static function _fnTweenAngle(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));final to=Lua.tonumber(l,2);final dur=Lua.tonumber(l,3);
		final e=Lua.gettop(l)>3?Lua.tostring(l,4):'linear'; Lua.settop(l,0);
		final obj=resolve(h); if(obj==null){Lua.pushnil(l);return 1;}
		final tw=flixel.tweens.FlxTween.tween(obj,{angle:to},dur,{ease:_ease(e)});
		Lua.pushnumber(l,register(tw)); return 1;
	}
	static function _fnTweenPos(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));final tx=Lua.tonumber(l,2);final ty=Lua.tonumber(l,3);
		final dur=Lua.tonumber(l,4);final e=Lua.gettop(l)>4?Lua.tostring(l,5):'linear'; Lua.settop(l,0);
		final obj=resolve(h); if(obj==null){Lua.pushnil(l);return 1;}
		final tw=flixel.tweens.FlxTween.tween(obj,{x:tx,y:ty},dur,{ease:_ease(e)});
		Lua.pushnumber(l,register(tw)); return 1;
	}
	static function _fnTweenAlpha(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));final to=Lua.tonumber(l,2);final dur=Lua.tonumber(l,3);
		final e=Lua.gettop(l)>3?Lua.tostring(l,4):'linear'; Lua.settop(l,0);
		final obj=resolve(h); if(obj==null){Lua.pushnil(l);return 1;}
		final tw=flixel.tweens.FlxTween.tween(obj,{alpha:to},dur,{ease:_ease(e)});
		Lua.pushnumber(l,register(tw)); return 1;
	}
	static function _fnTweenScale(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));final sx=Lua.tonumber(l,2);final sy=Lua.gettop(l)>2?Lua.tonumber(l,3):sx;
		final dur=Lua.tonumber(l,4);final e=Lua.gettop(l)>4?Lua.tostring(l,5):'linear'; Lua.settop(l,0);
		final obj=resolve(h); if(obj==null){Lua.pushnil(l);return 1;}
		final tw=flixel.tweens.FlxTween.tween(obj,{'scale.x':sx,'scale.y':sy},dur,{ease:_ease(e)});
		Lua.pushnumber(l,register(tw)); return 1;
	}
	static function _fnNumTween(l:Dynamic):Int
	{
		final from=Lua.tonumber(l,1);final to=Lua.tonumber(l,2);final dur=Lua.tonumber(l,3);
		final fn=Lua.tostring(l,4);final e=Lua.gettop(l)>4?Lua.tostring(l,5):'linear'; Lua.settop(l,0);
		var dummy:Dynamic = {val:from};
		final tw=flixel.tweens.FlxTween.tween(dummy,{val:to},dur,{ease:_ease(e),onUpdate:function(_) {
			final script=_timerScripts.get(register(dummy));
			if(script!=null && script.active) script.call(fn,[dummy.val]);
		}});
		Lua.pushnumber(l,register(tw)); return 1;
	}

	// ── Texto extendido ───────────────────────────────────────────────────────

	static function _fnTextItalic(l:Dynamic):Int  { final h=Std.int(Lua.tonumber(l,1));final v=Lua.toboolean(l,2);Lua.settop(l,0); try resolve(h).italic=v catch(_){}; return 0; }
	static function _fnTextShadow(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));final c=Std.int(Lua.tonumber(l,2));
		final ox=Lua.gettop(l)>2?Lua.tonumber(l,3):2.0;final oy=Lua.gettop(l)>3?Lua.tonumber(l,4):2.0;Lua.settop(l,0);
		try resolve(h).setBorderStyle(flixel.text.FlxText.FlxTextBorderStyle.SHADOW,c,ox,oy) catch(_){}; return 0;
	}
	static function _fnGetText(l:Dynamic):Int { final h=Std.int(Lua.tonumber(l,1));Lua.settop(l,0); try Lua.pushstring(l,resolve(h).text) catch(_) Lua.pushstring(l,''); return 1; }

	// ── Sprites extendidos ────────────────────────────────────────────────────

	static function _fnSprAngle(l:Dynamic):Int    { final s=_spr(l,1);final v=Lua.tonumber(l,2);Lua.settop(l,0); if(s!=null)s.angle=v; return 0; }
	static function _fnSprVisible(l:Dynamic):Int  { final s=_spr(l,1);final v=Lua.toboolean(l,2);Lua.settop(l,0); if(s!=null)s.visible=v; return 0; }
	static function _fnSprGetX(l:Dynamic):Int     { final s=_spr(l,1);Lua.settop(l,0); Lua.pushnumber(l,s!=null?s.x:0); return 1; }
	static function _fnSprGetY(l:Dynamic):Int     { final s=_spr(l,1);Lua.settop(l,0); Lua.pushnumber(l,s!=null?s.y:0); return 1; }
	static function _fnSprGetW(l:Dynamic):Int     { final s=_spr(l,1);Lua.settop(l,0); Lua.pushnumber(l,s!=null?s.width:0); return 1; }
	static function _fnSprGetH(l:Dynamic):Int     { final s=_spr(l,1);Lua.settop(l,0); Lua.pushnumber(l,s!=null?s.height:0); return 1; }
	static function _fnUpdateHitbox(l:Dynamic):Int { final s=_spr(l,1);Lua.settop(l,0); if(s!=null)try s.updateHitbox() catch(_){}; return 0; }
	static function _fnFrameSize(l:Dynamic):Int
	{
		final s=_spr(l,1);final w=Std.int(Lua.tonumber(l,2));final h=Std.int(Lua.tonumber(l,3));Lua.settop(l,0);
		if(s!=null) try s.setGraphicSize(w,h) catch(_){}; return 0;
	}
	static function _fnAddAnimIdx(l:Dynamic):Int
	{
		final s=_spr(l,1);final n=Lua.tostring(l,2);final p=Lua.tostring(l,3);
		// Parse indices from comma-separated string or skip
		final f=Lua.gettop(l)>3?Std.int(Lua.tonumber(l,4)):24;
		final lo=Lua.gettop(l)>4&&Lua.toboolean(l,5); Lua.settop(l,0);
		if(s!=null) try s.animation.addByPrefix(n,p,f,lo) catch(_){}; return 0;
	}
	static function _fnGetCurAnim(l:Dynamic):Int
	{
		final s=_spr(l,1);Lua.settop(l,0);
		try Lua.pushstring(l,s?.animation?.curAnim?.name??'') catch(_) Lua.pushstring(l,''); return 1;
	}
	static function _fnIsAnimPlay(l:Dynamic):Int
	{
		final s=_spr(l,1);final n=Lua.tostring(l,2);Lua.settop(l,0);
		Lua.pushboolean(l, try s?.animation?.curAnim?.name==n catch(_) false); return 1;
	}
	static function _fnSetAnimFPS(l:Dynamic):Int
	{
		final s=_spr(l,1);final fps=Std.int(Lua.tonumber(l,2));Lua.settop(l,0);
		if(s!=null) try s.animation.curAnim.frameRate=fps catch(_){}; return 0;
	}
	static function _fnSprCam(l:Dynamic):Int
	{
		final s=_spr(l,1);final c=_cam(l,2);Lua.settop(l,0);
		if(s!=null) try s.cameras=[c] catch(_){}; return 0;
	}

	// ── Cámara: control fino ──────────────────────────────────────────────────

	static function _fnCamTarget(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));final c=_cam(l,2);Lua.settop(l,0);
		final obj=resolve(h); if(obj==null) return 0;
		try c.follow(obj) catch(_){}; return 0;
	}
	static function _fnCamFollow(l:Dynamic):Int
	{
		final style = Lua.tostring(l, 1); final c = _cam(l, 2); Lua.settop(l, 0);
		try {
			final target = c.target;
			switch style {
				case 'LOCKON':
					c.follow(target, flixel.FlxCamera.FlxCameraFollowStyle.LOCKON, 0.04);
				case 'PLATFORMER':
					c.follow(target, flixel.FlxCamera.FlxCameraFollowStyle.PLATFORMER, 0.1);
				case 'TOPDOWN':
					c.follow(target, flixel.FlxCamera.FlxCameraFollowStyle.TOPDOWN, 0.04);
				case 'TOPDOWN_TIGHT':
					c.follow(target, flixel.FlxCamera.FlxCameraFollowStyle.TOPDOWN_TIGHT, 0.04);
				case 'SCREEN_BY_SCREEN':
					c.follow(target, flixel.FlxCamera.FlxCameraFollowStyle.SCREEN_BY_SCREEN, 1.0);
				case 'NO_DEAD_ZONE':
					c.follow(target, flixel.FlxCamera.FlxCameraFollowStyle.NO_DEAD_ZONE, 1.0);
				default:
					c.followLerp = 0.04;
			}
		} catch(_) {}
		return 0;
	}
	static function _fnCamLerp(l:Dynamic):Int    { final v=Lua.tonumber(l,1);final c=_cam(l,2);Lua.settop(l,0); try c.followLerp=v catch(_){}; return 0; }
	static function _fnGetCamZoom(l:Dynamic):Int  { final c=_cam(l,1);Lua.settop(l,0); Lua.pushnumber(l,c.zoom); return 1; }
	static function _fnCamScrollX(l:Dynamic):Int  { final v=Lua.tonumber(l,1);final c=_cam(l,2);Lua.settop(l,0); c.scroll.x=v; return 0; }
	static function _fnCamScrollY(l:Dynamic):Int  { final v=Lua.tonumber(l,1);final c=_cam(l,2);Lua.settop(l,0); c.scroll.y=v; return 0; }
	static function _fnRemoveCam(l:Dynamic):Int
	{
		final h=Std.int(Lua.tonumber(l,1));Lua.settop(l,0);
		final c=resolve(h); if(c!=null) try flixel.FlxG.cameras.remove(c,true) catch(_){}; release(h); return 0;
	}

	// ── Shaders ───────────────────────────────────────────────────────────────

	static function _fnAddShader(l:Dynamic):Int
	{
		final target=Lua.tostring(l,1);final name=Lua.tostring(l,2);Lua.settop(l,0);
		try
		{
			final p=_ps();
			final cam:flixel.FlxCamera = switch target {
				case 'hud': p?.camHUD??flixel.FlxG.camera;
				case 'ui':  p?.camUI ??flixel.FlxG.camera;
				default: flixel.FlxG.camera;
			};
			final sh=Type.createInstance(Type.resolveClass('shaders.$name')??Type.resolveClass(name)??Type.resolveClass('funkin.shaders.$name'),[]);
			if(sh!=null) cam.filters=[new openfl.filters.ShaderFilter(sh)];
		}
		catch(e:Dynamic) trace('[Lua] addShader: $e');
		return 0;
	}
	static function _fnRemoveShader(l:Dynamic):Int
	{
		final target=Lua.tostring(l,1);Lua.settop(l,0);
		try
		{
			final p=_ps();
			final cam:flixel.FlxCamera=switch target{case 'hud':p?.camHUD??flixel.FlxG.camera;case 'ui':p?.camUI??flixel.FlxG.camera;default:flixel.FlxG.camera;};
			cam.filters=[];
		}
		catch(_){} return 0;
	}
	static function _fnShaderProp(l:Dynamic):Int
	{
		final target=Lua.tostring(l,1);final prop=Lua.tostring(l,2);final val=_read(l,3);Lua.settop(l,0);
		try
		{
			final p=_ps();
			final cam:flixel.FlxCamera=switch target{case 'hud':p?.camHUD??flixel.FlxG.camera;case 'ui':p?.camUI??flixel.FlxG.camera;default:flixel.FlxG.camera;};
			if(cam.filters!=null&&cam.filters.length>0)
			{
				final sh=Reflect.field(cam.filters[0],'shader');
				if(sh!=null) Reflect.setField(sh,prop,val);
			}
		}
		catch(_){} return 0;
	}

	// ── UI / Diálogos ─────────────────────────────────────────────────────────
	// Usa ScriptDialog — misma clase que HScript

	static function _fnNotif(l:Dynamic):Int
	{
		final msg = Lua.tostring(l, 1);
		final dur = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 2.5; Lua.settop(l, 0);
		final d = funkin.scripting.ScriptDialog.quick('', msg, dur);
		// Sin speaker para notificaciones
		Lua.pushnumber(l, register(d)); return 1;
	}

	/** newDialog() → handle de ScriptDialog vacío listo para configurar. */
	static function _fnNewDialog(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final d = new funkin.scripting.ScriptDialog();
		Lua.pushnumber(l, register(d)); return 1;
	}

	/** dialogAddLine(handle, speaker, text, ?speakerColor, ?autoAdvance) */
	static function _fnDialogAddLine(l:Dynamic):Int
	{
		final h  = Std.int(Lua.tonumber(l, 1));
		final sp = Lua.tostring(l, 2);
		final tx = Lua.tostring(l, 3);
		final sc = Lua.gettop(l) > 3 ? Std.int(Lua.tonumber(l, 4)) : -1;
		final aa = Lua.gettop(l) > 4 ? Lua.tonumber(l, 5) : 0.0;
		Lua.settop(l, 0);
		final d = resolve(h);
		if (d != null) try
		{
			final color = sc >= 0 ? (sc : flixel.util.FlxColor) : null;
			d.addLine(sp, tx, color, null, aa > 0 ? aa : null);
		}
		catch(e:Dynamic) trace('[Lua] dialogAddLine: $e');
		return 0;
	}

	/** dialogSetPortrait(handle, key, path) */
	static function _fnDialogPortrait(l:Dynamic):Int
	{
		final h   = Std.int(Lua.tonumber(l, 1));
		final key = Lua.tostring(l, 2);
		final pth = Lua.tostring(l, 3); Lua.settop(l, 0);
		final d = resolve(h);
		if (d != null) try d.setPortrait(key, pth) catch(e:Dynamic) trace('[Lua] dialogSetPortrait: $e');
		return 0;
	}

	/** dialogSetTypeSpeed(handle, seconds) */
	static function _fnDialogTypeSpeed(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final v = Lua.tonumber(l, 2); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.typeSpeed = v catch(_) {}; return 0;
	}

	/** dialogSetAutoAdvance(handle, seconds) */
	static function _fnDialogAutoAdv(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final v = Lua.tonumber(l, 2); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.autoAdvance = v catch(_) {}; return 0;
	}

	/** dialogSetSpeakerColor(handle, color) */
	static function _fnDialogSpColor(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final c = Std.int(Lua.tonumber(l, 2)); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.speakerColor = c catch(_) {}; return 0;
	}

	/** dialogSetBgColor(handle, color) */
	static function _fnDialogBgColor(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final c = Std.int(Lua.tonumber(l, 2)); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.setBgColor(c) catch(_) {}; return 0;
	}

	/** dialogSetAllowSkip(handle, bool) */
	static function _fnDialogAllowSkip(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); final v = Lua.toboolean(l, 2); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.allowSkipLine = v catch(_) {}; return 0;
	}

	/** dialogOnFinish(handle, callbackFunctionName) */
	static function _fnDialogOnFinish(l:Dynamic):Int
	{
		final h  = Std.int(Lua.tonumber(l, 1));
		final fn = Lua.tostring(l, 2); Lua.settop(l, 0);
		final d  = resolve(h);
		if (d != null)
		{
			Lua.getglobal(_sCurrentLua, '__scriptHandle');
			final selfH = _sCurrentLua != null ? Std.int(Lua.tonumber(_sCurrentLua, -1)) : -1;
			if (_sCurrentLua != null) Lua.pop(_sCurrentLua, 1);
			final script = selfH >= 0 ? _timerScripts.get(selfH) : null;
			try d.onFinish = function() { if (script != null && script.active) script.call(fn); }
			catch(_) {};
		}
		return 0;
	}

	/** dialogOnLine(handle, callbackFunctionName)
	 *  El callback recibe: index, speaker, text */
	static function _fnDialogOnLine(l:Dynamic):Int
	{
		final h  = Std.int(Lua.tonumber(l, 1));
		final fn = Lua.tostring(l, 2); Lua.settop(l, 0);
		final d  = resolve(h);
		if (d != null)
		{
			Lua.getglobal(_sCurrentLua, '__scriptHandle');
			final selfH = _sCurrentLua != null ? Std.int(Lua.tonumber(_sCurrentLua, -1)) : -1;
			if (_sCurrentLua != null) Lua.pop(_sCurrentLua, 1);
			final script = selfH >= 0 ? _timerScripts.get(selfH) : null;
			try d.onLine = function(idx:Int, sp:String, tx:String) {
				if (script != null && script.active) script.call(fn, [idx, sp, tx]);
			} catch(_) {};
		}
		return 0;
	}

	/** dialogShow(handle) — muestra el diálogo */
	static function _fnDialogShow(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.show() catch(e:Dynamic) trace('[Lua] dialogShow: $e');
		return 0;
	}

	/** dialogClose(handle) */
	static function _fnDialogClose(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.close() catch(_) {}; return 0;
	}

	/** dialogSkipAll(handle) */
	static function _fnDialogSkipAll(l:Dynamic):Int
	{
		final h = Std.int(Lua.tonumber(l, 1)); Lua.settop(l, 0);
		final d = resolve(h); if (d != null) try d.skipAll() catch(_) {}; return 0;
	}

	/** dialogQuick(speaker, text, ?duration, ?callbackName) — atajo de una línea */
	static function _fnDialogQuick(l:Dynamic):Int
	{
		final sp = Lua.tostring(l, 1);
		final tx = Lua.tostring(l, 2);
		final dur = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0;
		final fn  = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : null; Lua.settop(l, 0);

		Lua.getglobal(_sCurrentLua, '__scriptHandle');
		final selfH = _sCurrentLua != null ? Std.int(Lua.tonumber(_sCurrentLua, -1)) : -1;
		if (_sCurrentLua != null) Lua.pop(_sCurrentLua, 1);
		final script = selfH >= 0 ? _timerScripts.get(selfH) : null;

		var cb:Void->Void = null;
		if (fn != null && script != null)
			cb = function() { if (script.active) script.call(fn); };

		final d = funkin.scripting.ScriptDialog.quick(sp, tx, dur, cb);
		Lua.pushnumber(l, register(d)); return 1;
	}

	/** dialogSequence(lines_table, ?callbackName)
	 *  lines_table = { {speaker="X", text="..."}, ... }  */
	static function _fnDialogSequence(l:Dynamic):Int
	{
		// Leer tabla Lua como array de {speaker, text}
		final lines:Array<{speaker:String, text:String}> = [];
		if (Lua.type(l, 1) == 5)
		{
			var i = 1;
			while (true)
			{
				Lua.pushnumber(l, i);
				Lua.gettable(l, 1);
				if (Lua.type(l, -1) != 5) { Lua.pop(l, 1); break; }
				// leer speaker
				Lua.pushstring(l, 'speaker'); Lua.gettable(l, -2);
				final sp = Lua.tostring(l, -1); Lua.pop(l, 1);
				// leer text
				Lua.pushstring(l, 'text'); Lua.gettable(l, -2);
				final tx = Lua.tostring(l, -1); Lua.pop(l, 1);
				Lua.pop(l, 1);
				lines.push({speaker: sp ?? '', text: tx ?? ''});
				i++;
			}
		}
		final fn = Lua.gettop(l) > 1 ? Lua.tostring(l, 2) : null; Lua.settop(l, 0);

		Lua.getglobal(_sCurrentLua, '__scriptHandle');
		final selfH = _sCurrentLua != null ? Std.int(Lua.tonumber(_sCurrentLua, -1)) : -1;
		if (_sCurrentLua != null) Lua.pop(_sCurrentLua, 1);
		final script = selfH >= 0 ? _timerScripts.get(selfH) : null;

		var cb:Void->Void = null;
		if (fn != null && script != null)
			cb = function() { if (script.active) script.call(fn); };

		final d = funkin.scripting.ScriptDialog.sequence(lines, cb);
		Lua.pushnumber(l, register(d)); return 1;
	}

	/** closeAllDialogs() — cierra todos los ScriptDialog activos */
	static function _fnCloseAllDialogs(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final state = flixel.FlxG.state;
		for (member in state.members)
			if (Std.isOfType(member, funkin.scripting.ScriptDialog))
				try (cast member : funkin.scripting.ScriptDialog).close() catch(_) {};
		return 0;
	}

	// ── Datos persistentes ────────────────────────────────────────────────────

	static function _dataPath(key:String):String
	{
		#if sys
		final dir='saves/moddata'; if(!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		return '$dir/${StringTools.replace(StringTools.replace(key, "/","_"), "..","")}.json';
		#else return ''; #end
	}
	static function _fnDataSave(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1);final v=_read(l,2);Lua.settop(l,0);
		#if sys
		try sys.io.File.saveContent(_dataPath(k), haxe.Json.stringify(v)) catch(e:Dynamic) trace('[Lua] dataSave: $e');
		#end return 0;
	}
	static function _fnDataLoad(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1);Lua.settop(l,0);
		#if sys
		try { final p=_dataPath(k); if(sys.FileSystem.exists(p)){_push(l,haxe.Json.parse(sys.io.File.getContent(p)));return 1;} } catch(_) {}
		#end Lua.pushnil(l); return 1;
	}
	static function _fnDataExists(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1);Lua.settop(l,0);
		#if sys Lua.pushboolean(l,sys.FileSystem.exists(_dataPath(k))); #else Lua.pushboolean(l,false); #end return 1;
	}
	static function _fnDataDelete(l:Dynamic):Int
	{
		final k=Lua.tostring(l,1);Lua.settop(l,0);
		#if sys try { final p=_dataPath(k); if(sys.FileSystem.exists(p)) sys.FileSystem.deleteFile(p); } catch(_) {} #end return 0;
	}

	// ── JSON ──────────────────────────────────────────────────────────────────

	static function _fnJsonEnc(l:Dynamic):Int
	{
		final v=_read(l,1);Lua.settop(l,0);
		try Lua.pushstring(l, haxe.Json.stringify(v)) catch(_) Lua.pushstring(l,'{}'); return 1;
	}
	static function _fnJsonDec(l:Dynamic):Int
	{
		final s=Lua.tostring(l,1);Lua.settop(l,0);
		try _push(l, haxe.Json.parse(s)) catch(_) Lua.pushnil(l); return 1;
	}

	// ── Strings / Tablas ──────────────────────────────────────────────────────

	static function _fnStrSplit(l:Dynamic):Int
	{
		final s=Lua.tostring(l,1);final sep=Lua.tostring(l,2);Lua.settop(l,0);
		final parts=s.split(sep);
		Lua.newtable(l);
		for(i in 0...parts.length){Lua.pushnumber(l,i+1);Lua.pushstring(l,parts[i]);Lua.settable(l,-3);}
		return 1;
	}
	static function _fnStrContains(l:Dynamic):Int { final s=Lua.tostring(l,1);final sub=Lua.tostring(l,2);Lua.settop(l,0); Lua.pushboolean(l,s.indexOf(sub)>=0); return 1; }
	static function _fnStrTrim(l:Dynamic):Int     { final s=Lua.tostring(l,1);Lua.settop(l,0); Lua.pushstring(l,StringTools.trim(s)); return 1; }
	static function _fnStrReplace(l:Dynamic):Int  { final s=Lua.tostring(l,1);final f=Lua.tostring(l,2);final r=Lua.tostring(l,3);Lua.settop(l,0); Lua.pushstring(l,StringTools.replace(s,f,r)); return 1; }
	static function _fnTableLen(l:Dynamic):Int
	{
		if(Lua.type(l,1)!=5){Lua.settop(l,0);Lua.pushnumber(l,0);return 1;}
		var count=0; Lua.pushnil(l);
		while(Lua.next(l,-2)!=0){count++;Lua.pop(l,1);}
		Lua.settop(l,0); Lua.pushnumber(l,count); return 1;
	}

	// ── Input extendido ───────────────────────────────────────────────────────

	static function _fnPadP(l:Dynamic):Int    { final id=Std.int(Lua.tonumber(l,1));final b=Std.int(Lua.tonumber(l,2));Lua.settop(l,0); try{final gp=flixel.FlxG.gamepads.getByID(id);Lua.pushboolean(l,gp!=null&&Reflect.callMethod(gp.pressed, Reflect.field(gp.pressed, "check"), [b]) == true);}catch(_)Lua.pushboolean(l,false); return 1; }
	static function _fnPadJP(l:Dynamic):Int   { final id=Std.int(Lua.tonumber(l,1));final b=Std.int(Lua.tonumber(l,2));Lua.settop(l,0); try{final gp=flixel.FlxG.gamepads.getByID(id);Lua.pushboolean(l,gp!=null&&Reflect.callMethod(gp.justPressed, Reflect.field(gp.justPressed, "check"), [b]) == true);}catch(_)Lua.pushboolean(l,false); return 1; }
	static function _fnMouseRP(l:Dynamic):Int  { Lua.pushboolean(l, flixel.FlxG.mouse.pressedRight); return 1; }
	static function _fnMouseRJP(l:Dynamic):Int { Lua.pushboolean(l, flixel.FlxG.mouse.justPressedRight); return 1; }

	// ── Note splash / hold ────────────────────────────────────────────────────

	static function _fnNoteSplash(l:Dynamic):Int
	{
		final dir=Std.int(Lua.tonumber(l,1));Lua.settop(l,0);final p=_ps();
		if(p!=null) try Reflect.callMethod(p,Reflect.field(p,'spawnSplash'),[dir]) catch(_) {}; return 0;
	}
	static function _fnHoldActive(l:Dynamic):Int
	{
		final n=resolve(Std.int(Lua.tonumber(l,1)));Lua.settop(l,0);
		Lua.pushboolean(l, n!=null ? try n.isSustainNote catch(_) false : false); return 1;
	}

	// ── Transiciones ─────────────────────────────────────────────────────────

	static function _fnFadeIn(l:Dynamic):Int
	{
		final dur=Lua.gettop(l)>0?Lua.tonumber(l,1):0.5;final col=Lua.gettop(l)>1?Lua.tostring(l,2):'BLACK';Lua.settop(l,0);
		flixel.FlxG.camera.fade(flixel.util.FlxColor.fromString(col),dur,true); return 0;
	}
	static function _fnFadeOut(l:Dynamic):Int
	{
		final dur=Lua.gettop(l)>0?Lua.tonumber(l,1):0.5;final col=Lua.gettop(l)>1?Lua.tostring(l,2):'BLACK';Lua.settop(l,0);
		flixel.FlxG.camera.fade(flixel.util.FlxColor.fromString(col),dur,false); return 0;
	}

	// ── Subtítulos ─────────────────────────────────────────────────────────────
	//
	//  showSubtitle(text, ?duration, ?optsTable)
	//    showSubtitle("Hello", 3.0)
	//    showSubtitle("Hello", 2.0, { size=28, color=0xFFFF00, bgAlpha=0.7,
	//                                 align="center", bold=true, font="vcr.ttf",
	//                                 bgColor=0x000000, fadeIn=0.2, fadeOut=0.3,
	//                                 y=620, padX=16, padY=10 })

	static function _fnSubShow(l:Dynamic):Int
	{
		final n    = Lua.gettop(l);
		final text = n > 0 ? (Lua.tostring(l, 1) ?? '') : '';
		final dur  = n > 1 ? Lua.tonumber(l, 2) : 3.0;

		// Leer tabla de opciones (arg 3 si es tabla Lua tipo 5)
		var opts:Dynamic = null;
		if (n > 2 && Lua.type(l, 3) == 5)
			opts = _luaTableToOpts(l, 3);

		Lua.settop(l, 0);
		funkin.ui.SubtitleManager.instance.show(text, dur, opts);
		return 0;
	}

	static function _fnSubHide(l:Dynamic):Int
	{
		final instant = Lua.gettop(l) > 0 && Lua.toboolean(l, 1);
		Lua.settop(l, 0);
		funkin.ui.SubtitleManager.instance.hide(instant);
		return 0;
	}

	static function _fnSubClear(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		funkin.ui.SubtitleManager.instance.clear();
		return 0;
	}

	/**
	 * queueSubtitle(entries_table)
	 * entries_table es un array Lua de tablas:
	 *   { { text="Line 1", duration=2.0 }, { text="Line 2", duration=1.5 } }
	 * Cada entrada puede tener además cualquier campo de estilo (size, color, etc.).
	 */
	static function _fnSubQueue(l:Dynamic):Int
	{
		final entries:Array<Dynamic> = [];
		if (Lua.type(l, 1) == 5)
		{
			var i = 1;
			while (true)
			{
				Lua.pushnumber(l, i);
				Lua.gettable(l, 1);
				if (Lua.type(l, -1) != 5) { Lua.pop(l, 1); break; }

				// Leer campos de la entrada
				final entry:Dynamic = _luaTableToOpts(l, Lua.gettop(l));
				entries.push(entry);
				Lua.pop(l, 1);
				i++;
			}
		}
		Lua.settop(l, 0);
		if (entries.length > 0)
			funkin.ui.SubtitleManager.instance.queue(entries);
		return 0;
	}

	static function _fnSubStyle(l:Dynamic):Int
	{
		var opts:Dynamic = null;
		if (Lua.gettop(l) > 0 && Lua.type(l, 1) == 5)
			opts = _luaTableToOpts(l, 1);
		Lua.settop(l, 0);
		if (opts != null) funkin.ui.SubtitleManager.instance.setStyle(opts);
		return 0;
	}

	static function _fnSubReset(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		funkin.ui.SubtitleManager.instance.resetStyle();
		return 0;
	}

	/**
	 * Lee una tabla Lua en el índice dado y devuelve un objeto Dynamic
	 * con sus campos string/number/bool. Útil para opciones de subtítulo.
	 * Solo lee claves string (ignorando índices numéricos del array).
	 */
	static function _luaTableToOpts(l:Dynamic, idx:Int):Dynamic
	{
		final opts:Dynamic = {};
		// Iterar claves string de la tabla
		Lua.pushnil(l); // primera clave
		while (Lua.next(l, idx) != 0)
		{
			// stack: ..., clave, valor
			final keyType = Lua.type(l, -2);
			if (keyType == 4) // string key
			{
				final key = Lua.tostring(l, -2);
				final valType = Lua.type(l, -1);
				if (valType == 1)      Reflect.setField(opts, key, Lua.toboolean(l, -1));
				else if (valType == 3) Reflect.setField(opts, key, Lua.tonumber(l, -1));
				else if (valType == 4) Reflect.setField(opts, key, Lua.tostring(l, -1));
			}
			Lua.pop(l, 1); // quitar valor, conservar clave para siguiente next()
		}
		return opts;
	}

	// ── forEachNote helper (necesita acceso a _lua de la instancia) ───────────
	// NOTA: _sCurrentLua se establece antes de llamar a forEachNote desde call()

	static var _sCurrentLua:Dynamic = null;



	static inline function _ps():Dynamic return funkin.gameplay.PlayState.instance;

	static function _char(who:String):Dynamic
	{
		final p = _ps(); if (p == null) return null;
		return switch who.toLowerCase() {
			case 'bf'|'boyfriend'|'player': try p.boyfriend catch(_) null;
			case 'dad'|'opponent':          try p.dad catch(_) null;
			case 'gf'|'girlfriend':         try p.gf  catch(_) null;
			default: null;
		};
	}

	static function _resolvePath(path:String, root:Dynamic):Dynamic
	{
		if (root == null) return null;
		var o = root;
		for (p in path.split('.')) o = Reflect.getProperty(o, p);
		return o;
	}

	static function _applyPath(path:String, v:Dynamic, root:Dynamic):Void
	{
		if (root == null) return;
		final parts = path.split('.');
		var o = root;
		for (i in 0...parts.length - 1) o = Reflect.getProperty(o, parts[i]);
		Reflect.setProperty(o, parts[parts.length - 1], v);
	}

	static function _key(n:String):Null<flixel.input.keyboard.FlxKey>
	{
		try return flixel.input.keyboard.FlxKey.fromString(n.toUpperCase()) catch(_) return null;
	}

	static function _ease(n:String):Float->Float return switch n {
		case 'quadIn':    flixel.tweens.FlxEase.quadIn;
		case 'quadOut':   flixel.tweens.FlxEase.quadOut;
		case 'quadInOut': flixel.tweens.FlxEase.quadInOut;
		case 'cubeIn':    flixel.tweens.FlxEase.cubeIn;
		case 'cubeOut':   flixel.tweens.FlxEase.cubeOut;
		case 'cubeInOut': flixel.tweens.FlxEase.cubeInOut;
		case 'sineIn':    flixel.tweens.FlxEase.sineIn;
		case 'sineOut':   flixel.tweens.FlxEase.sineOut;
		case 'sineInOut': flixel.tweens.FlxEase.sineInOut;
		case 'bounceOut': flixel.tweens.FlxEase.bounceOut;
		case 'bounceIn':  flixel.tweens.FlxEase.bounceIn;
		case 'elasticOut':flixel.tweens.FlxEase.elasticOut;
		case 'backIn':    flixel.tweens.FlxEase.backIn;
		case 'backOut':   flixel.tweens.FlxEase.backOut;
		default:          flixel.tweens.FlxEase.linear;
	};

	static function _push(l:State, v:Dynamic):Void
	{
		if      (v == null)                 Lua.pushnil(l);
		else if (Std.isOfType(v, Bool))     Lua.pushboolean(l, v);
		else if (Std.isOfType(v, Int))      Lua.pushnumber(l, v);
		else if (Std.isOfType(v, Float))    Lua.pushnumber(l, v);
		else if (Std.isOfType(v, String))   Lua.pushstring(l, v);
		else                                Lua.pushnil(l);
	}

	static function _read(l:State, idx:Int):Dynamic
	{
		var t = Lua.type(l, idx);
		if (t == 1)            return (Lua.toboolean(l, idx) : Dynamic);
		if (t == 3)            return (Lua.tonumber(l, idx)  : Dynamic);
		if (t == 4)            return (Lua.tostring(l, idx)  : Dynamic);
		return null;
	}

	static function _pop(l:State):Dynamic { final v = _read(l, -1); Lua.pop(l, 1); return v; }

	#end

	function _error(msg:String):Void
	{
		errored = true; active = false; lastError = msg;
		trace('[LuaScriptInstance] ❌ $msg');
	}
}
