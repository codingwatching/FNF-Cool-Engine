package funkin.gameplay;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.group.FlxGroup;
import funkin.data.MetaData;
import funkin.scripting.ScriptHandler;
import funkin.scripting.HScriptInstance;
import funkin.gameplay.GameState;
import sys.FileSystem;

using StringTools;

/**
	* UIScriptedManager — A UIManager fully controlled by HScript.

	* If the requested script does not exist or fails, the default script is loaded automatically.
	* *
	* ─── API exposed to the script ──────────────────────────────────────────────

	* // Construction

	* 	makeSprite(x, y) → FlxSprite (scrollFactor=0, assigned camHUD)

	* 	makeText(x, y, text, size) → FlxText (scrollFactor=0, assigned camHUD)

	* 	makeBar(x, y, w, h, obj, var, min, max) → FlxBar (RIGHT_TO_LEFT, scrollFactor=0, camHUD)

	* 	uiAdd(obj) → adds to the group and assigns camHUD

	* 	uiRemove(obj) → removes from the group

	* 	screenCenterX(obj)

	* 	screenCenterY(obj)

	* // Manual pool (replicates UIManager.getFromPool)

	* // _getFromPool(array) is used directly in the script with makeSprite+uiAdd

	* // Available classes in the script

	* 	HealthIcon, ScoreManager, FlxMath, StringTools

	* 	PIXEL_ZOOM, BORDER_OUTLINE, BORDER_SHADOW, BORDER_NONE

	* // Context references

	* 	camHUD, gameState, uiGroup, metaData

	* ─── Callbacks from the script ──────────────────────── ───────────────────────── 
	* 	onCreate() 
	* 	onUpdate(elapsed) 
	* 	onBeatHit(beat) 
	* 	onStepHit(step) 
	* 	onRatingPopup(ratingName, combo) 
	* 	onMissPopup() 
	* 	onScoreUpdate(score, misses, accuracy) ← optional, script can ignore it 
	* 	onHealthUpdate(health, percent) ← optional 
	* 	onIconsSet(p1, p2) 
	* 	onStageSet(stage) 
	* 	onDestroy()
 */
class UIScriptedManager extends FlxGroup
{
	// ─── Script ─────────────────────────────────────────────────────────────
	private var uiScript:HScriptInstance;
	#if (LUA_ALLOWED && linc_luajit)
	private var uiLuaScript:Null<funkin.scripting.RuleScriptInstance> = null;
	#end

	// ─── Arrays reutilizables para callbacks del script (evitan alloc/frame) ─
	static final _argUpdate:Array<Dynamic> = [0.0];
	static final _argBeat:Array<Dynamic> = [0];
	static final _argStep:Array<Dynamic> = [0];
	static final _argTwo:Array<Dynamic> = [null, null];
	static final _argOne:Array<Dynamic> = [null];
	static final _argEmpty:Array<Dynamic> = [];

	// ─── Referencias ────────────────────────────────────────────────────────
	private var camHUD:FlxCamera;
	private var gameState:GameState;
	private var metaData:MetaData;

	// ─── Constructor ────────────────────────────────────────────────────────

	public function new(camHUD:FlxCamera, gameState:GameState, metaData:MetaData)
	{
		super();

		this.camHUD = camHUD;
		this.gameState = gameState;
		this.metaData = metaData;

		loadUIScript(metaData.ui);
	}

	// ─── Carga del script ────────────────────────────────────────────────────

