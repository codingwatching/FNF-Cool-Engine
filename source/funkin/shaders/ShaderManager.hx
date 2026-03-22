package funkin.shaders;

/**
 * Alias de compatibilidad — toda la lógica vive en shaders.ShaderManager.
 * Mantener este typedef permite que los archivos que importen
 * `funkin.shaders.ShaderManager` sigan compilando sin ningún cambio.
 */
typedef ShaderManager = shaders.ShaderManager;
