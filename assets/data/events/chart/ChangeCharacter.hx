/**
 * ChangeCharacter.hx
 * Handler for the "Change Character" / "Swap Character" event.
 *
 * Event parameters (v1, v2):
 *   v1 = slot → "bf" / "boyfriend" / "player"
 *              "dad" / "opponent"
 *              "gf" / "girlfriend"
 *   v2 = name of the new character (must exist in characters/)
 */
function onTrigger(v1, v2, time)
{
    if (game == null || v1 == null || v1 == '' || v2 == null || v2 == '')
        return false;

    // Resolvemos el slot a partir de v1
    var slotLow = v1.toLowerCase();
    var target  = null;

    if (slotLow == 'bf' || slotLow == 'boyfriend' || slotLow == 'player')
        target = game.boyfriend;
    else if (slotLow == 'dad' || slotLow == 'opponent')
        target = game.dad;
    else if (slotLow == 'gf' || slotLow == 'girlfriend')
        target = game.gf;

    if (target == null)
    {
        trace('ChangeCharacter: slot "' + v1 + '" no reconocido.');
        return false;
    }

    // ── OPTIMIZACIÓN 1: skip si ya es el mismo personaje ─────────────────────
    // Evita reconstruir animaciones y recargar assets innecesariamente.
    // reloadCharacter() también tiene este guard, pero hacerlo aquí evita
    // incluso la llamada al método y el precacheo redundante.
    if (target.curCharacter == v2)
    {
        trace('ChangeCharacter: ' + v1 + ' ya es "' + v2 + '", skip.');
        return false;
    }

    // ── OPTIMIZACIÓN 2: safety precache antes del cambio ─────────────────────
    // Normalmente EventManager._precacheChangeCharacters() ya habrá creado
    // un dummy pinned en _precachePool al inicio de la canción, manteniendo
    // las texturas del personaje ancladas en VRAM hasta este momento.
    // Este guard protege dos casos edge:
    //   a) Evento disparado dinámicamente via fireEvent() desde un script.
    //   b) El LRU de FunkinSprite haya purgado la textura entre el precacheo
    //      y el momento en que llega el evento (canciones muy largas con muchos assets).
    // NOTA: precacheCharacter() ya NO es no-op cuando _dataCache tiene la entrada.
    // Siempre crea el dummy pin si no existe uno en el pool, asegurando que las
    // texturas queden en VRAM incluso si el JSON del personaje ya está cacheado.
    funkin.gameplay.objects.character.Character.precacheCharacter(v2);

    // ── Cambio real ───────────────────────────────────────────────────────────
    // reloadCharacter internamente: libera atlases del anterior → limpia anims
    // → loadCharacterData (hit de caché) → characterLoad (hit de caché de frames).
    target.reloadCharacter(v2);

    // Actualizar iconos del HUD
    if (game.uiManager != null && game.boyfriend != null && game.dad != null)
        game.uiManager.setIcons(game.boyfriend.healthIcon, game.dad.healthIcon);

    trace('ChangeCharacter: ' + v1 + ' → ' + v2);

    // Devolver false = el built-in también corre (llama onCharacterChange
    // en otros scripts que puedan estar escuchando).
    return false;
}