	private function loadUIScript(name:String):Void
	{
		// Buscar en el mod activo primero, luego en assets/.
		// Soporta .hx y .lua (.lua tiene prioridad si existe):
		//   mods/{mod}/data/ui/{name}/script.lua|hx
		//   assets/data/ui/{name}/script.lua|hx
		var path:String = null;
		var isLua:Bool = false;

		#if (LUA_ALLOWED && linc_luajit && sys)
		if (mods.ModManager.isActive())
		{
			final modRoot = mods.ModManager.modRoot();
			for (candidate in [
				'$modRoot/data/ui/$name/script.lua',
				'$modRoot/data/ui/$name/script.hx',
				'$modRoot/assets/data/ui/$name/script.lua',
				'$modRoot/assets/data/ui/$name/script.hx'
			])
			{
				if (FileSystem.exists(candidate))
				{
					path = candidate;
					isLua = candidate.endsWith('.lua');
					break;
				}
			}
		}
		#elseif sys
		if (mods.ModManager.isActive())
		{
			final modRoot = mods.ModManager.modRoot();
			for (candidate in ['$modRoot/data/ui/$name/script.hx', '$modRoot/assets/data/ui/$name/script.hx'])
			{
				if (FileSystem.exists(candidate))
				{
					path = candidate;
					break;
				}
			}
		}
		#end

		if (path == null)
		{
			#if (LUA_ALLOWED && linc_luajit && sys)
			for (candidate in ['assets/data/ui/$name/script.lua', 'assets/data/ui/$name/script.hx'])
				if (FileSystem.exists(candidate))
				{
					path = candidate;
					isLua = candidate.endsWith('.lua');
					break;
				}
			#elseif sys
			final assetPath = 'assets/data/ui/$name/script.hx';
			if (FileSystem.exists(assetPath))
				path = assetPath;
			#end
		}

		if (path == null)
		{
			if (name != 'default')
			{
				trace('[UIScriptedManager] "$name" not found, cargando default...');
				loadUIScript('default');
			}
			else
			{
				trace('[UIScriptedManager] ERROR: UI script "default" no existe. HUD vacío.');
			}
			return;
		}

		trace('[UIScriptedManager] Cargando UI script desde: $path (lua=$isLua)');
		#if (LUA_ALLOWED && linc_luajit)
		if (isLua)
		{
			// Cargar como RuleScript (Lua) — exponer API vía variables globales
			uiLuaScript = new funkin.scripting.RuleScriptInstance('ui_$name', path);
			uiLuaScript.loadFile(path);
			if (!uiLuaScript.active)
			{
				trace('[UIScriptedManager] Error en Lua UI "$name", cargando default...');
				uiLuaScript.destroy();
				uiLuaScript = null;
				if (name != 'default')
					loadUIScript('default');
				return;
			}
			exposeUIAPILua();
			uiLuaScript.call('onCreate', []);
			trace('[UIScriptedManager] Lua UI activo: "$name"');
			return;
		}
		#end
		// ── HScript path ─────────────────────────────────────────────────────
		// BUGFIX: ScriptHandler.loadScript() llama onCreate() automáticamente ANTES
		// de que exposeUIAPI() haya inyectado makeSprite/makeBar/uiAdd/etc.
		// Solución: cargar SIN auto-onCreate, exponer API y llamar nosotros.
		uiScript = ScriptHandler.loadScriptNoInit(path, 'ui');

		if (uiScript == null)
		{
			trace('[UIScriptedManager] Error al parsear script "$name", cargando default...');
			if (name != 'default')
				loadUIScript('default');
			return;
		}

		exposeUIAPI();
		uiScript.call('onCreate', []);
		trace('[UIScriptedManager] HScript UI activo: "$name" (desde $path)');
	}

	// ─── API expuesta al script ──────────────────────────────────────────────

