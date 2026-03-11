#pragma header

uniform float uTime;

void main()
{
    vec2 uv = openfl_TextureCoordv;

    // Tiempo quantizado: salta cada ~8 frames (a 60fps = ~7 saltos/seg)
    float fps = 8.0;
    float t = floor(uTime * fps) / fps;

    vec2 sc = gl_FragCoord.xy / openfl_TextureSize;

    float offX = sin(sc.y * 6.0 + t * 0.6) * 0.003;
    float offY = sin(sc.x * 5.0 + t * 0.45) * 0.002;
    float offX2 = sin(sc.y * 3.0 + sc.x * 2.5 + t * 0.4) * 0.0015;
    float offY2 = sin(sc.x * 2.5 + sc.y * 2.0 + t * 0.35) * 0.001;

    vec2 rawOffset = vec2(offX + offX2, offY + offY2);

    // Snapear el offset a pasos de 2px en pantalla
    vec2 pixelStep = 2.0 / openfl_TextureSize;
    vec2 snappedOffset = floor(rawOffset / pixelStep) * pixelStep;

    vec2 uvWarped = uv + snappedOffset;

    gl_FragColor = flixel_texture2D(bitmap, uvWarped);
}