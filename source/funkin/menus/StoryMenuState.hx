package funkin.menus;

import funkin.cutscenes.MP4Handler;
import lime.utils.Assets;
#if desktop
import data.Discord.DiscordClient;
#end
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import funkin.transitions.StickerTransition;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.transitions.StateTransition;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import lime.net.curl.CURLCode;
import funkin.menus.substate.MenuItem;
import funkin.menus.substate.MenuCharacter;
import funkin.gameplay.objects.hud.Highscore;
import funkin.scripting.StateScriptHandler;
import funkin.gameplay.PlayState;
import funkin.states.LoadingState;
import funkin.data.Song;
import funkin.data.WeekFile;
import funkin.data.WeekFile.WeekData;
import funkin.cutscenes.VideoState;

using StringTools;

// Importar JSON
import haxe.Json;
import haxe.format.JsonParser;
import funkin.audio.MusicManager;
#if sys
import sys.FileSystem;
#end



class StoryMenuState extends funkin.states.MusicBeatState
{
	var scoreText:FlxText;

	// Usar el mismo sistema que FreeplayState
	// songInfo removed — use WeekFile.loadAll() instead

	/** Semanas cargadas desde data/storymenu/weeks/*.json */
	var _loadedWeeks:Array<WeekData> = [];

	var weekData:Array<Dynamic> = [];
	var weekCharacters:Array<Dynamic> = [];
	var weekNames:Array<String> = [];
	var weekPaths:Array<String> = [];
	var weekColors:Array<FlxColor> = [];

	var curDifficulty:Int = 1;

	public static var weekUnlocked:Array<Bool> = [];

	var txtWeekTitle:FlxText;

	public var curWeek:Int = 0;

	/** Tween of transition suave of the color of fondo between weeks. */
	var _bgColorTween:FlxTween = null;

	/** Last week for the that is inició the tween (avoids relanzarlo each frame). */
	var _lastColoredWeek:Int = -1;

	var bg:FlxSprite;

	public var bgcol:FlxColor = 0xFF0A0A0A;

	var txtTracklist:FlxText;

	var grpWeekText:FlxTypedGroup<MenuItem>;
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;

	var grpLocks:FlxTypedGroup<FlxSprite>;

	var difficultySelectors:FlxGroup;
	var sprDifficulty:FlxSprite;
	var leftArrow:FlxSprite;
	var rightArrow:FlxSprite;
	var yellowBG:FlxSprite;
	var tracksMenu:FlxSprite;
	var blackBarThingie:FlxSprite;
	var inverted:FlxSprite;

	// Error message
	var errorText:FlxText;
	var errorTween:FlxTween;

	override function create()
	{
		if (StickerTransition.enabled)
		{
			transIn = null;
			transOut = null;
		}

		MusicManager.play('freakyMenu', 0.7);

		persistentUpdate = persistentDraw = true;

		// === CARGAR DATOS DESDE EL MISMO JSON QUE FREEPLAY ===
		loadSongsData();

		buildWeeksFromJSON();

		scoreText = new FlxText(10, 10, 0, "LEVEL SCORE: 49324858", 36);
		scoreText.setFormat("VCR OSD Mono", 32);

		txtWeekTitle = new FlxText(FlxG.width * 0.7, 10, 0, "", 32);
		txtWeekTitle.setFormat("VCR OSD Mono", 32, FlxColor.WHITE, RIGHT);
		txtWeekTitle.alpha = 0.7;

		var rankText:FlxText = new FlxText(0, 10);
		rankText.text = 'RANK: GREAT';
		rankText.setFormat(Paths.font("vcr.ttf"), 32);
		rankText.size = scoreText.size;
		rankText.screenCenter(X);

		yellowBG = new FlxSprite(0, 56).makeGraphic(FlxG.width, 404, 0xFFFFFFFF);
		inverted = new FlxSprite(0, 56).makeGraphic(FlxG.width, 400, 0xFFF9CF51);

		blackBarThingie = new FlxSprite().makeGraphic(FlxG.width, 56, FlxColor.BLACK);

		// bg always oscuro — the color of the week is applies to yellowBG, no here.
		// critical: Paths.image() always returns String (never null).
		// bg.frames == null tampoco es fiable — HaxeFlixel puede asignar un
		// FlxFramesCollection with bitmap internal nulo without lanzar excepción,
		// it that crashea in FlxDrawQuadsItem::render line 119.
		// The single comprobación safe is verify if the fichero exists.
		bg = new FlxSprite();
		#if sys
		var _bgPath:String = Paths.image('menu/menuDesat');
		if (sys.FileSystem.exists(_bgPath))
		{
			try
			{
				bg.loadGraphic(_bgPath);
			}
			catch (_:Dynamic)
			{
			}
		}
		#end
		if (bg.graphic == null || bg.graphic.bitmap == null)
			bg.makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);
		bg.color = 0xFF0A0A0A;