	private function exposeUIAPI():Void
	{
		if (uiScript == null)
			return;

		var self = this;

		// ── Referencias de contexto ────────────────────────────────────────
		uiScript.set('camHUD', camHUD);
		uiScript.set('gameState', gameState);
		uiScript.set('uiGroup', this);
		uiScript.set('metaData', metaData);
		uiScript.set('SONG', PlayState.SONG);

		var skinData = funkin.gameplay.notes.NoteSkinSystem.getCurrentSkinData();

		uiScript.set('isPixel', skinData.isPixel);

		// ── Duración total de la canción en ms ─────────────────────────────
		// IMPORTANTE: UIScriptedManager se construye ANTES de que PlayState llame
		// a Conductor.mapBPMChanges(), así que Conductor.bpmChangeMap está vacío
		// aquí → Conductor.getTimeAtStep() usa solo el BPM base y da un resultado
		// incorrecto para canciones con cambios de BPM.
		// Solución: replicar la misma suma que hace mapBPMChanges internamente,
		// iterando sección a sección con el BPM vigente en cada momento.
		var _songLenMs:Float = 0.0;
		final _song = PlayState.SONG;
		if (_song != null && _song.notes != null && _song.bpm > 0)
		{
			var _curBpm:Float = _song.bpm;
			for (section in _song.notes)
			{
				if (section.changeBPM && section.bpm > 0)
					_curBpm = section.bpm;
				// stepCrochet = 60000 / bpm / 4
				_songLenMs += section.lengthInSteps * (60000.0 / _curBpm / 4.0);
			}
		}
		uiScript.set('SONG_LENGTH_MS', _songLenMs);

		// ── Clases que el script necesita para replicar UIManager ──────────

		// HealthIcon — para new HealthIcon(name, isPlayer)
		uiScript.set('HealthIcon', funkin.gameplay.objects.character.HealthIcon);

		// ScoreManager — para scoreManager.getHUDText(gameState)
		uiScript.set('ScoreManager', funkin.gameplay.objects.hud.ScoreManager);

		// FlxMath — para remapToRange y lerp
		uiScript.set('FlxMath', flixel.math.FlxMath);

		// StringTools — para StringTools.startsWith(curStage, 'school')
		uiScript.set('StringTools', StringTools);

		// PlayStateConfig.PIXEL_ZOOM expuesto como constante directa
		uiScript.set('PIXEL_ZOOM', funkin.gameplay.PlayStateConfig.PIXEL_ZOOM);

		// setBorderStyle wrapper — HScript no puede pasar enums nativos de Haxe directamente.
		// En vez de exponer las constantes (que llegan como Int y crashean en applyBorderStyle),
		// exponemos una función que llama a setBorderStyle con el enum correcto desde Haxe.
		uiScript.set('setTextBorder', function(txt:flixel.text.FlxText, style:String, color:flixel.util.FlxColor, ?size:Float = 1, ?quality:Float = 1):Void
		{
			var s = switch (style.toLowerCase())
			{
				case 'outline': flixel.text.FlxText.FlxTextBorderStyle.OUTLINE;
				case 'outline_fast': flixel.text.FlxText.FlxTextBorderStyle.OUTLINE_FAST;
				case 'shadow': flixel.text.FlxText.FlxTextBorderStyle.SHADOW;
				default: flixel.text.FlxText.FlxTextBorderStyle.NONE;
			};
			txt.setBorderStyle(s, color, size, quality);
		});

		// ── Helpers de creación (scrollFactor=0 y camHUD ya asignados) ─────

		uiScript.set('makeSprite', function(?x:Float = 0, ?y:Float = 0):flixel.FlxSprite
		{
			var spr = new flixel.FlxSprite(x, y);
			spr.scrollFactor.set();
			spr.cameras = [camHUD];
			return spr;
		});

		uiScript.set('makeText', function(?x:Float = 0, ?y:Float = 0, ?text:String = '', ?size:Int = 20):flixel.text.FlxText
		{
			var t = new flixel.text.FlxText(x, y, 0, text, size);
			t.scrollFactor.set();
			t.cameras = [camHUD];
			return t;
		});

		// makeBar siempre RIGHT_TO_LEFT (único caso de uso = health bar)
		uiScript.set('makeBar', function(x:Float, y:Float, w:Int, h:Int, obj:Dynamic, varName:String, min:Float, max:Float):flixel.ui.FlxBar
		{
			var bar = new flixel.ui.FlxBar(x, y, flixel.ui.FlxBar.FlxBarFillDirection.RIGHT_TO_LEFT, w, h, obj, varName, min, max);
			bar.scrollFactor.set();
			bar.cameras = [camHUD];
			return bar;
		});

		// ── uiAdd / uiRemove ───────────────────────────────────────────────

		// uiAdd: añade el objeto al grupo Y le asigna camHUD si es FlxObject
		uiScript.set('uiAdd', function(obj:flixel.FlxBasic):flixel.FlxBasic
		{
			if (Std.isOfType(obj, flixel.FlxObject))
				cast(obj, flixel.FlxObject).cameras = [camHUD];
			self.add(obj);
			return obj;
		});

		// uiRemove: elimina del grupo (true = eliminar de memoria del grupo)
		uiScript.set('uiRemove', function(obj:flixel.FlxBasic):Void
		{
			self.remove(obj, true);
		});

		// ── Utilidades ─────────────────────────────────────────────────────

		uiScript.set('screenCenterX', function(spr:flixel.FlxObject):Void spr.screenCenter(flixel.util.FlxAxes.X));

		uiScript.set('screenCenterY', function(spr:flixel.FlxObject):Void spr.screenCenter(flixel.util.FlxAxes.Y));
	}

