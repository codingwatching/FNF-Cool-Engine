# Carpeta de Eventos — data/events/

Esta carpeta contiene las definiciones de eventos del engine organizadas por contexto.

## Estructura de carpetas

```
data/events/
  chart/        ← Eventos que se disparan durante el gameplay (Chart Editor)
  cutscene/     ← Eventos para SpriteCutscene
  playstate/    ← Eventos para el PlayState Editor
  modchart/     ← Eventos para el Modchart Editor
  global/       ← Visible y activo en TODOS los contextos
```

## Formato de evento — archivos planos

El nombre del archivo (sin extensión) = nombre del evento.

```
chart/
  Camera Follow.json    ← configuración UI del editor
  Camera Follow.hx      ← handler HScript (opcional)
  Camera Follow.lua     ← handler Lua (opcional)
```

## Formato de evento — carpeta por evento

```
chart/
  My Custom Event/
    event.json          ← (o config.json)
    handler.hx          ← (o My Custom Event.hx)
    handler.lua         ← (o My Custom Event.lua)
```

## Formato del JSON (event.json o EventName.json)

```json
{
  "name": "My Event",
  "description": "Hace algo genial en el gameplay.",
  "color": "#88FF88",
  "context": ["chart"],
  "aliases": ["my event", "ME"],
  "params": [
    {
      "name": "Target",
      "type": "DropDown(bf,dad,gf)",
      "defaultValue": "bf",
      "description": "Personaje objetivo"
    },
    {
      "name": "Duration",
      "type": "Float(0,10)",
      "defaultValue": "1.0",
      "description": "Duración en segundos"
    },
    {
      "name": "Loop",
      "type": "Bool",
      "defaultValue": "false",
      "description": "¿Repetir el efecto?"
    },
    {
      "name": "Value",
      "type": "Int(0,100)",
      "defaultValue": "50",
      "description": "Valor entero"
    },
    {
      "name": "Label",
      "type": "String",
      "defaultValue": "",
      "description": "Texto libre"
    }
  ]
}
```

### Tipos de parámetro soportados

| Tipo JSON          | Descripción                          |
|--------------------|--------------------------------------|
| `"String"`         | Campo de texto libre                 |
| `"Bool"`           | Dropdown true/false                  |
| `"Int"`            | Número entero                        |
| `"Int(min,max)"`   | Entero con rango                     |
| `"Float"`          | Número decimal                       |
| `"Float(min,max)"` | Decimal con rango                    |
| `"DropDown(a,b,c)"`| Dropdown con opciones fijas          |
| `"Color"`          | Campo de color hex (ej: `#FFFFFF`)   |

### Contextos disponibles

| Contexto     | Descripción                              |
|--------------|------------------------------------------|
| `"chart"`    | Chart Editor + durante el gameplay       |
| `"cutscene"` | Editor de SpriteCutscene                 |
| `"playstate"`| PlayState Editor                         |
| `"modchart"` | Modchart Editor                          |
| `"global"`   | Todos los editores y contextos           |

Un evento puede tener múltiples contextos: `"context": ["chart", "modchart"]`

## Handlers de script

El handler recibe el evento cuando se dispara. Puede retornar `true` para
**cancelar el built-in** del engine, o `false`/`nil` para dejar que también corra.

### HScript (My Event.hx)

```haxe
// Variables disponibles: v1, v2, time, game
// game = PlayState.instance (puede ser null fuera de gameplay)

function onTrigger(v1, v2, time) {
    trace('My Event disparado! v1=' + v1 + ' v2=' + v2);
    // Retorna false para que el built-in también corra (si existe)
    // Retorna true para cancelar el built-in
    return false;
}

// También compatible con el callback de scripts globales:
function onEvent(name, v1, v2, time) {
    if (name == 'My Event') {
        // lógica aquí
    }
    return false;
}

// Llamado al cargar el handler
function onCreate() {
    trace('Handler de My Event cargado!');
}

// Llamado al descargar (PlayState.destroy)
function onDestroy() {
    trace('Handler descargado');
}
```

### Lua (My Event.lua)

```lua
-- Variables disponibles: v1, v2, time
-- game accesible vía getProperty / playState global

function onTrigger(v1, v2, time)
    trace("My Event: " .. tostring(v1) .. " | " .. tostring(v2))
    return false  -- false = también corre el built-in
end

function onCreate()
    trace("Handler cargado!")
end

function onDestroy()
    trace("Handler descargado")
end
```

## Prioridad de dispatch (orden de ejecución)

1. Scripts globales → `onEvent(name, v1, v2, time)` — si retorna `true`, cancela todo lo siguiente
2. Handlers custom → `registerCustomEvent()` / `registerEvent()` — si retorna `true`, cancela lo siguiente
3. Handler por-evento → `onTrigger(v1, v2, time)` en el script de la carpeta `data/events/` — si retorna `true`, cancela lo siguiente
4. Built-in del engine (`EventManager._handleBuiltin`)

## Uso desde scripts

### HScript

```haxe
// Disparar un evento
events.fire("My Event", "bf", "1.5");

// Escuchar un evento
events.on("My Event", function(v1, v2, time) {
    trace('Recibido: ' + v1);
    return false;
});

// Registrar un evento nuevo con su definición
events.register({
    name: "My New Event",
    description: "Hace algo",
    color: 0xFF88FF88,
    contexts: ["chart"],
    params: [
        { name: "Target", type: "String", defaultValue: "bf" }
    ]
});

// Listar eventos de un contexto
var chartEvents = events.list("chart");
```

### Lua

```lua
-- Disparar
triggerEvent("My Event", "bf", "1.5")

-- Escuchar (vía onEvent callback global)
function onEvent(name, v1, v2, time)
    if name == "My Event" then
        trace("Recibido: " .. v1)
        return false
    end
end

-- Listar eventos
local names = listEvents("chart")
for i, name in ipairs(names) do
    trace(name)
end

-- Obtener definición
local def = getEventDef("Camera Follow")
if def then
    trace(def.name)
    trace(def.description)
    trace(#def.params .. " params")
end

-- Registrar un nuevo evento
registerEventDef({
    name = "My Lua Event",
    description = "Evento registrado desde Lua",
    color = 0xFF88FF88,
    contexts = { "chart" },
    aliases = { "mle" },
    params = {
        { name = "Value", type = "Float(0,1)", defaultValue = "0.5" }
    }
})
```