		// Aplicar color de la semana inicial al yellowBG
		if (weekColors.length > 0)
			yellowBG.color = weekColors[0];

		persistentUpdate = persistentDraw = true;

		grpWeekText = new FlxTypedGroup<MenuItem>();
		add(grpWeekText);

		add(blackBarThingie);

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();

		grpLocks = new FlxTypedGroup<FlxSprite>();
		add(grpLocks);

		trace("Line 70");

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Story Mode", null);
		#end

		// validation: Only create items if there is weeks disponibles
		if (weekData.length > 0)
		{
			for (i in 0...weekData.length)
			{
				var weekThing:MenuItem = new MenuItem(0, yellowBG.y + yellowBG.height + 10, i,
					(weekPaths != null && i < weekPaths.length) ? weekPaths[i] : null);
				weekThing.y += ((weekThing.height + 20) * i);
				weekThing.targetY = i;
				grpWeekText.add(weekThing);

				weekThing.screenCenter(X);
				weekThing.antialiasing = true;
				// weekThing.updateHitbox();

				// Needs an offset thingie
				// CRITICAL: only create the lock if ui_tex exists.
				// lock.frames = null crashea en FlxDrawQuadsItem::render.
				if (i < weekUnlocked.length && !weekUnlocked[i])
				{
					var lock:FlxSprite = new FlxSprite(weekThing.width + 10 + weekThing.x);
					lock.loadGraphic(Paths.image('menu/storymenu/ui/lock'));
					lock.ID = i;
					lock.antialiasing = true;
					grpLocks.add(lock);
				}
			}
		}
		else
		{
			// NUEVO: Mostrar mensaje de error si no hay semanas
			trace("WARNING: No weeks available in Story Mode!");
		}

		trace("Line 96");

		// Inicializar personajes con la primera semana
		var initialChars:Array<String> = ['', 'bf', 'gf'];
		if (weekCharacters.length > 0 && weekCharacters[0] != null)
			initialChars = weekCharacters[0];

		for (char in 0...3)
		{
			var charName:String = char < initialChars.length ? initialChars[char] : '';
			var weekCharacterThing:MenuCharacter = new MenuCharacter((FlxG.width * 0.25) * (1 + char) - 150, charName);
			weekCharacterThing.y += 70;
			weekCharacterThing.antialiasing = true;
			grpWeekCharacters.add(weekCharacterThing);
		}

		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('StoryMenuState', this);
		StateScriptHandler.callOnScripts('onCreate', []);

		// Obtener semanas custom
		var customWeeks = StateScriptHandler.callOnScriptsReturn('getCustomWeeks', [], null);
		if (customWeeks != null && Std.isOfType(customWeeks, Array))
		{
			// Procesar semanas custom
		}
		#end

		difficultySelectors = new FlxGroup();
		add(difficultySelectors);

		trace("Line 124");

