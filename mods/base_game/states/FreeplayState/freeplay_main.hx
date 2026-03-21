/**
 * FREEPLAY — Filtro por personaje leyendo metadata V-Slice
 * mods/{tuMod}/states/freeplaystate/main.hx
 *
 * Lee songVariations + player de cada metadata para decidir quién ve qué.
 * No requiere ningún JSON de configuración extra.
 */

var selectedChar = 'bf';
var _created     = false;
var _hintText    = null;
var _goingToChar = false;
var _allChars    = [];
var _metaCache   = {};

// ═══════════════════════════════════════════════════════════════════
//  Carga de personajes
// ═══════════════════════════════════════════════════════════════════

function _loadAllChars()
{
	var chars = [];
	try
	{
		var content = Paths.getText('data/charSelectChars.json');
		if (content == null || content == '') return chars;
		var sb = content.indexOf('[');
		var se = content.lastIndexOf(']');
		if (sb < 0 || se < 0) return chars;
		var s = content.substring(sb + 1, se);
		var tokens = [];
		var depth = 0; var cur = ''; var si = 0;
		while (si < s.length)
		{
			var ch = s.charAt(si); si++;
			if      (ch == '{') { depth++; cur += ch; }
			else if (ch == '}') { depth--; cur += ch; }
			else if (ch == ',' && depth == 0) { tokens.push(cur); cur = ''; }
			else cur += ch;
		}
		if (cur != '') tokens.push(cur);
		for (tok in tokens)
		{
			var t = tok.split(' ').join('').split('\t').join('')
			            .split('\n').join('').split('\r').join('');
			if (t == 'null' || t == '') continue;
			var cId = null;
			if (t.charAt(0) == '{')
			{
				var ki = t.indexOf('"id"');
				if (ki >= 0)
				{
					var rest = t.substring(ki + 4);
					var ci2 = rest.indexOf(':'); if (ci2 < 0) continue;
					rest = rest.substring(ci2 + 1);
					var q1 = rest.indexOf('"'); if (q1 < 0) continue;
					rest = rest.substring(q1 + 1);
					var q2 = rest.indexOf('"'); if (q2 < 0) continue;
					cId = rest.substring(0, q2);
				}
			}
			else cId = t.split('"').join('').split("'").join('');
			if (cId != null && cId != '' && cId != 'null') chars.push(cId);
		}
	}
	catch (e:Dynamic) { trace('[FreeplayFilter] Error cargando chars: ' + e); }
	return chars;
}

// ═══════════════════════════════════════════════════════════════════
//  Búsqueda de carpetas de canciones
//  Busca en TODOS los mods habilitados (no solo el activo).
//  mod.isActive() puede ser false aunque el mod base esté cargado.
// ═══════════════════════════════════════════════════════════════════

function _songDirs(songName)
{
	var fl = songName.toLowerCase();
	// Variantes del nombre: con espacios, con guiones, sin espacios
	var names = [fl];
	var withDash = fl.split(' ').join('-');
	var withSpace = fl.split('-').join(' ');
	if (names.indexOf(withDash) < 0)  names.push(withDash);
	if (names.indexOf(withSpace) < 0) names.push(withSpace);

	var roots = [];

	// Todos los mods habilitados
	try
	{
		var installed = ModManager.installedMods;
		if (installed != null)
		{
			for (m in installed)
			{
				if (m == null || m.id == null) continue;
				if (!ModManager.isEnabled(m.id)) continue;
				var root = ModManager.MODS_FOLDER + '/' + m.id;
				if (roots.indexOf(root) < 0) roots.push(root);
			}
		}
	}
	catch (e:Dynamic) {}

	// Mod activo al principio si no está ya
	if (mod.isActive())
	{
		var mr = mod.root();
		if (roots.indexOf(mr) < 0) roots.unshift(mr);
	}

	var dirs = [];
	for (mr in roots)
		for (n in names)
		{
			dirs.push(mr + '/songs/' + n);
			dirs.push(mr + '/assets/songs/' + n);
		}
	for (n in names)
		dirs.push('assets/songs/' + n);

	return dirs;
}