	// ─── API expuesta al script Lua ─────────────────────────────────────────
	#if (LUA_ALLOWED && linc_luajit)
	private function exposeUIAPILua():Void
	{
		if (uiLuaScript == null)
			return;
		final self = this;
		final cam = camHUD;
		// Contexto
		uiLuaScript.set('camHUD', camHUD);
		uiLuaScript.set('gameState', gameState);
		uiLuaScript.set('uiGroup', this);
		uiLuaScript.set('metaData', metaData);
		uiLuaScript.set('SONG', funkin.gameplay.PlayState.SONG);
		uiLuaScript.set('isPixel', funkin.gameplay.notes.NoteSkinSystem.getCurrentSkinData()?.isPixel ?? false);
		uiLuaScript.set('PIXEL_ZOOM', funkin.gameplay.PlayStateConfig.PIXEL_ZOOM);
		uiLuaScript.set('HealthIcon', funkin.gameplay.objects.character.HealthIcon);
		uiLuaScript.set('ScoreManager', funkin.gameplay.objects.hud.ScoreManager);
		uiLuaScript.set('FlxMath', flixel.math.FlxMath);
		// Duración de canción
		var _songLenMs:Float = 0.0;
		final _song = funkin.gameplay.PlayState.SONG;
		if (_song != null && _song.notes != null && _song.bpm > 0)
		{
			var _curBpm:Float = _song.bpm;
			for (section in _song.notes)
			{
				if (section.changeBPM && section.bpm > 0)
					_curBpm = section.bpm;
				_songLenMs += section.lengthInSteps * (60000.0 / _curBpm / 4.0);
			}
		}
		uiLuaScript.set('SONG_LENGTH_MS', _songLenMs);
		// Helpers de creación
		uiLuaScript.set('makeSprite', function(?x:Float = 0, ?y:Float = 0):flixel.FlxSprite
		{
			var s = new flixel.FlxSprite(x, y);
			s.scrollFactor.set();
			s.cameras = [cam];
			return s;
		});
		uiLuaScript.set('makeText', function(?x:Float = 0, ?y:Float = 0, ?txt:String = '', ?sz:Int = 20):flixel.text.FlxText
		{
			var t = new flixel.text.FlxText(x, y, 0, txt, sz);
			t.scrollFactor.set();
			t.cameras = [cam];
			return t;
		});
		uiLuaScript.set('uiAdd', function(obj:flixel.FlxBasic):flixel.FlxBasic
		{
			if (Std.isOfType(obj, flixel.FlxObject))
				cast(obj, flixel.FlxObject).cameras = [cam];
			self.add(obj);
			return obj;
		});
		uiLuaScript.set('uiRemove', function(obj:flixel.FlxBasic):Void
		{
			self.remove(obj, true);
		});
		uiLuaScript.set('screenCenterX', function(spr:flixel.FlxObject):Void spr.screenCenter(flixel.util.FlxAxes.X));
		uiLuaScript.set('screenCenterY', function(spr:flixel.FlxObject):Void spr.screenCenter(flixel.util.FlxAxes.Y));
	}
	#end

	// ─── Ciclo de vida ───────────────────────────────────────────────────────

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		_argUpdate[0] = elapsed;
		uiScript?.call('onUpdate', _argUpdate);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onUpdate', _argUpdate);
		#end
	}

	// ─── Callbacks del juego → script ────────────────────────────────────────

	public function onBeatHit(beat:Int):Void
	{
		_argBeat[0] = beat;
		uiScript?.call('onBeatHit', _argBeat);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onBeatHit', _argBeat);
		#end
	}

	public function onStepHit(step:Int):Void
	{
		_argStep[0] = step;
		uiScript?.call('onStepHit', _argStep);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onStepHit', _argStep);
		#end
	}

	public function showRatingPopup(ratingName:String, combo:Int):Void
	{
		if (metaData.hideRatings)
			return;
		_argTwo[0] = ratingName;
		_argTwo[1] = combo;
		uiScript?.call('onRatingPopup', _argTwo);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onRatingPopup', _argTwo);
		#end
	}

	public function showMissPopup():Void
	{
		uiScript?.call('onMissPopup', _argEmpty);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onMissPopup', _argEmpty);
		#end
	}

	public function setIcons(p1:String, p2:String):Void
	{
		_argTwo[0] = p1;
		_argTwo[1] = p2;
		uiScript?.call('onIconsSet', _argTwo);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onIconsSet', _argTwo);
		#end
	}

	public function setStage(stage:String):Void
	{
		_argOne[0] = stage;
		uiScript?.call('onStageSet', _argOne);
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onStageSet', _argOne);
		#end
	}

	// ─── Acceso a iconos (compatibilidad con PlayState) ───────────────────────
	// PlayState puede leer iconP1/iconP2 si el script los expone como variables.
	public var iconP1(get, null):funkin.gameplay.objects.character.HealthIcon;

	function get_iconP1():funkin.gameplay.objects.character.HealthIcon
		return uiScript?.get('iconP1');

	public var iconP2(get, null):funkin.gameplay.objects.character.HealthIcon;

	function get_iconP2():funkin.gameplay.objects.character.HealthIcon
		return uiScript?.get('iconP2');

	// ─── Destrucción ─────────────────────────────────────────────────────────

	override function destroy():Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		uiLuaScript?.call('onDestroy', _argEmpty);
		uiLuaScript?.destroy();
		uiLuaScript = null;
		#end
		uiScript?.call('onDestroy', _argEmpty);
		uiScript?.destroy();
		uiScript = null;
		super.destroy();
	}
}