		if (grpWeekText.members.length > 0 && grpWeekText.members[0] != null)
		{
			leftArrow = new FlxSprite(grpWeekText.members[0].x + grpWeekText.members[0].width + 10, grpWeekText.members[0].y + 10);
			leftArrow.frames = Paths.getSparrowAtlas('menu/storymenu/ui/arrows');
			leftArrow.animation.addByPrefix('idle', "leftIdle");
			leftArrow.animation.addByPrefix('press', "leftConfirm");
			leftArrow.animation.play('idle');
			difficultySelectors.add(leftArrow);

			// sprDifficulty y rightArrow empiezan en x=0.
			// changeDifficulty() the reposicionará correctly a vez that
			// ambas arrows and the sprite are creados.
			sprDifficulty = new FlxSprite(0, leftArrow.y);
			sprDifficulty.loadGraphic(Paths.image('menu/storymenu/difficulties/easy'));
			difficultySelectors.add(sprDifficulty);

			rightArrow = new FlxSprite(leftArrow.x + 60, leftArrow.y);
			rightArrow.frames = Paths.getSparrowAtlas('menu/storymenu/ui/arrows');
			rightArrow.animation.addByPrefix('idle', 'rightIdle');
			rightArrow.animation.addByPrefix('press', "rightConfirm", 24, false);
			rightArrow.animation.play('idle');
			difficultySelectors.add(rightArrow);

			// Now that all is creado, posicionar correctly.
			changeDifficulty();
		}
		else
		{
			trace("WARNING: grpWeekText is empty, skipping difficulty selectors initialization");
		}

		trace("Line 150");

		add(yellowBG);
		add(grpWeekCharacters);

		// Paths.image() always returns String (never null), so that the check
		// anterior "!= null" era siempre true. Hay que verificar con FileSystem.
		var tracksMenuPath:String = Paths.image('menu/storymenu/tracksMenu');
		tracksMenu = new FlxSprite(FlxG.width * 0.07, yellowBG.y + 435);
		var tracksLoaded:Bool = false;
		#if sys
		if (sys.FileSystem.exists(tracksMenuPath))
		{
			try
			{
				tracksMenu.loadGraphic(tracksMenuPath);
				if (tracksMenu.graphic != null && tracksMenu.graphic.bitmap != null)
				{
					tracksMenu.antialiasing = true;
					tracksLoaded = true;
				}
			}
			catch (e:Dynamic)
			{
				trace("ERROR: Failed to load tracksMenu: " + e);
			}
		}
		#end
		if (!tracksLoaded)
		{
			tracksMenu.makeGraphic(Std.int(FlxG.width * 0.5), 100, 0xFF000000);
		}
		add(tracksMenu);

		txtTracklist = new FlxText(FlxG.width * 0.05, tracksMenu.y + 60, 0, "", 32);
		txtTracklist.alignment = CENTER;
		txtTracklist.font = rankText.font;
		txtTracklist.color = 0xFFe55777;
		add(txtTracklist);
		// add(rankText);
		add(scoreText);
		add(txtWeekTitle);

		// Error message text
		errorText = new FlxText(0, FlxG.height * 0.5 - 50, FlxG.width, "", 32);
		errorText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.RED, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		errorText.setBorderStyle(OUTLINE, FlxColor.BLACK, 4);
		errorText.scrollFactor.set();
		errorText.alpha = 0;
		errorText.visible = false;
		add(errorText);

		updateText();

		// NUEVO: Mostrar error si no hay semanas disponibles
		if (weekData.length == 0)
		{
			showError("No weeks available in Story Mode!\nAll songs may be set to Freeplay-only.");
		}

		trace("Line 165");

		super.create();