// ═══════════════════════════════════════════════════════════════════
//  Lectura de metadata V-Slice
// ═══════════════════════════════════════════════════════════════════

function _readVSliceMeta(songName, variation)
{
	var fl = songName.toLowerCase();
	var nameVariants = [fl, fl.split(' ').join('-'), fl.split('-').join(' ')];

	for (dir in _songDirs(songName))
	{
		if (!FileSystem.exists(dir)) continue;
		for (nv in nameVariants)
		{
			var fileName = variation != null
				? nv + '-metadata-' + variation + '.json'
				: nv + '-metadata.json';
			var path = dir + '/' + fileName;
			if (!FileSystem.exists(path)) continue;
			try
			{
				var raw = File.read(path);
				if (raw != null && raw != '')
					return Json.parse(raw);
			}
			catch (e:Dynamic) {}
		}
	}
	return null;
}

/**
 * Devuelve { basePlayer, variations: [{id, player}] }
 * Con caché para no releer en cada cambio de selección.
 */
function _songInfo(songName)
{
	var key = songName.toLowerCase();
	if (Reflect.hasField(_metaCache, key))
		return Reflect.field(_metaCache, key);

	var info = { basePlayer: null, variations: [] };
	try
	{
		var base = _readVSliceMeta(songName, null);
		if (base != null)
		{
			info.basePlayer = base.playData.characters.player;
			var sv = base.playData.songVariations;
			if (sv != null)
				for (varId in sv)
				{
					var vm = _readVSliceMeta(songName, varId);
					var vp = null;
					if (vm != null) try { vp = vm.playData.characters.player; } catch (e:Dynamic) {}
					info.variations.push({ id: varId, player: vp });
				}
		}
	}
	catch (e:Dynamic)
	{
		trace('[FreeplayFilter] Error metadata "' + songName + '": ' + e);
	}

	trace('[FreeplayFilter] songInfo "' + songName + '" → player='
		+ info.basePlayer + ' vars=' + info.variations.length);
	Reflect.setField(_metaCache, key, info);
	return info;
}

/** "pico-playable" matchea con "pico" */
function _playerMatch(player, charId)
{
	if (player == null || charId == null) return false;
	if (player == charId) return true;
	var p = charId + '-';
	return player.length > p.length && player.substr(0, p.length) == p;
}

// ═══════════════════════════════════════════════════════════════════
//  preFilterSongs
// ═══════════════════════════════════════════════════════════════════

function preFilterSongs()
{
	selectedChar = (save != null && save.selectedBF != null && save.selectedBF != '')
		? save.selectedBF : 'bf';

	if (freeplayData == null || freeplayData.songs == null) return;

	_allChars  = _loadAllChars();
	_metaCache = {};
	if (_allChars.length == 0) _allChars = ['bf', 'pico'];

	var songs    = freeplayData.songs;
	var filtered = [];
	var total    = songs.length;

	for (song in songs)
	{
		if (song == null || song.name == null) continue;
		var info = _songInfo(song.name);

		// Sin metadata → canción compartida
		if (info.basePlayer == null && info.variations.length == 0)
		{
			filtered.push(song);
			continue;
		}

		// ¿Es el player base?
		if (_playerMatch(info.basePlayer, selectedChar))
		{
			filtered.push(song);
			continue;
		}

		// ¿Tiene variación para este personaje?
		for (v in info.variations)
			if (_playerMatch(v.player, selectedChar))
			{
				filtered.push(song);
				break;
			}
	}

	freeplayData.songs = filtered;
	trace('[FreeplayFilter] Char: ' + selectedChar
		+ ' | ' + total + ' → ' + filtered.length);
}

// ═══════════════════════════════════════════════════════════════════
//  onDifficultyStuffBuilt
//
//  Usa songVariations para conocer TODAS las variantes (bf, erect, etc.).
//  Muestra solo las diffs del personaje activo, o las base si no tiene variante.
// ═══════════════════════════════════════════════════════════════════

