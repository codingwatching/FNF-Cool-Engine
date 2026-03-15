package funkin.menus;

import openfl.display.BitmapData;
import flixel.text.FlxText;
import funkin.gameplay.PlayState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxSubState;
import flixel.util.FlxTimer;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.effects.particles.FlxEmitter;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StateTransition;
import funkin.transitions.StickerTransition;
import funkin.states.LoadingState;
import flixel.math.FlxMath;
import flixel.util.FlxGradient;
import flixel.group.FlxSpriteGroup;
import flixel.effects.particles.FlxParticle;
import haxe.Json;

/**
 * RatingState v3 — result screen with fully softcoded rank config.
 *
 * ─── Rank config ──────────────────────────────────────────────────────────────
 *
 * Loaded from (first found wins):
 *   1. mods/{mod}/data/songs/{song}/ranking_config.json
 *   2. mods/{mod}/data/ranking_config.json
 *   3. assets/data/songs/{song}/ranking_config.json
 *   4. assets/data/ranking_config.json
 *   5. Built-in defaults (see RankConfig.defaults)
 *
 * Format:
 * {
 *   "ranks": [
 *     {
 *       "key":          "SS",
 *       "minAccuracy":  99.99,
 *       "displayName":  "PERFECT!!",
 *       "color":        "FFFF00",       // hex string, no #
 *       "bgColor":      "FFD700",
 *       "music":        "SS",           // resultsXX/resultsXX.ogg
 *       "sparkles":     true,
 *       "camShake":     0.012
 *     },
 *     ...
 *   ],
 *   "failAt": 59.99,     // accuracy below this → "F" rank
 *   "naWhenZero": true   // 0% with 0 misses → "N/A"
 * }
 *
 * ─── Script hooks ─────────────────────────────────────────────────────────────
 * (All previous hooks still work, plus:)
 *   onRankConfigLoaded(config)          → after config is parsed
 *   getSongDisplayName(song, diff)      → override the title shown at top
 *   onSongTitleCreate(titleText)        → after creating the song title text
 */
class RatingState extends FlxSubState
{
	// ─── Visual elements ──────────────────────────────────────────────────────
	public var comboText:FlxText;
	public var bf:funkin.gameplay.objects.character.Character;
	public var bg:FlxSprite;
	public var bgGradient:FlxSprite;
	public var bgPattern:FlxSprite;
	public var scoreDisplay:FlxTypedGroup<FlxText>;
	public var rankSprite:FlxSprite;
	public var fcBadge:FlxSprite;
	public var accuracyText:FlxText;
	public var ratingText:FlxText;
	public var glowOverlay:FlxSprite;
	public var particles:FlxEmitter;
	public var confetti:FlxEmitter;
	public var statBars:FlxTypedGroup<StatBar>;
	public var songTitleText:FlxText;
	public var difficultyText:FlxText;

	// ─── Internal state ───────────────────────────────────────────────────────
	public var canExit:Bool     = false;
	public var isExiting:Bool   = false;
	public var introComplete:Bool = false;
	public var currentRank:String;
	public var rankConfig:RankConfig;

	/** Current loaded rank entry (data for currentRank). */
	public var currentRankEntry(get, never):Null<RankEntry>;
	function get_currentRankEntry():Null<RankEntry>
	{
		if (rankConfig == null || rankConfig.ranks == null) return null;
		for (r in rankConfig.ranks) if (r.key == currentRank) return r;
		return null;
	}

	var pulseElements:Array<FlxSprite> = [];

	// Beat tracking via Conductor
	var _lastBeat:Int = -1;

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	override public function create():Void
	{
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('RatingState', this);
		StateScriptHandler.callOnScripts('onCreate', []);

		super.create();

		// Load rank config (softcoded from JSON)
		rankConfig = RankConfig.load(_songId());
		StateScriptHandler.callOnScripts('onRankConfigLoaded', [rankConfig]);

		// Determine current rank
		currentRank = _generateRank();

		_exposePlayStateData();
		StateScriptHandler.exposeElement('ratingState',  this);
		StateScriptHandler.exposeElement('currentRank',  currentRank);
		StateScriptHandler.exposeElement('rankConfig',   rankConfig);

		// Build UI
		createBackgrounds();
		createParticleSystems();
		createSongTitle();
		createBFCharacter();
		createRankDisplay();
		createStatsDisplay();
		createStatBars();
		createAccuracyDisplay();

		glowOverlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.WHITE);
		glowOverlay.alpha = 0;
		glowOverlay.blend = ADD;
		add(glowOverlay);
		StateScriptHandler.exposeElement('glowOverlay', glowOverlay);