		StickerTransition.clearStickers();
	}

	// === CARGAR SEMANAS DESDE data/storymenu/weeks/*.json ===
	function loadSongsData():Void
	{
		_loadedWeeks = WeekFile.loadAll();

		// Compat: Psych Engine mods inyectan sus propias semanas
		#if sys
		if (mods.ModManager.isActive())
		{
			final fmt = mods.compat.ModCompatLayer.getActiveModFormat();
			if (fmt == mods.compat.ModFormat.PSYCH_ENGINE)
			{
				for (modWeek in mods.compat.ModCompatLayer.getModSongsInfo())
				{
					var ws:Array<String> = cast (Reflect.field(modWeek, 'weekSongs') ?? []);
					if (ws.length == 0) continue;
					var sim:Array<Dynamic> = cast (Reflect.field(modWeek, 'showInStoryMode') ?? []);
					var storySongs:Array<String> = [];
					for (j in 0...ws.length) {
						var show = sim.length == 0 || (j < sim.length && sim[j] == true);
						if (show) storySongs.push(ws[j]);
					}
					if (storySongs.length == 0) continue;
					var cl:Array<String> = cast (Reflect.field(modWeek, 'color') ?? []);
					_loadedWeeks.push({
						id:             'psych_mod_${_loadedWeeks.length}',
						weekName:       Reflect.field(modWeek, 'weekName') ?? 'Week',
						weekPath:       Reflect.field(modWeek, 'weekPath') ?? '',
						weekCharacters: cast (Reflect.field(modWeek, 'weekCharacters') ?? ['', 'bf', 'gf']),
						weekSongs:      storySongs,
						color:          (cl != null && cl.length > 0) ? cl[0] : '0xFFFFD900',
						locked:         Reflect.field(modWeek, 'locked') == true
					});
				}
				trace('[StoryMenuState] Psych mod: ${_loadedWeeks.length} weeks total.');
			}
		}
		#end
	}

	// === CONSTRUIR SEMANAS DESDE JSON ===
	function buildWeeksFromJSON():Void
	{
		if (_loadedWeeks == null || _loadedWeeks.length == 0)
		{
			loadDefaultWeeks();
			return;
		}

		weekData       = [];
		weekCharacters = [];
		weekNames      = [];
		weekUnlocked   = [];
		weekColors     = [];
		weekPaths      = [];

		for (week in _loadedWeeks)
		{
			if (week.weekSongs == null || week.weekSongs.length == 0)
				continue;

			weekData.push(week.weekSongs.copy());
			weekNames.push(week.weekName ?? 'Week');
			weekPaths.push(week.weekPath ?? '');
			weekUnlocked.push(!(week.locked == true));
			weekCharacters.push(
				(week.weekCharacters != null && week.weekCharacters.length >= 3)
				? week.weekCharacters : ['', 'bf', 'gf']
			);

			final colorStr = week.color ?? '0xFFFFD900';
			final colorInt:Null<Int> = Std.parseInt(colorStr);
			var color:FlxColor = (colorInt != null && colorInt != 0)
				? (colorInt : FlxColor) : (0xFFFFD900 : FlxColor);
			color.alpha = 255;
			weekColors.push(color);
		}

		bgcol = weekColors.length > 0 ? weekColors[0] : 0xFF0A0A0A;
		trace('[StoryMenuState] ${weekData.length} weeks built.');
	}
	// === function of FALLBACK for load weeks by DEFECTO ===
	function loadDefaultWeeks():Void
	{
		weekData = [
			['Tutorial'],
			['Bopeebo', 'Fresh', 'Dadbattle'],
			['Spookeez', 'South', "Monster"],
			['Pico', 'Philly', "Blammed"],
			['Satin-Panties', "High", "Milf"],
			['Cocoa', 'Eggnog', 'Winter-Horrorland'],
			['Senpai', 'Roses', 'Thorns']
		];

		weekCharacters = [
			['', 'bf', 'gf'],
			['dad', 'bf', 'gf'],
			['spooky', 'bf', 'gf'],
			['pico', 'bf', 'gf'],
			['mom', 'bf', 'gf'],
			['parents-christmas', 'bf', 'gf'],
			['senpai', 'bf', 'gf']
		];

		weekNames = [
			"Tutorial",
			"Daddy Dearest",
			"Spooky Month",
			"PICO",
			"MOMMY MUST MURDER",
			"RED SNOW",
			"hating simulator ft. moawling"
		];

		weekUnlocked = [true, true, true, true, true, true, true];

		weekColors = [
			0xFF9271FD,
			0xFFAF66CE,
			0xFF2A2A2A,
			0xFF6BAA4C,
			0xFFD85889,
			0xFF9A68A4,
			0xFFFFAA6F
		];
	}

	override function update(elapsed:Float)
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		// validation: Only update if there is weeks
		if (weekData.length > 0)
		{
			// Update score lerp
			lerpScore = Math.floor(FlxMath.lerp(lerpScore, intendedScore, 0.5));
			if (Math.abs(intendedScore - lerpScore) < 10)
				lerpScore = intendedScore;

			scoreText.text = "LEVEL SCORE:" + lerpScore;

			// Update title of the week if is valid
			// validation TRIPLE: curWeek, weekNames, and txtWeekTitle
			if (txtWeekTitle != null && curWeek >= 0 && curWeek < weekNames.length && weekNames[curWeek] != null)
			{
				try
				{
					txtWeekTitle.text = weekNames[curWeek].toUpperCase();
					txtWeekTitle.x = FlxG.width - (txtWeekTitle.width + 10);
				}
				catch (e:Dynamic)
				{
					trace("ERROR: Failed to update week title: " + e);
				}

				// BUGFIX: Antes se asignaba yellowBG.color directamente cada frame,
				// it that no produced transition smooth and podía verse as white/black
				// si el color llegaba null o con un valor inesperado.
				// Ahora solo se lanza un FlxTween.color cuando cambia la semana.
				if (yellowBG != null && curWeek >= 0 && curWeek < weekColors.length && curWeek != _lastColoredWeek)
				{
					_lastColoredWeek = curWeek;
					var targetColor:Null<FlxColor> = weekColors[curWeek];
					if (targetColor == 0 || targetColor == null)
						targetColor = 0xFFFFD900; // fallback if the parsed color is invalid
					if (_bgColorTween != null)
					{
						_bgColorTween.cancel();
						_bgColorTween = null;
					}
					_bgColorTween = FlxTween.color(yellowBG, 0.35, yellowBG.color, targetColor,
						{ease: FlxEase.quartOut, onComplete: function(_) _bgColorTween = null});
				}
			}
			else if (curWeek >= weekNames.length)
			{
				// CORRECTION: If curWeek is out of range, reset it
				trace("WARNING: curWeek (" + curWeek + ") >= weekNames.length (" + weekNames.length + "), resetting to 0");
				curWeek = 0;
			}

			// FlxG.watch.addQuick('font', scoreText.font);

			// Validar antes de acceder al array
			if (curWeek >= 0 && curWeek < weekUnlocked.length && difficultySelectors != null)
				difficultySelectors.visible = weekUnlocked[curWeek];

			if (grpLocks != null)
			{
				grpLocks.forEach(function(lock:FlxSprite)
				{
					if (lock != null && grpWeekText != null && grpWeekText.members != null && lock.ID < grpWeekText.members.length)
					{
						var member = grpWeekText.members[lock.ID];
						if (member != null)
							lock.y = member.y;
					}
				});
			}

			if (!movedBack)
			{
				if (!selectedWeek)
				{
					if (controls.UP_P)
					{
						changeWeek(-1);
					}

					if (controls.DOWN_P)
					{
						changeWeek(1);
					}

					// validation: Only interact with arrows if they exist and have valid frames
					if (rightArrow != null && rightArrow.frames != null && rightArrow.animation != null)
					{
						try
						{
							if (controls.RIGHT)
								rightArrow.animation.play('press')
							else
								rightArrow.animation.play('idle');
						}
						catch (e:Dynamic)
						{
							trace("ERROR: Failed to play rightArrow animation: " + e);
						}
					}

					if (leftArrow != null && leftArrow.frames != null && leftArrow.animation != null)
					{
						try
						{
							if (controls.LEFT)
								leftArrow.animation.play('press');
							else
								leftArrow.animation.play('idle');
						}
						catch (e:Dynamic)
						{
							trace("ERROR: Failed to play leftArrow animation: " + e);
						}
					}

					if (controls.RIGHT_P)
						changeDifficulty(1);
					if (controls.LEFT_P)
						changeDifficulty(-1);
				}

				if (controls.ACCEPT)
				{
					selectWeek();
				}
			}
		}
		else
		{
			// new: If no there is weeks, only allow return back
			scoreText.text = "NO WEEKS AVAILABLE";
			if (txtWeekTitle != null)
				txtWeekTitle.text = "";
		}

		if (controls.BACK && !movedBack && !selectedWeek)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			movedBack = true;
			StateTransition.switchState(new MainMenuState());
			return; // IMPORTANTE: Stop the execution here
		}

		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	var movedBack:Bool = false;
	var selectedWeek:Bool = false;
	var stopspamming:Bool = false;

	function selectWeek()
	{
		#if HSCRIPT_ALLOWED
		var cancelled = StateScriptHandler.callOnScriptsReturn('onAccept', [], false);
		if (cancelled)
			return;
		#end

		// validation: Verify that there is weeks disponibles
		if (weekData.length == 0)
		{
			showError("No weeks available!");
			return;
		}

		// Validate index before of acceder
		if (curWeek < 0 || curWeek >= weekUnlocked.length || curWeek >= weekData.length)
			return;

		if (weekUnlocked[curWeek])
		{
			if (stopspamming == false)
			{
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
				if (FlxG.save.data.flashing)
					FlxG.camera.flash(FlxColor.WHITE, 1);

				if (grpWeekText != null
					&& grpWeekText.members != null
					&& curWeek < grpWeekText.members.length
					&& grpWeekText.members[curWeek] != null)
					grpWeekText.members[curWeek].startFlashing();

				if (grpWeekCharacters != null
					&& grpWeekCharacters.members != null
					&& grpWeekCharacters.members.length > 1
					&& grpWeekCharacters.members[1] != null)
					grpWeekCharacters.members[1].animation.play('confirm');

				stopspamming = true;
			}

			PlayState.storyPlaylist = weekData[curWeek];
			PlayState.isStoryMode = true;
			selectedWeek = true;

			// BUGFIX: storyDifficulty se debe asignar ANTES de llamar a
			// difficultySuffix(), que lee PlayState.storyDifficulty.
			PlayState.storyDifficulty = curDifficulty;

			var diffic = funkin.data.CoolUtil.difficultySuffix();

			PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0].toLowerCase() + diffic, PlayState.storyPlaylist[0].toLowerCase());
			PlayState.storyWeek = curWeek;
			PlayState.campaignScore = 0;

			new FlxTimer().start(1, function(tmr:FlxTimer)
			{
				LoadingState.loadAndSwitchState(new PlayState(), true);
			});
		}
	}

	function changeDifficulty(change:Int = 0):Void
	{
		// validation: Only change difficulty if sprDifficulty exists
		if (sprDifficulty == null)
			return;

		// validation ADICIONAL: Verify that sprDifficulty tiene frames valid
		if (sprDifficulty.frames == null)
		{
			trace("ERROR: sprDifficulty.frames is null, cannot change difficulty");
			return;
		}

		curDifficulty += change;

		final diffs = funkin.menus.FreeplayState.difficultyStuff;

		if (curDifficulty < 0)
			curDifficulty = diffs.length - 1;
		if (curDifficulty >= diffs.length)
			curDifficulty = 0;

		// Nombre de la dificultad (ej: "nightmare"), para cargar la imagen
		final diffLabel:String = diffs[curDifficulty][0].toLowerCase();

		// Cargar la imagen de la dificultad y actualizar hitbox para que
		// sprDifficulty.width refleje el ancho REAL de la nueva imagen.
		try
		{
			// Intenta first with the label exacto, then fallback to easy/normal/hard classic
			var imgPath = 'menu/storymenu/difficulties/$diffLabel';
			if (!openfl.Assets.exists(Paths.image(imgPath)))
			{
				// Para dificultades sin imagen propia, usa "normal" como fallback
				imgPath = 'menu/storymenu/difficulties/normal';
			}
			sprDifficulty.loadGraphic(Paths.image(imgPath));
			sprDifficulty.updateHitbox();
			sprDifficulty.offset.set(0, 0);
		}
		catch (e:Dynamic)
		{
			trace("ERROR: Failed to load difficulty graphic: " + e);
			return;
		}

		// Reposicionar todo el selector centrado respecto a leftArrow.
		// Layout:   [leftArrow] [padding] [sprDifficulty] [padding] [rightArrow]
		// Tanto sprDifficulty como rightArrow se recalculan con el ancho real
		// of the image, so "EASY" (estrecha) and "NORMAL" (ancha) quedan well.
		if (leftArrow != null && rightArrow != null)
		{
			var padding:Float = 16;
			var arrowY:Float = leftArrow.y;
			var startX:Float = leftArrow.x + leftArrow.width + padding;

			// sprDifficulty centrado verticalmente respecto a la flecha
			sprDifficulty.x = startX;
			sprDifficulty.y = arrowY + (leftArrow.height - sprDifficulty.height) / 2;

			// rightArrow justo after of the sprite of difficulty
			rightArrow.x = startX + sprDifficulty.width + padding;
			rightArrow.y = arrowY;

			// Animation of entry: baja from arriba with fade-in
			sprDifficulty.alpha = 0;
			var targetY:Float = sprDifficulty.y;
			sprDifficulty.y = targetY - 15;
			FlxTween.cancelTweensOf(sprDifficulty);
			FlxTween.tween(sprDifficulty, {y: targetY, alpha: 1}, 0.1, {ease: flixel.tweens.FlxEase.cubeOut});
		}
		else
		{
			sprDifficulty.alpha = 0;
			FlxTween.cancelTweensOf(sprDifficulty);
			FlxTween.tween(sprDifficulty, {alpha: 1}, 0.1);
		}

		// validation: Only get score if there is weeks
		if (weekData.length > 0 && curWeek >= 0 && curWeek < weekData.length)
		{
			#if !switch
			intendedScore = Highscore.getWeekScore(curWeek, funkin.data.CoolUtil.difficultySuffix());
			#end
		}
	}

	var lerpScore:Int = 0;
	var intendedScore:Int = 0;

	function changeWeek(change:Int = 0):Void
	{
		// validation: No do nada if no there is weeks
		if (weekData.length == 0)
			return;

		curWeek += change;

		// Validation mejorada with protection extra and clamp
		if (curWeek >= weekData.length)
		{
			curWeek = 0;
			trace("Wrapped to first week");
		}
		if (curWeek < 0)
		{
			curWeek = weekData.length - 1;
			trace("Wrapped to last week");
		}

		// validation critical: Asegurar that curWeek is in rango valid
		// para TODOS los arrays antes de continuar
		if (curWeek >= weekData.length || curWeek < 0)
		{
			trace("ERROR: curWeek out of range after wrap: " + curWeek);
			curWeek = 0;
		}

		var bullShit:Int = 0;

		// Verificar que grpWeekText no sea null
		if (grpWeekText != null && grpWeekText.members != null)
		{
			for (item in grpWeekText.members)
			{
				if (item != null)
				{
					item.targetY = bullShit - curWeek;

					// Validate indices before accessing weekUnlocked
					if (item.targetY == Std.int(0) && curWeek >= 0 && curWeek < weekUnlocked.length && weekUnlocked[curWeek])
						item.alpha = 1;
					else
						item.alpha = 0.6;
				}
				bullShit++;
			}
		}

		FlxG.sound.play(Paths.sound('menus/scrollMenu'));

		// Asegurar that curWeek is valid justo before of updateText
		if (curWeek >= 0 && curWeek < weekData.length)
		{
			updateText();
		}
		else
		{
			trace("ERROR: Skipping updateText, curWeek invalid: " + curWeek);
		}

		#if HSCRIPT_ALLOWED
		var cancelled = StateScriptHandler.callOnScriptsReturn('onWeekSelected', [], false);
		#end
	}

	function updateText()
	{
		// validation: Only update if there is weeks
		if (weekData.length == 0)
			return;

		// Validate that curWeek is inside of the rango before of do any cosa
		if (curWeek < 0 || curWeek >= weekData.length)
		{
			trace("WARNING: curWeek out of range in updateText: " + curWeek + " (weekData.length: " + weekData.length + ")");
			curWeek = 0; // Reset a la primera semana
			if (weekData.length == 0)
				return;
		}

		// Validation mejorada for prevenir indices fuera of rango
		var weekArray:Array<String> = ['', 'bf', 'gf']; // Default seguro

		if (curWeek >= 0 && curWeek < weekCharacters.length && weekCharacters[curWeek] != null)
		{
			weekArray = weekCharacters[curWeek];
		}
		else if (weekCharacters.length > 0 && weekCharacters[0] != null)
		{
			weekArray = weekCharacters[0]; // Fallback al primero
		}
		else
		{
			trace("WARNING: weekCharacters is empty or null, using defaults");
		}

		// Verify that grpWeekCharacters no sea null and tenga the size correct
		if (grpWeekCharacters != null && grpWeekCharacters.members != null)
		{
			for (i in 0...grpWeekCharacters.length)
			{
				var member = grpWeekCharacters.members[i];
				if (member != null && i < weekArray.length && weekArray[i] != null)
				{
					try
					{
						member.changeCharacter(weekArray[i]);
					}
					catch (e:Dynamic)
					{
						trace("ERROR: Failed to change character at index " + i + " to '" + weekArray[i] + "': " + e);
					}
				}
			}
		}

		// Doble validation of curWeek before of acceder to weekData
		if (curWeek < 0 || curWeek >= weekData.length)
		{
			trace("WARNING: curWeek still out of range after validation: " + curWeek);
			return;
		}

		var stringThing:Array<String> = weekData[curWeek];

		// Validar que stringThing no sea null
		if (stringThing == null)
		{
			trace("ERROR: weekData[" + curWeek + "] is null!");
			return;
		}

		if (txtTracklist != null)
		{
			txtTracklist.text = '';
			for (i in 0...stringThing.length)
			{
				if (stringThing[i] != null)
					txtTracklist.text += stringThing[i] + '\n';
			}

			txtTracklist.text = StringTools.replace(txtTracklist.text, '-', ' ');
			txtTracklist.text = txtTracklist.text.toUpperCase();

			txtTracklist.screenCenter(X);
			txtTracklist.x -= FlxG.width * 0.35;
		}

		#if !switch
		if (curWeek >= 0 && curWeek < weekData.length)
			intendedScore = Highscore.getWeekScore(curWeek, funkin.data.CoolUtil.difficultySuffix());
		#end
	}

	function showError(message:String):Void
	{
		// Cancel any existing error tween
		if (errorTween != null)
		{
			errorTween.cancel();
		}

		// Set error message
		errorText.text = message;
		errorText.visible = true;
		errorText.alpha = 0;

		// Fade in
		errorTween = FlxTween.tween(errorText, {alpha: 1}, 0.3, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				// Wait 3 seconds then fade out
				errorTween = FlxTween.tween(errorText, {alpha: 0}, 0.5, {
					ease: FlxEase.expoIn,
					startDelay: 3.0,
					onComplete: function(twn:FlxTween)
					{
						errorText.visible = false;
					}
				});
			}
		});
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
