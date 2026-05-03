// assets/scripts/events/characters.hx
// Eventos de personajes built-in portados a HScript.
// ── Hey! ──────────────────────────────────────────────────────
// value1 = target: "bf" | "gf" | (vacío = ambos)
registerEvent("Hey!", function(v1, v2, time) {
	var g = PlayState.instance;
	if (g == null)
		return false;
	var target = v1 != null ? StringTools.toLowerCase(StringTools.trim(v1)) : '';

	if (target == 'bf' || target == 'boyfriend' || target == '')
		if (g.characterController != null)
			g.characterController.playSpecialAnim(bf, 'hey');

	if (target == 'gf' || target == 'girlfriend' || target == '')
		if (g.characterController != null)
			g.characterController.playSpecialAnim(gf, 'cheer');

	return false;
});

// ── Play Animation ────────────────────────────────────────────
// value1 = target: player | opponent | gf  (aliases: bf, dad, girlfriend)
// value2 = nombre de la animación (ej "singLEFT", "idle")
registerEvent("Play Animation", function(v1, v2, time) {
	var g = PlayState.instance;
	if (g == null)
		return false;
	var target = v1 != null ? StringTools.toLowerCase(StringTools.trim(v1)) : '';
	var anim = v2 != null ? StringTools.trim(v2) : '';
	if (anim == '')
		return false;

	if (target == 'player' || target == 'bf' || target == 'boyfriend') {
		if (g.characterController != null)
			g.characterController.playSpecialAnim(bf, anim);
	} else if (target == 'opponent' || target == 'dad' || target == 'enemy') {
		if (g.characterController != null)
			g.characterController.playSpecialAnim(dad, anim);
	} else if (target == 'gf' || target == 'girlfriend') {
		if (g.characterController != null)
			g.characterController.playSpecialAnim(gf, anim);
	}

	return false;
});

// ── Set GF Speed ──────────────────────────────────────────────
// value1 = velocidad de baile (int, mínimo 1)
//
// Requiere que PlayState exponga gfSpeed como campo público.
registerEvent("Set GF Speed", function(v1, v2, time) {
	var g = PlayState.instance;
	if (g == null)
		return false;
	var speed = Std.parseInt(v1);
	if (speed == null || speed < 1)
		speed = 1;

	// g.gfSpeed = speed;
	trace('[Event] Set GF Speed: ' + speed);
	return false;
});
