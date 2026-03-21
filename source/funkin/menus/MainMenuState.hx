package funkin.menus;

#if desktop
import data.Discord.DiscordClient;
#end
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import funkin.transitions.StateTransition;
import flixel.effects.FlxFlicker;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.transitions.StickerTransition;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import lime.app.Application;
import funkin.menus.OptionsMenuState;
import openfl.display.BitmapData as Bitmap;
import data.PlayerSettings;
import funkin.scripting.StateScriptHandler;
import funkin.audio.MusicManager;

using StringTools;

class MainMenuState extends funkin.states.MusicBeatState
{
	var curSelected:Int = 0;

	var menuItems:FlxTypedGroup<FlxSprite>;

	var optionShit:Array<String> = ['storymode', 'freeplay', 'options', 'credits'];

	var canSnap:Array<Float> = [];

	var camFollow:FlxObject;
	var newInput:Bool = true;
	var menuItem:FlxSprite;

	public static var firstStart:Bool = true;

	public static var finishedFunnyMove:Bool = false;

	override function create()
	{
		funkin.system.CursorManager.hide();
		// LOAD CUZ THIS SHIT DONT DO IT SOME IN THE CACHESTATE.HX FUCK
		PlayerSettings.player1.controls.loadKeyBinds();

		if (StickerTransition.enabled)
		{
			transIn = null;
			transOut = null;
		}

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menu", null);
		#end

		#if !MAINMENU
		// MusicManager solo llama playMusic si freakyMenu no está ya sonando
		MusicManager.play('freakyMenu', 0.7);
		#end

		persistentUpdate = persistentDraw = true;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Bitmap.fromFile(Paths.image('menu/menuBG')));
		bg.scrollFactor.x = 0;
		bg.scrollFactor.y = 0.18;
		// Escalar el fondo para cubrir siempre el ancho completo (fix 1080p)
		var bgScale:Float = Math.max(FlxG.width / bg.width, FlxG.height / bg.height) * 1.1;
		bg.scale.set(bgScale, bgScale);
		bg.updateHitbox();
		bg.screenCenter();
		bg.antialiasing = FlxG.save.data.antialiasing;
		add(bg);

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);
		FlxG.camera.follow(camFollow, LOCKON, 0.06);
		FlxG.camera.snapToTarget();

		menuItems = new FlxTypedGroup<FlxSprite>();
		add(menuItems);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('MainMenuState', this);
		StateScriptHandler.callOnScripts('onCreate', []);

		// Obtener items custom
		var customItems = StateScriptHandler.callOnScriptsReturn('getCustomMenuItems', [], null);
		if (customItems != null && Std.isOfType(customItems, Array))
		{
			var itemsArray:Array<String> = cast customItems;
			for (item in itemsArray)
				optionShit.push(item);
		}
		#end

		for (i in 0...optionShit.length)
		{
			var offset:Float = 108 - (Math.max(optionShit.length, 4) - 4) * 80;
			var menuItem:FlxSprite = new FlxSprite(70, (i * 140) + offset);
			menuItem.frames = Paths.getSparrowAtlas('menu/mainmenu/' + optionShit[i]);
			menuItem.animation.addByPrefix('idle', optionShit[i] + " idle", 24);
			menuItem.animation.addByPrefix('selected', optionShit[i] + " selected", 24);
			menuItem.animation.play('idle');
			menuItem.ID = i;
			// menuItem.screenCenter(X);
			menuItems.add(menuItem);
			var scr:Float = (optionShit.length - 4) * 0.135;
			if (optionShit.length < 6)
				scr = 0;
			menuItem.scrollFactor.set(0, scr);
			menuItem.antialiasing = FlxG.save.data.antialiasing;
			menuItem.setGraphicSize(Std.int(menuItem.width * 0.8));
			menuItem.updateHitbox();
		}

		#if mobileC
		// En móvil: texto "[ MODS ]" tappable en lugar de "Press Shift"
		var modShit:FlxText = new FlxText(5, FlxG.height - 19, 0, '[ MODS ]', 12);
		#else
		var modShit:FlxText = new FlxText(5, FlxG.height - 19, 0, 'Press Shift - Menu Mods - API v0.4.0B', 12);
		#end
		modShit.scrollFactor.set();
		modShit.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		modShit.antialiasing = FlxG.save.data.antialiasing;
		modShit.y -= 40;
		add(modShit);

		var versionShit:FlxText = new FlxText(5, FlxG.height - 19, 0, "Friday Night Funkin v0.3.1", 12);
		versionShit.scrollFactor.set();
		versionShit.antialiasing = FlxG.save.data.antialiasing;
		versionShit.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(versionShit);

		var versionShit2:FlxText = new FlxText(5, FlxG.height - 19, 0, 'Cool Engine - v${Application.current.meta.get('version')}', 12);
		versionShit2.scrollFactor.set();
		versionShit2.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		versionShit2.y -= 20;
		versionShit2.antialiasing = FlxG.save.data.antialiasing;
		add(versionShit2);

		// Etiqueta del mod activo — solo visible si hay uno cargado
		final _activeMod = mods.ModManager.activeMod;
		if (_activeMod != null)
		{
			final _modInfo = mods.ModManager.getInfo(_activeMod);
			final _modLabel = _modInfo != null ? _modInfo.name : _activeMod;
			final _modVer = _modInfo != null ? ' v${_modInfo.version}' : '';
			final _modColor:flixel.util.FlxColor = _modInfo != null ? new flixel.util.FlxColor(_modInfo.color | 0xFF000000) : FlxColor.fromRGB(255, 170, 0);

			var modActiveText:FlxText = new FlxText(FlxG.width - 270, FlxG.height - 19, 0, '\u25B6 MOD: $_modLabel$_modVer', 16);
			modActiveText.scrollFactor.set();
			modActiveText.setFormat("VCR OSD Mono", 16, _modColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			modActiveText.antialiasing = FlxG.save.data.antialiasing;
			add(modActiveText);
		}

		changeItem();

		#if mobileC
		addVirtualPad(UP_DOWN, A_B);
		#end

		StickerTransition.clearStickers();

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('postCreate', []);
		#end

		super.create();
	}

	var selectedSomethin:Bool = false;

	/** Developer Mode — da acceso a los editores (Chart, Stage, Dialogue, AnimDebug).
	 *  Se almacena en mod.json del mod activo como "developerMode": true/false.
	 *  Si no hay mod activo o el campo no existe, cae al save.data como fallback.
	 *  Por defecto es TRUE. */
	public static var developerMode(get, set):Bool;

	static function get_developerMode():Bool
	{
		// Leer desde mod.json del mod activo (si hay uno)
		final info = mods.ModManager.activeInfo();
		if (info != null)
			return info.developerMode != false; // null/true → true, false → false
		// Fallback al save para el modo base (sin mod activo)
		if (FlxG.save.data.developerMode == null)
			return true; // default TRUE
		return FlxG.save.data.developerMode == true;
	}

	static function set_developerMode(v:Bool):Bool
	{
		final info = mods.ModManager.activeInfo();
		if (info != null)
		{
			// Guardar en mod.json
			info.developerMode = v;
			mods.ModManager.saveModInfo(info);
		}
		else
		{
			// Modo base: guardar en save.data
			FlxG.save.data.developerMode = v;
			FlxG.save.flush();
		}
		return v;
	}

	override function update(elapsed:Float)
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		// El volumen de la música de menú lo gestiona CoreAudio._applyAll() cada frame.
		// No manipular FlxG.sound.music.volume aquí — pelea con el sistema de volumen.

		// ── Teclas de editor (solo en developer mode) ──────────────────────────
		if (developerMode)
		{
			if (FlxG.keys.justPressed.ONE)
				StateTransition.switchState(new funkin.debug.EditorHubState());
		}

		// ── Mod Selector ────────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.SHIFT)
			StateTransition.switchState(new ModSelectorState());
		#if mobileC
		// Tap en la zona del texto "[ MODS ]" (esquina inferior izquierda)
		for (touch in FlxG.touches.justStarted())
			if (touch.screenX < 130 && touch.screenY > FlxG.height - 60)
				StateTransition.switchState(new ModSelectorState());
		#end

		if (!selectedSomethin)
		{
			if (controls.UP_P)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				changeItem(-1);
			}

			if (controls.DOWN_P)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				changeItem(1);
			}

			if (controls.BACK)
			{
				StateTransition.switchState(new TitleState());
			}

			if (controls.ACCEPT)
			{
				#if HSCRIPT_ALLOWED
				var cancelled = StateScriptHandler.callOnScriptsReturn('onAccept', [], false);
				if (cancelled)
				{
					super.update(elapsed);
					return;
				}
				StateScriptHandler.callOnScripts('onMenuItemSelected', [optionShit[curSelected], curSelected]);
				#end

				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
				if (FlxG.save.data.flashing)
					FlxG.camera.flash(FlxColor.WHITE);

				menuItems.forEach(function(spr:FlxSprite)
				{
					if (curSelected != spr.ID)
					{
						FlxTween.tween(spr, {alpha: 0}, 0.4, {
							ease: FlxEase.quadOut,
							onComplete: function(twn:FlxTween)
							{
								spr.kill();
							}
						});
					}
					else
					{
						menuItems.forEach(function(spr:FlxSprite)
						{
							FlxFlicker.flicker(spr, 1, 0.06, false, false, function(flick:FlxFlicker)
							{
								var daChoice:String = optionShit[curSelected];

								switch (daChoice)
								{
									case 'storymode':
										StateTransition.switchState(new StoryMenuState());
									case 'freeplay':
										StateTransition.switchState(new FreeplayState());
									case 'options':
										StateTransition.switchState(new OptionsMenuState());
									case 'credits':
										StateTransition.switchState(new CreditsState());
								}
							});
						});
					}
				});
			}
		}

		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	function changeItem(huh:Int = 0)
	{
		curSelected += huh;

		if (curSelected >= menuItems.length)
			curSelected = 0;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;

		menuItems.forEach(function(spr:FlxSprite)
		{
			spr.animation.play('idle');
			spr.offset.y = 0;
			spr.updateHitbox();

			if (spr.ID == curSelected)
			{
				spr.animation.play('selected');
				camFollow.setPosition(spr.getGraphicMidpoint().x, spr.getGraphicMidpoint().y);
				spr.offset.x = 0.15 * (spr.frameWidth / 2 + 180);
				spr.offset.y = 0.15 * spr.frameHeight;
			}
		});

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSelectionChanged', [curSelected]);
		#end
	}

	override function destroy()
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end

		super.destroy();
	}
}