		createHelpText();
		startMusicWithIntro();
		playIntroAnimation();

		StateScriptHandler.callOnScripts('postCreate', []);
		StateTransition.onStateCreated();
	}

	override function destroy():Void
	{
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		super.destroy();
	}

	override function update(elapsed:Float):Void
	{
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		super.update(elapsed);

		// Beat detection using Conductor (if music is playing)
		if (FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			var bpm         = 120.0;
			var beatLength  = (60.0 / bpm) * 1000.0;
			var curBeat     = Math.floor(FlxG.sound.music.time / beatLength);
			if (curBeat != _lastBeat)
			{
				_lastBeat = curBeat;
				_onBeat(curBeat);
			}
		}

		if (bgPattern != null)
			bgPattern.angle += elapsed * 2;

		if (bf != null && (bf.animation.finished || bf.animation.curAnim.name == 'idle'))
			bf.playAnim('idle', true);

		var pressedEnter = FlxG.keys.justPressed.ENTER;
		var pressedRetry = FlxG.keys.justPressed.R;

		#if mobile
		for (touch in FlxG.touches.list)
			if (touch.justPressed) pressedEnter = true;
		#end

		if (pressedEnter && canExit && !isExiting) exitState(false);
		if (pressedRetry && canExit && !isExiting) exitState(true);

		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
	}

	// ─── Rank generation (reads from RankConfig) ──────────────────────────────

	function _generateRank():String
	{
		var acc = PlayState.accuracy;

		// Script override first
		var scriptRank = StateScriptHandler.callOnScriptsReturn('getCustomRank', [acc], null);
		if (scriptRank != null) return scriptRank;

		if (rankConfig.naWhenZero && acc == 0 && PlayState.misses == 0)
			return 'N/A';

		if (acc <= rankConfig.failAt && !PlayState.startingSong)
			return 'F';

		// Walk sorted ranks (highest minAccuracy first)
		var sorted = rankConfig.ranks.copy();
		sorted.sort(function(a, b) return b.minAccuracy > a.minAccuracy ? 1 : -1);
		for (entry in sorted)
		{
			if (acc >= entry.minAccuracy)
				return entry.key;
		}

		return 'F';
	}

	// ─── Visual builders ─────────────────────────────────────────────────────

	function createBackgrounds():Void
	{
		bg = new FlxSprite().loadGraphic(Paths.image('menu/menuBGBlue'));
		bg.alpha = 0;
		bg.scrollFactor.set(0.1, 0.1);
		bg.color = _getBgColor();
		add(bg);

		bgGradient = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height,
			[FlxColor.TRANSPARENT, 0x88000000]);
		bgGradient.alpha = 0;
		add(bgGradient);

		bgPattern = new FlxSprite().loadGraphic(Paths.image('menu/blackslines_finalrating'));
		bgPattern.alpha = 0;
		bgPattern.blend = MULTIPLY;
		add(bgPattern);

		StateScriptHandler.exposeAll(['bg' => bg, 'bgGradient' => bgGradient, 'bgPattern' => bgPattern]);
		StateScriptHandler.callOnScripts('onBackgroundsCreate', [bg, bgGradient, bgPattern]);
	}

	function createParticleSystems():Void
	{
		particles = new FlxEmitter(0, 0, 100);
		particles.makeParticles(4, 4, FlxColor.WHITE, 100);
		particles.launchMode = FlxEmitterMode.SQUARE;
		particles.velocity.set(-100, -200, 100, -400);
		particles.lifespan.set(3, 6);
		particles.alpha.set(0.3, 0.6, 0, 0);
		particles.scale.set(1, 1.5, 0.2, 0.5);
		particles.width  = FlxG.width;
		particles.height = 100;
		particles.y      = FlxG.height;
		add(particles);

		var entry = currentRankEntry;
		var doSparkles = (entry != null && entry.sparkles) || (currentRank == 'S' || currentRank == 'SS');

		if (doSparkles)
		{
			confetti = new FlxEmitter(FlxG.width / 2, -50, 150);
			confetti.makeParticles(6, 6, FlxColor.WHITE, 150);
			confetti.launchMode = FlxEmitterMode.SQUARE;
			confetti.velocity.set(-200, 100, 200, 300);
			confetti.angularVelocity.set(-180, 180);
			confetti.lifespan.set(4, 8);
			confetti.alpha.set(0.8, 1, 0, 0);
			confetti.width = FlxG.width;
			add(confetti);
		}

		StateScriptHandler.exposeAll(['particles' => particles, 'confetti' => confetti]);
		StateScriptHandler.callOnScripts('onParticlesCreate', [particles, confetti]);
	}

	function createSongTitle():Void
	{
		var songName = PlayState.SONG?.song ?? "";
		var diff     = funkin.data.CoolUtil.difficultyString();

		var displayName = StateScriptHandler.callOnScriptsReturn(
			'getSongDisplayName', [songName, diff], '${songName.toUpperCase()}');

		songTitleText = new FlxText(0, FlxG.height, FlxG.width, displayName, 28);
		songTitleText.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		songTitleText.borderSize = 3;
		songTitleText.alpha = 0;
		add(songTitleText);

		difficultyText = new FlxText(0, FlxG.height + 30, FlxG.width, diff, 16);
		difficultyText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromRGB(200, 200, 255), CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		difficultyText.borderSize = 2;
		difficultyText.alpha = 0;
		add(difficultyText);

		FlxTween.tween(songTitleText, {y: 8, alpha: 1}, 0.8,
			{ease: FlxEase.backOut, startDelay: 0.2});
		FlxTween.tween(difficultyText, {y: 44, alpha: 1}, 0.8,
			{ease: FlxEase.backOut, startDelay: 0.3});

		StateScriptHandler.exposeAll(['songTitleText' => songTitleText, 'difficultyText' => difficultyText]);
		StateScriptHandler.callOnScripts('onSongTitleCreate', [songTitleText]);
	}

	function createBFCharacter():Void
	{
		var char:String = PlayState.SONG?.player1 ?? 'bf';
		var bfChar = StateScriptHandler.callOnScriptsReturn('getBFCharacter', [], char);

		bf = new funkin.gameplay.objects.character.Character(-100, FlxG.height + 100, bfChar);
		
		bf.scale.set(bf.width + 0.2, bf.height + 0.2);
		add(bf);

		pulseElements.push(bf);
		StateScriptHandler.exposeElement('bf', bf);
		StateScriptHandler.callOnScripts('onBFCreate', [bf]);
	}

	function createRankDisplay():Void
	{
		var daLogo:FlxSprite = new FlxSprite(FlxG.width / 2 + 100, -200);
		daLogo.loadGraphic(Paths.image('titlestate/daLogo'));
		daLogo.scale.set(0.6, 0.6);
		daLogo.alpha = 0;
		daLogo.updateHitbox();
		add(daLogo);
		StateScriptHandler.exposeElement('daLogo', daLogo);

		var rankDisplayY:Float = (currentRank == 'S' || currentRank == 'SS') ? 80 : 120;

		rankSprite = new FlxSprite(FlxG.width / 2 + 350, -300);
		rankSprite.loadGraphic(Paths.image('menu/ratings/${currentRank}'));
		rankSprite.scale.set(1.7, 1.7);
		rankSprite.antialiasing = FlxG.save.data.antialiasing;
		rankSprite.alpha = 0;
		rankSprite.updateHitbox();
		rankSprite.screenCenter(X);
		rankSprite.x += 100;
		add(rankSprite);
		pulseElements.push(rankSprite);
		StateScriptHandler.exposeElement('rankSprite', rankSprite);

		if (PlayState.misses == 0)
		{
			fcBadge = new FlxSprite(rankSprite.x - 100, rankSprite.y + 200);
			fcBadge.loadGraphic(Paths.image('menu/ratings/FC'));
			fcBadge.scale.set(1.2, 1.2);
			fcBadge.antialiasing = FlxG.save.data.antialiasing;
			fcBadge.alpha = 0;
			fcBadge.updateHitbox();
			add(fcBadge);
			pulseElements.push(fcBadge);
			StateScriptHandler.exposeElement('fcBadge', fcBadge);
			StateScriptHandler.callOnScripts('onFCBadgeCreate', [fcBadge]);
		}

		var entry     = currentRankEntry;
		var shakeAmt  = (entry != null && entry.camShake > 0) ? entry.camShake : 0.01;

		FlxTween.tween(daLogo, {y: 40, alpha: 1}, 0.8, {ease: FlxEase.elasticOut, startDelay: 0.3});
		FlxTween.tween(rankSprite, {y: rankDisplayY, alpha: 1}, 1.0, {
			ease: FlxEase.elasticOut,
			startDelay: 0.5,
			onComplete: function(_)
			{
				FlxG.camera.shake(shakeAmt, 0.25);
				glowOverlay.alpha = 0.35;
				FlxTween.tween(glowOverlay, {alpha: 0}, 0.5);
				if (confetti != null) confetti.start(false, 0.05, 0);
				StateScriptHandler.callOnScripts('onRankLanded', [rankSprite, currentRank]);
			}
		});
		if (fcBadge != null)
			FlxTween.tween(fcBadge, {alpha: 1}, 0.6, {ease: FlxEase.quadOut, startDelay: 1.2});

		StateScriptHandler.callOnScripts('onRankCreate', [rankSprite]);
	}

	function createStatsDisplay():Void
	{
		scoreDisplay = new FlxTypedGroup<FlxText>();
		add(scoreDisplay);

		var statsData:Array<Dynamic> = [
			{label: 'SCORE',  value: '${PlayState.songScore}',              color: FlxColor.YELLOW},
			{label: 'SICKS',  value: '${PlayState.sicks}',                  color: FlxColor.CYAN},
			{label: 'GOODS',  value: '${PlayState.goods}',                  color: FlxColor.LIME},
			{label: 'BADS',   value: '${PlayState.bads}',                   color: FlxColor.ORANGE},
			{label: 'SHITS',  value: '${PlayState.shits}',                  color: FlxColor.fromRGB(139, 69, 19)},
			{label: 'MISSES', value: '${PlayState.misses}',                 color: FlxColor.RED},
			{label: 'COMBO',  value: '${PlayState.maxCombo}',               color: FlxColor.fromRGB(200, 200, 255)}
		];

		final customStats = StateScriptHandler.collectArrays('getCustomStats');
		for (cs in customStats) statsData.push(cs);

		final startX = 50.0;
		final startY = 70.0; // shifted down to make room for song title
		final spacing = 55.0;

		for (i in 0...statsData.length)
		{
			final stat = statsData[i];

			final label:FlxText = new FlxText(startX - 100, startY + (i * spacing), 150, stat.label, 22);
			label.setFormat(Paths.font('vcr.ttf'), 22, stat.color, LEFT,
				FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			label.borderSize = 2; label.alpha = 0;
			scoreDisplay.add(label);

			final value:FlxText = new FlxText(startX + 60, startY + (i * spacing), 200, stat.value, 30);
			value.setFormat(Paths.font('vcr.ttf'), 30, FlxColor.WHITE, LEFT,
				FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			value.borderSize = 2; value.alpha = 0;
			scoreDisplay.add(value);

			FlxTween.tween(label, {x: startX,       alpha: 1}, 0.5, {ease: FlxEase.backOut, startDelay: 0.8 + (i * 0.08)});
			FlxTween.tween(value, {x: startX + 160, alpha: 1}, 0.5, {ease: FlxEase.backOut, startDelay: 0.85 + (i * 0.08)});
		}

		StateScriptHandler.exposeElement('scoreDisplay', scoreDisplay);
		StateScriptHandler.callOnScripts('onStatsCreate', [scoreDisplay]);
	}

	function createStatBars():Void
	{
		statBars = new FlxTypedGroup<StatBar>();
		add(statBars);

		var total:Int = PlayState.sicks + PlayState.goods + PlayState.bads + PlayState.shits + PlayState.misses;
		if (total == 0) total = 1;

		final barData = [
			{notes: PlayState.sicks,  color: FlxColor.CYAN,                     yOffset: 0},
			{notes: PlayState.goods,  color: FlxColor.LIME,                     yOffset: 1},
			{notes: PlayState.bads,   color: FlxColor.ORANGE,                   yOffset: 2},
			{notes: PlayState.shits,  color: FlxColor.fromRGB(139, 69, 19),     yOffset: 3},
			{notes: PlayState.misses, color: FlxColor.RED,                      yOffset: 4}
		];

		final startY  = 100.0;
		final spacing = 55.0;

		for (i in 0...barData.length)
		{
			final data = barData[i];
			final pct  = data.notes / total;
			final bar  = new StatBar(500, startY + (data.yOffset * spacing), pct, data.color);
			statBars.add(bar);
			FlxTween.tween(bar, {alpha: 1}, 0.3, {
				startDelay: 1.2 + (i * 0.08),
				onComplete: function(_) bar.animateBar()
			});
		}

		StateScriptHandler.exposeElement('statBars', statBars);
		StateScriptHandler.callOnScripts('onStatBarsCreate', [statBars]);
	}

	function createAccuracyDisplay():Void
	{
		final accuracy   = PlayState.accuracy;
		final ratingTxt  = _getRatingText(accuracy);
		final ratingClr  = _getRatingColor(accuracy);

		accuracyText = new FlxText(0, FlxG.height, FlxG.width, Std.int(accuracy) + '%', 72);
		accuracyText.setFormat(Paths.font('vcr.ttf'), 72, FlxColor.WHITE, CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		accuracyText.borderSize = 4; accuracyText.alpha = 0;
		add(accuracyText);

		ratingText = new FlxText(0, FlxG.height, FlxG.width, ratingTxt, 32);
		ratingText.setFormat(Paths.font('vcr.ttf'), 32, ratingClr, CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		ratingText.borderSize = 2; ratingText.alpha = 0;
		add(ratingText);

		FlxTween.tween(accuracyText, {y: FlxG.height - 180, alpha: 1}, 0.8,
			{ease: FlxEase.backOut, startDelay: 1.4});
		FlxTween.tween(ratingText,  {y: FlxG.height - 110, alpha: 1}, 0.8,
			{ease: FlxEase.backOut, startDelay: 1.5});

		pulseElements.push(cast accuracyText);

		StateScriptHandler.exposeAll(['accuracyText' => accuracyText, 'ratingText' => ratingText]);
		StateScriptHandler.callOnScripts('onAccuracyCreate', [accuracyText, ratingText]);
	}

	function createHelpText():Void
	{
		final helpMsg = StateScriptHandler.callOnScriptsReturn('getHelpText', [],
			'[ENTER] Continue  •  [R] Retry');

		final helpText:FlxText = new FlxText(0, FlxG.height - 50, FlxG.width, helpMsg, 24);
		helpText.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		helpText.borderSize = 2; helpText.alpha = 0;
		add(helpText);

		FlxTween.tween(helpText, {alpha: 1}, 0.5, {ease: FlxEase.quadInOut, startDelay: 2, type: PINGPONG});
		StateScriptHandler.exposeElement('helpText', helpText);
	}

	// ─── Music ────────────────────────────────────────────────────────────────

	function startMusicWithIntro():Void
	{
		final overridden = StateScriptHandler.callOnScriptsReturn('getRankMusic', [currentRank], null);
		var rankMusic:String;

		if (overridden != null)
		{
			rankMusic = overridden;
		}
		else
		{
			// Use entry.music if defined, else fall back to key (or B for C/D)
			var entry = currentRankEntry;
			if (entry != null && entry.music != null && entry.music.length > 0)
				rankMusic = entry.music;
			else
				rankMusic = (currentRank == 'C' || currentRank == 'D') ? 'B' : currentRank;
		}

		FlxG.sound.playMusic(Paths.music('results$rankMusic/results$rankMusic'), 0);
		FlxTween.tween(FlxG.sound.music, {volume: 0.7}, 2.0, {
			ease: FlxEase.quadOut,
			onComplete: function(_) { introComplete = true; }
		});
	}

	// ─── Animations ──────────────────────────────────────────────────────────

	function playIntroAnimation():Void
	{
		FlxG.camera.fade(FlxColor.BLACK, 1, true);
		FlxTween.tween(bg,         {alpha: 0.4}, 1.2, {ease: FlxEase.quadOut});
		FlxTween.tween(bgGradient, {alpha: 0.7}, 1.5, {ease: FlxEase.quadOut});
		FlxTween.tween(bgPattern,  {alpha: 0.3}, 1.8, {ease: FlxEase.quadOut});
		FlxTween.tween(bf, {x: 120, y: 320}, 1.2, {ease: FlxEase.expoOut, startDelay: 0.4});

		new FlxTimer().start(0.8, function(_)
		{
			particles.start(false, 0.08, 0);
			canExit = true;
			StateScriptHandler.callOnScripts('onCanExitChange', [true]);
		});

		StateScriptHandler.callOnScripts('onIntroStart', []);
	}

	function _onBeat(beat:Int):Void
	{
		StateScriptHandler.callOnScripts('onBeatHit', [beat]);

		for (el in pulseElements)
		{
			if (el == null) continue;
			FlxTween.cancelTweensOf(el.scale);
			el.scale.x *= 1.05; el.scale.y *= 1.05;
			FlxTween.tween(el.scale, {x: el.scale.x / 1.05, y: el.scale.y / 1.05}, 0.25,
				{ease: FlxEase.quadOut});
		}

		FlxG.camera.zoom = 1.015;
		FlxTween.tween(FlxG.camera, {zoom: 1}, 0.25, {ease: FlxEase.quadOut});
	}

	function exitState(retry:Bool = false):Void
	{
		if (StateScriptHandler.callOnScripts('onExit', [retry])) return;

		isExiting = true;
		if (bf != null && bf.hasAnim('hey')) bf.animation.play('hey', true);

		if (FlxG.save.data.flashing) FlxG.camera.flash(FlxColor.WHITE, 0.5);
		FlxG.camera.shake(0.005, 0.3);

		FlxTween.tween(FlxG.sound.music, {volume: 0}, 0.8, {ease: FlxEase.quadIn});

		if (rankSprite  != null) FlxTween.tween(rankSprite,  {y: rankSprite.y - 100, alpha: 0}, 0.6, {ease: FlxEase.backIn});
		if (bf          != null) FlxTween.tween(bf,          {x: -200,               alpha: 0}, 0.8, {ease: FlxEase.expoIn});
		if (accuracyText != null) FlxTween.tween(accuracyText, {y: FlxG.height + 100, alpha: 0}, 0.7, {ease: FlxEase.backIn});
		if (songTitleText != null) FlxTween.tween(songTitleText, {y: -60, alpha: 0}, 0.5, {ease: FlxEase.backIn});

		for (text in scoreDisplay)
			FlxTween.tween(text, {x: text.x - 150, alpha: 0}, 0.5, {ease: FlxEase.quadIn});

		FlxG.camera.fade(FlxColor.BLACK, 1.2, false);

		new FlxTimer().start(1.2, function(_)
		{
			if (FlxG.sound.music != null) FlxG.sound.music.stop();
			StateScriptHandler.callOnScripts('onExitComplete', [retry]);

			if (retry && PlayState.SONG?.song != null)
			{
				FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
				PlayState.startFromTime = null;
				new FlxTimer().start(0.3, function(_)
				{
					FlxG.mouse.visible = false;
					LoadingState.loadAndSwitchState(new PlayState());
				});
			}
			else
			{
				if (PlayState.isStoryMode)
					StateTransition.switchState(new funkin.menus.StoryMenuState());
				else
					StickerTransition.start(function() StateTransition.switchState(new funkin.menus.FreeplayState()));
			}
		});
	}

	// ─── Rating text helpers (script-overrideable) ────────────────────────────

	function _getRatingText(accuracy:Float):String
	{
		final override_ = StateScriptHandler.callOnScriptsReturn('getRatingText', [accuracy], null);
		if (override_ != null) return override_;

		// Check rank entry displayName first
		var entry = currentRankEntry;
		if (entry != null && entry.displayName != null && entry.displayName.length > 0)
			return entry.displayName;

		if (accuracy == 100)  return 'PERFECT!!';
		if (accuracy >= 95)   return 'AMAZING!';
		if (accuracy >= 90)   return 'EXCELLENT!';
		if (accuracy >= 85)   return 'GREAT!';
		if (accuracy >= 80)   return 'GOOD!';
		if (accuracy >= 70)   return 'NICE!';
		if (accuracy >= 60)   return 'OK';
		return 'KEEP TRYING';
	}

	function _getRatingColor(accuracy:Float):Int
	{
		final override_ = StateScriptHandler.callOnScriptsReturn('getRatingColor', [accuracy], null);
		if (override_ != null) return override_;

		var entry = currentRankEntry;
		if (entry != null && entry.color != null && entry.color.length > 0)
			return Std.parseInt('0xFF${entry.color}');

		if (accuracy == 100) return FlxColor.fromRGB(255, 215, 0);
		if (accuracy >= 95)  return FlxColor.fromRGB(100, 255, 100);
		if (accuracy >= 85)  return FlxColor.CYAN;
		if (accuracy >= 70)  return FlxColor.YELLOW;
		if (accuracy >= 60)  return FlxColor.ORANGE;
		return FlxColor.RED;
	}

	function _getBgColor():Int
	{
		final override_ = StateScriptHandler.callOnScriptsReturn('getCustomBgColor', [currentRank], null);
		if (override_ != null) return override_;

		var entry = currentRankEntry;
		if (entry != null && entry.bgColor != null && entry.bgColor.length > 0)
			return Std.parseInt('0xFF${entry.bgColor}');

		return switch (currentRank)
		{
			case 'S' | 'SS': FlxColor.fromRGB(255, 215, 0);
			case 'A':        FlxColor.fromRGB(100, 255, 100);
			case 'B':        FlxColor.fromRGB(100, 200, 255);
			case 'C' | 'D':  FlxColor.fromRGB(255, 150, 100);
			case 'F':        FlxColor.fromRGB(200, 100, 100);
			default:         FlxColor.fromRGB(100, 100, 200);
		};
	}

	// ─── Helpers ─────────────────────────────────────────────────────────────

	function _songId():String
		return (PlayState.SONG?.song ?? '').toLowerCase();

	function _exposePlayStateData():Void
	{
		StateScriptHandler.exposeAll([
			'songScore'   => PlayState.songScore,
			'accuracy'    => PlayState.accuracy,
			'misses'      => PlayState.misses,
			'sicks'       => PlayState.sicks,
			'goods'       => PlayState.goods,
			'bads'        => PlayState.bads,
			'shits'       => PlayState.shits,
			'maxCombo'    => PlayState.maxCombo,
			'isStoryMode' => PlayState.isStoryMode,
			'songName'    => PlayState.SONG?.song ?? '',
			'difficulty'  => PlayState.storyDifficulty
		]);
	}
}


// ============================================================================
//  RankEntry  — single rank data entry
// ============================================================================
typedef RankEntry =
{
	var key:String;           // "SS", "S", "A", etc.
	var minAccuracy:Float;    // threshold (e.g. 99.99 for SS)
	@:optional var displayName:String;  // text shown in ratingText
	@:optional var color:String;        // hex RRGGBB (no #) for ratingText color
	@:optional var bgColor:String;      // hex RRGGBB for bg tint
	@:optional var music:String;        // music key, e.g. "SS"
	@:optional var sparkles:Bool;       // show confetti emitter
	@:optional var camShake:Float;      // camera shake amount on rank land
}

// ============================================================================
//  RankConfig  — full config loaded from JSON
// ============================================================================
class RankConfig
{
	public var ranks:Array<RankEntry>;
	public var failAt:Float;
	public var naWhenZero:Bool;

	public function new()
	{
		ranks      = _defaultRanks();
		failAt     = 59.99;
		naWhenZero = true;
	}

	public static function defaults():RankConfig return new RankConfig();

	/**
	 * Load config for a given song.
	 * Search order:
	 *  1. mods/{mod}/data/songs/{song}/ranking_config.json
	 *  2. mods/{mod}/data/ranking_config.json
	 *  3. assets/data/songs/{song}/ranking_config.json
	 *  4. assets/data/ranking_config.json
	 */
	public static function load(songId:String):RankConfig
	{
		var cfg    = new RankConfig();
		var loaded = false;

		var paths:Array<String> = [];

		#if sys
		var activeMod = mods.ModManager.activeMod;
		if (activeMod != null)
		{
			var modBase = '${mods.ModManager.MODS_FOLDER}/${activeMod}';
			if (songId.length > 0)
				paths.push('$modBase/data/songs/$songId/ranking_config.json');
			paths.push('$modBase/data/ranking_config.json');
		}
		#end

		if (songId.length > 0)
			paths.push('assets/data/songs/$songId/ranking_config.json');
		paths.push('assets/data/ranking_config.json');

		for (p in paths)
		{
			#if sys
			if (!sys.FileSystem.exists(p)) continue;
			try
			{
				var raw:Dynamic = Json.parse(sys.io.File.getContent(p));
				_parseInto(cfg, raw);
				loaded = true;
				trace('[RatingState] Loaded ranking_config from: $p');
				break;
			}
			catch (e:Dynamic)
			{
				trace('[RatingState] Failed to parse $p: $e');
			}
			#else
			try
			{
				if (!openfl.utils.Assets.exists(p)) continue;
				var raw:Dynamic = Json.parse(openfl.utils.Assets.getText(p));
				_parseInto(cfg, raw);
				loaded = true;
				break;
			}
			catch (_:Dynamic) {}
			#end
		}

		if (!loaded) trace('[RatingState] Using default ranking config');
		return cfg;
	}

	static function _parseInto(cfg:RankConfig, raw:Dynamic):Void
	{
		if (raw.failAt   != null) cfg.failAt    = raw.failAt;
		if (raw.naWhenZero != null) cfg.naWhenZero = raw.naWhenZero;

		if (raw.ranks != null)
		{
			cfg.ranks = [];
			var arr:Array<Dynamic> = raw.ranks;
			for (r in arr)
			{
				var entry:RankEntry = {
					key:         r.key         ?? "?",
					minAccuracy: r.minAccuracy ?? 0,
					displayName: r.displayName ?? null,
					color:       r.color       ?? null,
					bgColor:     r.bgColor     ?? null,
					music:       r.music       ?? null,
					sparkles:    r.sparkles    ?? false,
					camShake:    r.camShake    ?? 0.01
				};
				cfg.ranks.push(entry);
			}
		}
	}

	static function _defaultRanks():Array<RankEntry>
	{
		return [
			{key: 'SS', minAccuracy: 99.99, displayName: 'PERFECT!!',   color: 'FFD700', bgColor: 'FFD700', music: 'SS', sparkles: true,  camShake: 0.012},
			{key: 'S',  minAccuracy: 94.99, displayName: 'AMAZING!',    color: '64FF64', bgColor: '64FF00', music: 'S',  sparkles: true,  camShake: 0.010},
			{key: 'A',  minAccuracy: 89.99, displayName: 'EXCELLENT!',  color: '64FFFF', bgColor: '64C8FF', music: 'A',  sparkles: false, camShake: 0.008},
			{key: 'B',  minAccuracy: 79.99, displayName: 'GREAT!',      color: 'FFFF00', bgColor: '64C8FF', music: 'B',  sparkles: false, camShake: 0.006},
			{key: 'C',  minAccuracy: 69.99, displayName: 'NICE!',       color: 'FFA000', bgColor: 'FF9664', music: 'B',  sparkles: false, camShake: 0.004},
			{key: 'D',  minAccuracy: 59.99, displayName: 'OK',          color: 'FF6400', bgColor: 'FF9664', music: 'B',  sparkles: false, camShake: 0.004},
			{key: 'F',  minAccuracy: 0,     displayName: 'KEEP TRYING', color: 'FF3333', bgColor: 'C86464', music: 'B',  sparkles: false, camShake: 0.008}
		];
	}
}


// ============================================================================
//  StatBar (unchanged from v2)
// ============================================================================
class StatBar extends FlxSpriteGroup
{
	var targetWidth:Float;
	var maxWidth:Float = 400;
	var barColor:Int;
	var bgBar:FlxSprite;
	var fillBar:FlxSprite;

	public function new(x:Float, y:Float, percentage:Float, color:Int)
	{
		super(x, y);
		barColor    = color;
		targetWidth = maxWidth * percentage;

		bgBar  = new FlxSprite(x, y);
		bgBar.makeGraphic(Std.int(maxWidth), 28, FlxColor.fromRGB(40, 40, 40));
		bgBar.alpha = 0.6;

		fillBar = new FlxSprite(x, y);
		fillBar.makeGraphic(1, 28, color);
		fillBar.scale.x = 0;
		alpha = 0;
	}

	public function animateBar():Void
	{
		FlxTween.tween(fillBar.scale, {x: targetWidth}, 0.8, {ease: FlxEase.expoOut});
		FlxTween.tween(fillBar, {alpha: 1}, 0.2, {type: PINGPONG, loopDelay: 0.3});
	}

	override function draw():Void
	{
		bgBar?.draw();
		fillBar?.draw();
		super.draw();
	}

	override function destroy():Void
	{
		bgBar?.destroy();
		fillBar?.destroy();
		super.destroy();
	}
}