function onDifficultyStuffBuilt(songName, diffs)
{
	if (diffs == null || diffs.length == 0) return diffs;

	if (_allChars == null || _allChars.length == 0)
	{
		_allChars = _loadAllChars();
		if (_allChars.length == 0) _allChars = ['bf', 'pico'];
	}

	var info = _songInfo(songName);

	// Recopilar todos los IDs de variación conocidos (bf, erect, nightmare, etc.)
	var allVariationIds = [];
	for (v in info.variations)
		if (v.id != null && allVariationIds.indexOf(v.id) < 0)
			allVariationIds.push(v.id);
	// También incluir todos los charIds como posibles variantes de char
	for (c in _allChars)
		if (allVariationIds.indexOf(c) < 0)
			allVariationIds.push(c);

	var mySuf = '-' + selectedChar;

	// ¿Tiene el personaje actual una variante? Buscar por metadata primero, luego por sufijo
	var myVariantId = null;
	for (v in info.variations)
		if (_playerMatch(v.player, selectedChar))
		{ myVariantId = v.id; break; }

	if (myVariantId == null)
		for (pair in diffs)
		{
			var s = pair[1];
			if (s == null) continue;
			if (s.length >= mySuf.length && s.substr(s.length - mySuf.length) == mySuf)
			{ myVariantId = selectedChar; break; }
		}

	var allSuf = [];
	for (p in diffs) allSuf.push(p[1]);
	trace('[FreeplayFilter] onDiffBuilt "' + songName + '" char=' + selectedChar
		+ ' myVariant=' + myVariantId
		+ ' knownVars=[' + allVariationIds.join(',') + ']'
		+ ' diffs=[' + allSuf.join(',') + ']');

	var myDiffs   = [];
	var baseDiffs = [];

	for (pair in diffs)
	{
		var suffix = pair[1];
		if (suffix == null) suffix = '';

		// ¿Pertenece a la variante del personaje activo?
		if (myVariantId != null)
		{
			var vSuf = '-' + myVariantId;
			if (suffix.length >= vSuf.length
				&& suffix.substr(suffix.length - vSuf.length) == vSuf)
			{ myDiffs.push(pair); continue; }
		}

		// ¿Pertenece a alguna variante conocida (de cualquier char/erect/etc.)?
		var isAnyVariant = false;
		for (vid in allVariationIds)
		{
			var vSuf2 = '-' + vid;
			if (suffix.length >= vSuf2.length
				&& suffix.substr(suffix.length - vSuf2.length) == vSuf2)
			{ isAnyVariant = true; break; }
		}

		// Solo pasa si es diff base pura
		if (!isAnyVariant)
			baseDiffs.push(pair);
	}

	trace('[FreeplayFilter] my=' + myDiffs.length + ' base=' + baseDiffs.length);

	if (myDiffs.length > 0)   return myDiffs;
	if (baseDiffs.length > 0) return baseDiffs;
	return diffs;
}

// ═══════════════════════════════════════════════════════════════════
//  onCreate
// ═══════════════════════════════════════════════════════════════════

function onCreate()
{
	if (_created) return;
	_created = true;
	_hintText = new FlxText(0, FlxG.height - 30, FlxG.width,
		'TAB - cambiar personaje  [' + selectedChar.toUpperCase() + ']');
	_hintText.color     = 0xFFFFFFFF;
	_hintText.alpha     = 0.7;
	_hintText.alignment = 'center';
	_hintText.scrollFactor.set(0, 0);
	ui.add(_hintText);
}

// ═══════════════════════════════════════════════════════════════════
//  onUpdate — TAB → CharSelect
// ═══════════════════════════════════════════════════════════════════

function onUpdate(dt)
{
	if (_goingToChar) return;
	if (FlxG.keys.justPressed.TAB)
	{
		_goingToChar = true;
		FlxG.camera.flash(0xFFFFFFFF, 0.25);
		ui.timer(0.25, function(_) {
			ui.switchStateInstance(new ScriptableState('charSelect'));
		});
	}
}

function onSelectionChanged(idx) {}
function onDifficultyChanged(idx) {}
