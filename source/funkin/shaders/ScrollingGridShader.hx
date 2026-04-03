package funkin.shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * ScrollingGridShader — Tablero de ajedrez que scrollea en diagonal (↘).
 *
 * Cuadros alternados: negro con poco alpha / totalmente transparente.
 * El movimiento va de izquierda-arriba hacia abajo-derecha.
 *
 * Uso:
 *   var gridShader = new ScrollingGridShader();
 *   gridSprite.shader = gridShader;
 *   // En update():
 *   gridShader.uTime.value[0] += elapsed;
 */
class ScrollingGridShader extends FlxShader
{
	@:glFragmentSource("
		#pragma header

		uniform float uTime;
		uniform float uCellSize; // cuantas celdas caben a lo ancho (default 12)
		uniform float uSpeed;    // velocidad del scroll diagonal (default 0.08)
		uniform float uAlpha;    // alpha de los cuadros negros (default 0.18)

		void main()
		{
			vec2 uv = openfl_TextureCoordv;

			// Desplazar diagonalmente: x e y avanzan igual -> direction (1,1)
			float offset = uTime * uSpeed;
			vec2 scrolled = uv + vec2(offset, offset);

			// Escalar al espacio de celdas
			vec2 cell = floor(scrolled * uCellSize);

			// Tablero de ajedrez: suma par = negro, impar = transparente
			float checker = mod(cell.x + cell.y, 2.0);

			// checker == 1 -> cuadro negro con alpha; checker == 0 -> invisible
			float a = checker * uAlpha;

			gl_FragColor = vec4(0.0, 0.0, 0.0, a);
		}
	")

	public function new()
	{
		super();
		uTime.value     = [0.0];
		uCellSize.value = [12.0];
		uSpeed.value    = [0.08];
		uAlpha.value    = [0.18];
	}
}
