package funkin.cache;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.media.Sound;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

// ── Compatibilidad con OpenFL antiguo / nuevo ─────────────────────────────────
#if (openfl >= "9.2.0")
import openfl.utils.Assets as OpenFLAssets;
#else
import openfl.Assets as OpenFLAssets;
#end
import animationdata.FunkinSprite;

using StringTools;

/**
 * PathsCache v4 — system of cache tricapa with prefetch asynchronous and LRU.
 *
 * ─── Mejoras v4 ──────────────────────────────────────────────────────────────
 *
 *  LRU REAL
 *    • _lruOrder: Array<String> que mantiene el orden de acceso.
 *    • Cuando _currentGraphics supera maxGraphics, evicta el menos usado.
 *    • Avoids acumulación silenciosa of textures no referenciadas.
 *
 *  PREFETCH asynchronous (desktop C++)
 *    • prefetchAsync(keys): inicia la carga de texturas en background.
 *    • isPrefetchDone(): true when all the textures are lists.
 *    • Integrado con CacheState para mostrar progreso real.
 *
 *  HIT RATE METRICS
 *    • Contadores: _hits, _misses, _rescues for diagnostic of performance.
 *    • hitRate(): porcentaje de hits sobre el total de lookups.
 *    • Visibles en el debug overlay.
 *
 *  SOPORTE MODS MEJORADO
 *    • _modPathCache: Map<String, String> para evitar rellamadas a ModManager.
 *    • resolveWithMod(id): resuelve el path real teniendo en cuenta el mod activo.
 *    • clearModPathCache(): llamar al cambiar de mod para invalidar el cache.
 *
 * ─── Layers of cache ──────────────────────────────────────────────────────────
 *
 *   PERMANENTE  — UI esencial, countdown, fonts. Nunca se destruye.
 *   CURRENT     — Assets of the session current. Is rota to the change state.
 *   PREVIOUS    — Assets of the previous session. Is rescatan or destruyen.
 *
 * ─── Compatibilidad ──────────────────────────────────────────────────────────
 *  OpenFL ≥ 9.2.0 / OpenFL < 9.2.0 (via import condicional)
 *  Flixel ≥ 5.0.0 con null-safety
 *
 * @author Cool Engine Team
 * @version 4.0.0
 */
@:access(openfl.display.BitmapData)
class PathsCache
{
	// ── Singleton ─────────────────────────────────────────────────────────────

	public static var instance(get, null):PathsCache;
	static function get_instance():PathsCache
	{
		if (instance == null) instance = new PathsCache();
		return instance;
	}

	// ── Opciones globales ─────────────────────────────────────────────────────

	public static var gpuCaching:Bool =
		#if (desktop && !hl && cpp) true #else false #end;

	public static var lowMemoryMode(default, set):Bool = false;
	static function set_lowMemoryMode(v:Bool):Bool
	{
		lowMemoryMode = v;
		if (instance != null)
		{
			// Mobile tiene RAM more limitada — limits more bajos incluso in modo normal
			#if (mobileC || android || ios)
			instance.maxGraphics = v ? 20 : 40;
			instance.maxSounds   = v ? 16 : 32;
			#else
			instance.maxGraphics = v ? 30 : 80;
			instance.maxSounds   = v ? 24 : 64;
			#end
		}
		return v;
	}

	public static var streamedMusic:Bool = false;

	/**
	 * Resolvedor opcional de paths cortos → paths completos de asset.
	 * Ejemplo: `PathsCache.pathResolver = function(k) return Paths.image(k);`
	 * Registrar desde Main o create() del primer estado.
	 * Cuando `fromAssetKey(key)` falla, se intenta con el path resuelto.
	 */
	public static var pathResolver:(String)->String = null;

	// ── Limits of cache ──────────────────────────────────────────────────────
	// Desktop: 80 texturas / 64 sonidos.
	// Mobile (Android/iOS): 40 / 32 — RAM more limitada and without swap.

	public var maxGraphics:Int = #if (mobileC || android || ios) 40 #else 80 #end;
	public var maxSounds:Int   = #if (mobileC || android || ios) 32 #else 64 #end;

	// ── Tricapa de texturas ───────────────────────────────────────────────────

	final _permanentGraphics : Map<String, FlxGraphic> = [];
	final _currentGraphics   : Map<String, FlxGraphic> = [];
	var   _previousGraphics  : Map<String, FlxGraphic> = [];

	// ── LRU de texturas current ───────────────────────────────────────────────
	// Mantiene the orden of acceso: [more old ... more reciente]
	var _lruOrder : Array<String> = [];

	// ── Tricapa de sonidos ────────────────────────────────────────────────────

	final _permanentSounds : Map<String, Sound> = [];
	final _currentSounds   : Map<String, Sound> = [];
	var   _previousSounds  : Map<String, Sound> = [];

	// ── Cache of paths of mod ─────────────────────────────────────────────────
	// Evita llamar a ModManager.resolveInMod en cada carga repetida.
	var _modPathCache : Map<String, String> = [];

	// ── Metrics of hit rate ──────────────────────────────────────────────────
	var _hits    : Int = 0;
	var _misses  : Int = 0;
	var _rescues : Int = 0; // hits rescatados desde previous

	// ── API de compatibilidad ─────────────────────────────────────────────────

	public var localTrackedAssets(get, never):Array<String>;
	inline function get_localTrackedAssets():Array<String>
	{
		final out:Array<String> = [];
		for (k in _currentGraphics.keys()) out.push(k);
		for (k in _currentSounds.keys())   out.push(k);
		return out;
	}

	public var currentTrackedGraphics(get, never):Map<String, FlxGraphic>;
	inline function get_currentTrackedGraphics() return _currentGraphics;

	public var currentTrackedSounds(get, never):Map<String, Sound>;
	inline function get_currentTrackedSounds() return _currentSounds;

	// ── Contadores O(1) ───────────────────────────────────────────────────────

	var _graphicCount : Int = 0;
	var _soundCount   : Int = 0;

	public function graphicCount():Int return _graphicCount;
	public function soundCount():Int   return _soundCount;

	static inline function _count<K,V>(m:Map<K,V>):Int {
		var n = 0; for (_ in m) n++; return n;
	}

	// ── Hit rate ──────────────────────────────────────────────────────────────

	/** Porcentaje de hits sobre el total de lookups (0.0 - 1.0). */
	public function hitRate():Float
	{
		final total = _hits + _misses;
		return total > 0 ? _hits / total : 0.0;
	}

	/** Reset of metrics. */
	public function resetMetrics():Void { _hits = 0; _misses = 0; _rescues = 0; }

	// ── API compatibilidad ────────────────────────────────────────────────────

	public function hasValidGraphic(key:String):Bool {
		var g = _permanentGraphics.get(key);
		if (g != null) return g.bitmap != null;
		g = _currentGraphics.get(key);
		if (g != null) {
			if (g.bitmap != null) return true;
			_currentGraphics.remove(key);
			_lruOrder.remove(key);
			_graphicCount--;
			return false;
		}
		g = _previousGraphics.get(key);
		if (g != null) return g.bitmap != null;
		return false;
	}

	public inline function peekGraphic(key:String):Null<FlxGraphic> return getGraphic(key);

	public function hasSound(key:String):Bool {
		if (_permanentSounds.exists(key)) return true;
		if (_currentSounds.exists(key))   return true;
		if (_previousSounds.exists(key))  return true;
		return false;
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	function new() {}

	// ═══════════════════════════════════════════════════════════════════════════
	// management of session
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Starts a new session.
	 * Los assets de current pasan a previous.
	 * The assets that is carguen now is añaden to current.
	 */
	public function beginSession():Void
	{
		// No-op: FunkinCache maneja el lifecycle via preStateSwitch/postStateSwitch.
		// PathsCache ya no destruye FlxGraphics durante cambios de estado — es solo un loader.
		trace('[PathsCache] beginSession() — no-op, FunkinCache gestiona el lifecycle');
	}

	/**
	 * Rota the layers of graphics: _current → _previous, _previous descartada.
	 * Llamar desde FunkinCache.preStateSwitch, ANTES de que el nuevo estado cargue assets.
	 *
	 * By what is necesario:
	 *   FunkinCache.clearSecondLayer() llama FlxG.bitmap.removeByKey() → g.destroy()
	 *   → g.bitmap = null over the graphics of the previous session.
	 *   Without this rotation, PathsCache._currentGraphics retiene those FlxGraphics muertos
	 *   indefinidamente. hasValidGraphic() veía the object != null and returned true.
	 *   The new state obtenía a graphic with bitmap=null, it usaba in FlxAtlasFrames,
	 *   y el primer draw → FlxDrawQuadsItem::render → null-object crash.
	 *
	 * With this rotation:
	 *   - The graphics actuales is mueven to _previousGraphics.
	 *   - Si el nuevo estado los necesita, getGraphic() los rescata a _current (siempre
	 *     que bitmap != null — si ya fueron destruidos se descartan y se recargan).
	 *   - _currentGraphics queda empty → hasValidGraphic() returns false → load clears.
	 */
	public function rotateSession():Void
	{
		// _currentGraphics y _previousGraphics son `final` — no se pueden reasignar.
		// Copiar current → previous y limpiar current en su lugar.
		_previousGraphics.clear();
		for (k => g in _currentGraphics)
			_previousGraphics.set(k, g);
		_currentGraphics.clear();
		_graphicCount = 0;
		// Nota: _permanentGraphics NO se rota — nunca se destruyen.
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// TEXTURAS
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Carga o rescata una textura con LRU eviction.
	 * Si _currentGraphics supera maxGraphics, evicta el menos usado (front del LRU).
	 */
	public function cacheGraphic(key:String):Null<FlxGraphic>
	{
		if (_currentGraphics.exists(key))
		{
			_hits++;
			_touchLRU(key);
			return _currentGraphics.get(key);
		}

		if (_previousGraphics.exists(key))
		{
			final g = _previousGraphics.get(key);
			_previousGraphics.remove(key);
			if (g != null && g.bitmap != null)
			{
				_rescues++;
				_hits++;
				_currentGraphics.set(key, g);
				_graphicCount++;
				_addToLRU(key);
				_evictIfNeeded();
				#if (cpp && !hl)
				try {
					if (FlxG.stage != null && FlxG.stage.context3D != null) {
						final tex = g.bitmap.getTexture(FlxG.stage.context3D);
						if (tex != null) {
							@:privateAccess
							if (g.bitmap.image != null) g.bitmap.disposeImage();
						}
					}
				} catch (_:Dynamic) {}
				#end
				return g;
			}
		}

		_misses++;
		final g = _loadGraphic(key, false);
		if (g != null) { _addToLRU(key); _evictIfNeeded(); }
		return g;
	}

	// ── LRU helpers ──────────────────────────────────────────────────────────

	inline function _addToLRU(key:String):Void
		_lruOrder.push(key);

	inline function _touchLRU(key:String):Void
	{
		final idx = _lruOrder.indexOf(key);
		if (idx >= 0) _lruOrder.splice(idx, 1);
		_lruOrder.push(key);
	}

	/**
	 * If _currentGraphics supera maxGraphics, evicta the entradas more antiguas.
	 * Only evicta graphics without references activas (useCount == 0, no persist, no permanent).
	 */
	function _evictIfNeeded():Void
	{
		if (_graphicCount <= maxGraphics) return;
		var evicted = 0;
		var i = 0;
		while (_graphicCount > maxGraphics && i < _lruOrder.length)
		{
			final k = _lruOrder[i];
			if (_permanentGraphics.exists(k)) { i++; continue; }
			final g = _currentGraphics.get(k);
			if (g != null && g.useCount <= 0 && !g.persist)
			{
				_currentGraphics.remove(k);
				_lruOrder.splice(i, 1);
				_graphicCount--;
				evicted++;
				// Don't destroy here — FunkinCache.clearSecondLayer() will do it safely
			}
			else i++;
		}
		if (evicted > 0)
			trace('[PathsCache] LRU evict: $evicted texturas (total=$_graphicCount/$maxGraphics)');
	}

	// ══════════════════════════════════════════════════════════════════════════
	// PREFETCH asynchronous
	// ══════════════════════════════════════════════════════════════════════════

	var _prefetchQueue   : Array<String>       = [];
	var _prefetchResults : Map<String, Bool>   = [];
	var _prefetchDone    : Bool                = true;

	/**
	 * Inicia la precarga de una lista de texturas en background (desktop C++).
	 * In otras plataformas, hace the load sincrónica normal.
	 *
	 * @param keys      Lista de claves/paths a precargar.
	 * @param onProgress Callback (loaded:Int, total:Int) llamado tras cada carga.
	 * @param onDone    Callback calldo when all the textures are lists.
	 */
	public function prefetchAsync(keys:Array<String>, ?onProgress:(Int,Int)->Void, ?onDone:()->Void):Void
	{
		if (keys == null || keys.length == 0) { if (onDone != null) onDone(); return; }

		_prefetchQueue   = keys.copy();
		_prefetchResults = [];
		_prefetchDone    = false;
		final total      = keys.length;
		var loaded       = 0;

		// En cpp (desktop Y Android) cargamos por lotes via FlxTimer para no bloquear el render loop.
		#if cpp
		final batchSize = 4;
		var batchStart  = 0;

		function loadBatch():Void
		{
			final end = Std.int(Math.min(batchStart + batchSize, total));
			for (i in batchStart...end)
			{
				final k = keys[i];
				if (!hasValidGraphic(k))
				{
					final g = cacheGraphic(k);
					_prefetchResults.set(k, g != null);
				}
				else _prefetchResults.set(k, true);
				loaded++;
				if (onProgress != null) try { onProgress(loaded, total); } catch (_:Dynamic) {}
			}
			batchStart = end;
			if (batchStart >= total)
			{
				_prefetchDone = true;
				if (onDone != null) try { onDone(); } catch (_:Dynamic) {}
			}
			else
			{
				// Next batch in the next frame
				new flixel.util.FlxTimer().start(0, function(_) loadBatch());
			}
		}
		loadBatch();
		#else
		// Plataformas without threads: load synchronous
		for (k in keys)
		{
			if (!hasValidGraphic(k)) cacheGraphic(k);
			loaded++;
			if (onProgress != null) try { onProgress(loaded, total); } catch (_:Dynamic) {}
		}
		_prefetchDone = true;
		if (onDone != null) try { onDone(); } catch (_:Dynamic) {}
		#end
	}

	/** true cuando el prefetch ha completado. */
	public function isPrefetchDone():Bool return _prefetchDone;

	/** How many assets of the last prefetch is cargaron correctly. */
	public function prefetchSuccessCount():Int
	{
		var n = 0;
		for (v in _prefetchResults) if (v) n++;
		return n;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// support mods — resolution of paths with cache
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Resuelve el path real de un asset teniendo en cuenta el mod activo.
	 * Usa _modPathCache para evitar llamadas repetidas a ModManager.
	 *
	 * @return Path del archivo en el mod, o null si no existe override en el mod.
	 */
	public function resolveWithMod(id:String):Null<String>
	{
		final cached = _modPathCache.get(id);
		if (cached != null) return cached == '' ? null : cached;

		#if sys
		try
		{
			final modPath = mods.ModManager.resolveInMod(id);
			if (modPath != null && sys.FileSystem.exists(modPath))
			{
				_modPathCache.set(id, modPath);
				return modPath;
			}
		}
		catch (_:Dynamic) {}
		#end
		_modPathCache.set(id, ''); // cache miss
		return null;
	}

	/** Invalida the cache of paths of mod (callr to the change of mod). */
	public function clearModPathCache():Void
		_modPathCache = [];


	/**
	 * Carga una textura y la marca como permanente.
	 * Usada durante the pre-cache of arranque.
	 */
	public function permanentCacheGraphic(key:String):Null<FlxGraphic>
	{
		if (_permanentGraphics.exists(key)) return _permanentGraphics.get(key);
		final g = _loadGraphic(key, true);
		if (g != null) { _permanentGraphics.set(key, g); _currentGraphics.set(key, g); }
		return g;
	}

	/** Registra a FlxGraphic already existente in the session current. */
	public function trackGraphic(key:String, graphic:FlxGraphic):Void
	{
		if (_currentGraphics.exists(key)) return;
		graphic.persist = true;
		_currentGraphics.set(key, graphic);
		_graphicCount++;
	}

	/**
	 * Rescata un FlxGraphic de _previousGraphics a _currentGraphics.
	 * Llamar cuando un atlas cacheado se reutiliza entre sesiones para
	 * avoid that its graphic sea destruido by clearPreviousSession().
	 *
	 * BUGFIX: also rescata the BitmapData subyacente in FunkinCache.
	 * Sin esto, FunkinCache.clearSecondLayer() llama dispose() sobre el
	 * BitmapData que este FlxGraphic sigue usando → graphic.bitmap = null
	 * → FlxDrawQuadsItem::render null-object crash en el primer frame.
	 */
	public function rescueFromPrevious(key:String, graphic:FlxGraphic):Void
	{
		if (_currentGraphics.exists(key) || _permanentGraphics.exists(key)) return;
		if (_previousGraphics.exists(key))
		{
			_previousGraphics.remove(key);
		}
		graphic.persist = true;
		_currentGraphics.set(key, graphic);
		_graphicCount++;
	}

	/** Devuelve un FlxGraphic buscando en todas las capas. */
	public function getGraphic(key:String, ?bitmapData:openfl.display.BitmapData, allowGPU:Bool = true):Null<FlxGraphic>
	{
		// BUGFIX: always verify bitmap != null before of return a graphic.
		// FunkinCache.clearSecondLayer() puede haber destruido the graphic (g.bitmap = null)
		// mientras PathsCache._currentGraphics sigue sosteniendo la referencia.
		// Return a graphic muerto → FlxAtlasFrames with bitmap=null → crash in first render.
		var gPerm = _permanentGraphics.get(key);
		if (gPerm != null)
		{
			if (gPerm.bitmap != null) return gPerm;
			_permanentGraphics.remove(key); // permanente destruido — limpiar y recargar
		}
		var gCur = _currentGraphics.get(key);
		if (gCur != null)
		{
			if (gCur.bitmap != null) return gCur;
			// Stale: evictar para que la siguiente carga lo recargue desde disco
			_currentGraphics.remove(key);
			_graphicCount--;
		}
		// ── RESCUE: move of previous to current for that sobreviva this session ──
		if (_previousGraphics.exists(key))
		{
			final g = _previousGraphics.get(key);
			_previousGraphics.remove(key);
			// BUGFIX: if the graphic was destruido (bitmap=null), no rescue — reload.
			if (g != null && g.bitmap != null)
			{
				_currentGraphics.set(key, g);
				_graphicCount++;
						return g;
			}
			// Caer al bloque de bitmapData / retorno nulo abajo
		}
		// If a BitmapData was supplied, create and register the graphic now
		if (bitmapData != null) {
			var g = FlxGraphic.fromBitmapData(bitmapData, false, key, true);
			if (g != null) {
				g.persist = true;
				if (allowGPU) _forceGPURender(g);
				_currentGraphics.set(key, g);
				_graphicCount++;
			}
			return g;
		}
		return null;
	}

	function _loadGraphic(key:String, permanent:Bool):Null<FlxGraphic>
	{
		// Intentar with FlxG.bitmap first (puede that Flixel already it tenga in cache propia)
		var existing = FlxG.bitmap.get(key);
		if (existing != null)
		{
			// BUGFIX critical — FlxDrawQuadsItem::render null object reference:
			// FlxG.bitmap._cache conserva entradas cuyo FlxGraphic fue destruido por
			// clearPreviousSession() (calldo from PlayState.destroy() via clearUnusedMemory).
			// destroy() llama bitmap.dispose() → bitmap = null, pero la entrada sigue en el cache.
			// If aceptamos that graphic without verify, it metemos in _currentGraphics with bitmap=null
			// → FlxDrawQuadsItem::render falla en el primer frame con null object reference.
			// Solution: if bitmap is null, remove the entry huérfana and reload from disco.
			if (existing.bitmap == null)
			{
				trace('[PathsCache] FlxGraphic orphan detectado for "$key" (bitmap=null), recargando from disco.');
				@:privateAccess FlxG.bitmap.removeKey(key);
				existing = null;
				// Caer al bloque de carga desde disco abajo
			}
			else
			{
				existing.persist = true;
				_currentGraphics.set(key, existing);
				_graphicCount++;
				// BUGFIX (crash FlxDrawQuadsItem::render):
				// FlxG.bitmap still contains FlxGraphics from the previous session —
				// no se limpian hasta postStateSwitch → clearPreviousSession().
				// Su BitmapData fue movido a bitmapData2 por moveToSecondLayer().
				// If we don't rescue it here, clearSecondLayer() will call dispose() on it
				// while this FlxGraphic (already in _currentGraphics) sigue usándolo →
				// bitmap dispuesto en el primer frame de render → crash.
						return existing;
			}
		}

		// Load via FlxGraphic.fromAssetKey — igual that V-Slice FunkinMemory.cacheTexture().
		// Is more directo that getBitmapData → fromBitmapData and funciona with all the
		// versiones of OpenFL porque delega the resolution to the pipeline nativo of Flixel.
		//
		// FALLBACK PARA MODS (build no recompilada):
		// The assets of mods existen in disco but no are in the manifest of OpenFL
		// (only is registran in compilation). fromAssetKey → Assets.getBitmapData falla
		// con "Could not find a BitmapData asset with ID mods/...". 
		// Solution: if fromAssetKey falla and the file exists in disco, cargamos the
		// BitmapData directamente con BitmapData.fromFile() y construimos el FlxGraphic.
		var g:FlxGraphic = null;
		try
		{
			g = FlxGraphic.fromAssetKey(key, false, null, true);
		}
		catch (e:Dynamic)
		{
			#if sys
			// Intento 2: carga directa desde disco (rutas de mods no compilados)
			if (FileSystem.exists(key))
			{
				trace('[PathsCache] fromAssetKey failed for "$key", intentando load directa from disco...');
				try
				{
					final bitmap = BitmapData.fromFile(key);
					if (bitmap != null)
						g = FlxGraphic.fromBitmapData(bitmap, false, key, true);
				}
				catch (e2:Dynamic) { trace('[PathsCache] Error en carga directa de "$key": $e2'); }
			}
			#end

			// Intento 3: resolve the path complete via pathResolver (ej: Paths.image)
			// Avoids the falsos "no is pudo load" when the key corto no is in the
			// manifiesto de OpenFL pero el asset existe bajo assets/images/<key>.png.
			if (g == null && pathResolver != null)
			{
				try
				{
					final resolved = pathResolver(key);
					if (resolved != null && resolved != key)
					{
						g = FlxGraphic.fromAssetKey(resolved, false, key, true);
						// g.key es (default, null) en Flixel — no se puede asignar.
						// We store it in _currentGraphics under the short key below.
					}
				}
				catch (e3:Dynamic) {}

				#if sys
				// If fromAssetKey with resolved path also failed, try disk directly
				if (g == null && pathResolver != null)
				{
					try
					{
						final resolved2 = pathResolver(key);
						if (resolved2 != null && FileSystem.exists(resolved2))
						{
							final bitmap2 = BitmapData.fromFile(resolved2);
							if (bitmap2 != null)
								g = FlxGraphic.fromBitmapData(bitmap2, false, key, true);
						}
					}
					catch (_:Dynamic) {}
				}
				#end
			}

			if (g == null)
				trace('[PathsCache] Error cargando "$key": $e');
		}

		if (g == null)
		{
			trace('[PathsCache] No se pudo cargar "$key"');
			return null;
		}

		g.persist = true;

		// GPU pre-render: llama getTexture() para registrar la textura en el pipeline de OpenFL.
		// El upload real de pixels ocurre en el PRIMER DRAW CALL del render thread.
		// no callmos disposeImage() here — the pixels deben exist until that primer draw.
		// flushGPUCache() (calldo 5 frames after via ENTER_FRAME in PlayState.create())
		// is encarga of free the pixels after of confirmar that the render ocurrió.
		_forceGPURender(g);

		_currentGraphics.set(key, g);
		_graphicCount++;
		return g;
	}

	/**
	 * Pre-carga la textura en la GPU dibujando un sprite temporal.
	 * Replicado de V-Slice FunkinMemory.forceRender() para evitar el stutter
	 * del primer frame en el que OpenGL sube la textura.
	 *
	/**
	 * Pre-sube la textura a VRAM usando getTexture() directo.
	 *
	 * El dummy FlxSprite + draw() fue eliminado: instanciar un FlxSprite fuera
	 * del render loop causa stutter durante el precacheo (especialmente al
	 * cargar 40-100 texturas en LoadingState→PlayState). Flixel sube la textura
	 * a GPU en el primer draw call real, lo que ocurre suavemente dentro del
	 * frame loop when the loading screen already is visible.
	 *
	 * getTexture() is mantiene as optimization optional for context3D
	 * disponible (desktop, no web/mobile).
	 */
	static function _forceGPURender(graphic:FlxGraphic):Void
	{
		if (graphic == null || graphic.bitmap == null) return;
		#if (desktop && !hl)
		try
		{
			if (FlxG.stage != null && FlxG.stage.context3D != null)
				graphic.bitmap.getTexture(FlxG.stage.context3D);
		}
		catch (_:Dynamic) {}
		#end
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// SONIDOS
	// ═══════════════════════════════════════════════════════════════════════════

	public function cacheSound(key:String):Null<Sound>
	{
		if (_currentSounds.exists(key)) return _currentSounds.get(key);

		// Rescatar de previous
		if (_previousSounds.exists(key))
		{
			final s = _previousSounds.get(key);
			_previousSounds.remove(key);
			if (s != null) { _currentSounds.set(key, s); _soundCount++; }
			return s;
		}

		return _loadSound(key, false);
	}

	public function permanentCacheSound(key:String):Null<Sound>
	{
		if (_permanentSounds.exists(key)) return _permanentSounds.get(key);
		final s = _loadSound(key, true);
		if (s != null) { _permanentSounds.set(key, s); _currentSounds.set(key, s); }
		return s;
	}

	public function getSound(key:String, ?sound:Sound, safety:Bool = false):Null<Sound>
	{
		if (_permanentSounds.exists(key)) return _permanentSounds.get(key);
		if (_currentSounds.exists(key))   return _currentSounds.get(key);
		if (_previousSounds.exists(key))  return _previousSounds.get(key);
		if (sound != null) {
			_currentSounds.set(key, sound);
			_soundCount++;
			return sound;
		}
		return null;
	}

	function _loadSound(key:String, permanent:Bool):Null<Sound>
	{
		var sound:Sound = null;
		try
		{
			if (OpenFLAssets.exists(key, openfl.utils.AssetType.SOUND)
			 || OpenFLAssets.exists(key, openfl.utils.AssetType.MUSIC))
				sound = OpenFLAssets.getSound(key);
		}
		catch (e:Dynamic) { trace('[PathsCache] Error de audio "$key": $e'); return null; }

		if (sound == null) return null;

		_currentSounds.set(key, sound);
		_soundCount++;
		return sound;
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// release of memory
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Destroys the assets of the previous session that no fueron rescatados.
	 * Callr after of `beginSession()` when the new session already cargó its assets.
	 */
	/**
	 * DEPRECATED — the destruction of assets the hace FunkinCache.clearSecondLayer()
	 * via FlxG.bitmap.removeByKey (modelo Codename). Mantener como no-op para
	 * compatibilidad con Paths.clearPreviousSession() en PlayState/LoadingState.
	 */
	public function clearPreviousSession():Void
	{
		// No-op: FunkinCache.postStateSwitch ya llama clearSecondLayer() que
		// use FlxG.bitmap.removeByKey for destroy the graphics no rescatados.
		// Destroy FlxGraphics here (as hacía before) causaba the crash porque
		// is destruían after of that the sprites of the new state the cargaron.
		trace('[PathsCache] clearPreviousSession() — no-op, FunkinCache manages the destruction');
	}

	

	function _clearPreviousGraphics():Void
	{
		// No-op: FunkinCache.clearSecondLayer() via FlxG.bitmap.removeByKey() handles the destruction.
		// Destroy FlxGraphics here causaba crashes porque ocurría after of that
		// the sprites of the new state already tenían references to those graphics.
		_previousGraphics.clear();
	}

	function _clearPreviousSounds():Void
	{
		for (key => sound in _previousSounds)
		{
			if (_permanentSounds.exists(key)) { _previousSounds.remove(key); continue; }
			if (sound == null) { _previousSounds.remove(key); continue; }
			try { OpenFLAssets.cache.removeSound(key); } catch(_) {}
			_previousSounds.remove(key);
		}

		// Clear the libraries of songs completas — igual that V-Slice purgeSoundCache().
		// removeSound() por key individual no libera los bundles de audio de OpenFL.
		try { OpenFLAssets.cache.clear('songs'); }  catch(_) {}
		try { OpenFLAssets.cache.clear('music'); }  catch(_) {}

		if (_soundCount > maxSounds) _soundCount = _count(_currentSounds);
	}

	/** Limpieza completa (al salir del juego). */
	public function destroy():Void
	{
		_clearPreviousGraphics();
		for (k => g in _currentGraphics)
		{
			if (_permanentGraphics.exists(k)) continue;
			if (g == null) continue;
			FlxG.bitmap.remove(g);
			g.persist = false;
			try { g.destroy(); } catch(_) {}
		}
		_currentGraphics.clear();
		_permanentGraphics.clear();
		_currentSounds.clear();
		_permanentSounds.clear();
		_previousSounds.clear();
		_graphicCount = 0;
		_soundCount   = 0;
	}

	/** Limpieza of assets of a contexto specific (p.ej. "freeplay"). */
	public function clearContext(contextTag:String):Void
	{
		final toRemove:Array<String> = [];

		@:privateAccess
		if (FlxG.bitmap._cache != null)
		{
			@:privateAccess
			for (k in FlxG.bitmap._cache.keys())
			{
				if (!k.contains(contextTag)) continue;
				if (_permanentGraphics.exists(k) || k.contains('fonts')) continue;
				toRemove.push(k);
			}
		}

		for (k in toRemove)
		{
			final g = FlxG.bitmap.get(k);
			if (g != null) { g.destroy(); @:privateAccess FlxG.bitmap.removeKey(k); }
			_currentGraphics.remove(k);
			try { OpenFLAssets.cache.clear(k); } catch(_) {}
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// COMPAT — methods esperados by Paths.hx and the resto of the engine
	// ═══════════════════════════════════════════════════════════════════════════

	/** Lista de claves pendientes de marcar como permanentes. */
	var _pendingExclusions:Array<String> = [];

	/**
	 * Marca una clave como permanente (nunca se evicta).
	 * If the asset already is loaded in current, it promueve to permanent.
	 * If still no is loaded, it anota for promoverlo when is cargue.
	 */
	public function addExclusion(key:String):Void
	{
		final g = _currentGraphics.get(key);
		if (g != null) { _permanentGraphics.set(key, g); return; }
		final s = _currentSounds.get(key);
		if (s != null) { _permanentSounds.set(key, s); return; }
		if (!_pendingExclusions.contains(key))
			_pendingExclusions.push(key);
	}

	/** Libera assets of the previous session. FunkinCache handles the destruction actual. */
	public function clearStoredMemory():Void
	{
		// FunkinCache.clearSecondLayer() ya destruye via removeByKey en postStateSwitch.
		// This function queda as no-op for compatibility with Paths.clearStoredMemory().
		try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}
	}

	/** Destroys graphics without uso and forces GC. */
	public function clearUnusedMemory():Void
	{
		try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}
		try { openfl.system.System.gc(); } catch (_:Dynamic) {}
		#if cpp
		cpp.vm.Gc.run(true);
		try { cpp.vm.Gc.compact(); } catch (_:Dynamic) {}
		#end
		#if hl hl.Gc.major(); #end
	}

	/**
	 * GPU caching post-load flush: libera la RAM (imagen CPU) de todos los
	 * graphics of the session current that already hayan sido subidos to VRAM.
	 *
	 * Callr after of that the state haya completado its create() and haya
	 * rendering to the menos a frame — guarantees that context3D is listo
	 * y que todas las texturas hayan sido subidas por OpenFL.
	 *
	 * Solo efectivo en desktop C++ (requiere OpenGL context3D).
	 * Libera típicamente 50-400 MB of RAM in songs with muchos sprites.
	 */
	public function flushGPUCache():Void
	{
		#if (cpp && !hl)
		if (FlxG.stage == null || FlxG.stage.context3D == null) return;
		final ctx = FlxG.stage.context3D;
		var released = 0;
		var skipped  = 0;
		for (g in _currentGraphics)
		{
			if (g == null || g.bitmap == null) continue;
			// Nunca liberar permanentes — se reutilizan en cada state sin recarga
			if (_permanentGraphics.exists(g.key)) continue;
			// Si ya fue dispuesto (bitmap.image == null), saltear
			@:privateAccess
			if (g.bitmap.image == null) continue;
			try
			{
				final tex = g.bitmap.getTexture(ctx);
				if (tex != null)
				{
					g.bitmap.disposeImage(); // libera pixels CPU manteniendo textura GPU
					released++;
				}
				else
				{
					skipped++;
				}
			}
			catch (_:Dynamic) {}
		}
		if (released > 0 || skipped > 0)
			trace('[PathsCache] flushGPUCache: $released textures liberadas to VRAM-only, $skipped without texture GPU still');
		#end
	}

	/**
	 * Version selectiva: libera RAM of a texture specific if already was subida to VRAM.
	 * Useful for free sprites of character/stage individualmente.
	 */
	public function flushGPUCacheFor(key:String):Void
	{
		#if (cpp && !hl)
		if (FlxG.stage == null || FlxG.stage.context3D == null) return;
		var g = _currentGraphics.get(key);
		if (g == null) g = _previousGraphics.get(key);
		if (g == null || g.bitmap == null) return;
		try
		{
			final tex = g.bitmap.getTexture(FlxG.stage.context3D);
			@:privateAccess
			if (tex != null && g.bitmap.image != null) g.bitmap.disposeImage();
		}
		catch (_:Dynamic) {}
		#end
	}

	/** Limpieza total — alias de destroy() para cambio de mod / reinicio. */
	public function forceFullClear():Void
		destroy();

	/** Limpia assets de gameplay (prefijos char_, stage_, skin_). */
	public function clearGameplayAssets():Void
	{
		for (prefix in ['char_', 'stage_', 'skin_'])
			clearContext(prefix);
	}

	/** String compacto para el overlay de debug. */
	public function debugString():String
		return 'Cache: ${_count(_currentGraphics)} tex / ${_count(_currentSounds)} snd';

	/** Stats completos (alias de getStats). */
	public function fullStats():String
		return getStats();

	// ═══════════════════════════════════════════════════════════════════════════
	// STATS / DEBUG
	// ═══════════════════════════════════════════════════════════════════════════

	public function getStats():String
	{
		final total  = _hits + _misses;
		final hr     = total > 0 ? '${Math.round(hitRate() * 100)}%' : 'n/a';
		return '[PathsCache v4] Permanent: ${_count(_permanentGraphics)} tex / ${_count(_permanentSounds)} snd'
			+ ' | Current: ${_count(_currentGraphics)} tex (LRU ${_lruOrder.length}) / ${_count(_currentSounds)} snd'
			+ ' | Previous: ${_count(_previousGraphics)} tex / ${_count(_previousSounds)} snd'
			+ ' | HitRate: $hr (hits=$_hits miss=$_misses rescue=$_rescues)';
	}
}
