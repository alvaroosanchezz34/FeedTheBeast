# FEED THE BEAST

*Feed it. Grow it. Steal everything.* — juego multijugador de Roblox (Luau + Rojo): cuida criaturas absurdas en tu parcela, aliméntalas para que crezcan y produzcan monedas, colecciona rarezas y mutaciones, y compite por cajas de comida que se pueden robar.

Estado: **MVP implementado y probado fuera de Roblox; pendiente de revisión visual y de juego en Roblox Studio.** Nada de lo que hay aquí se ha ejecutado todavía dentro de Roblox (ver "Qué está verificado").

![Criaturas x mutaciones](docs/preview/creatures.png)

## Cómo abrirlo

```bash
rojo build default.project.json -o FeedTheBeast.rbxl   # y abrir el .rbxl en Studio
# o bien: rojo serve  + plugin de Rojo en un lugar vacío
```

No hay archivo de lugar con geometría: el servidor construye el mapa al arrancar (`WorldBuilder`) y cada cliente construye las criaturas. En Studio sin acceso a DataStores se juega con un perfil en memoria (aviso rojo en el HUD).

Si usas `rojo serve` sobre una plantilla, desactiva **Workspace.StreamingEnabled** a mano (Rojo no puede cambiarla en vivo; `rojo build` sí la deja en `false`).

## Estructura

| Ruta | Contenido |
|---|---|
| `src/shared/Config` | Toda la configuración: comida, criaturas, rarezas, mutaciones, economía, mejoras, huevos, eventos, robo, VFX, audio, monetización |
| `src/shared/Logic` | Lógica pura y testeada: fórmulas, esquema y migraciones del perfil, máquina de estados de robo, tiradas, validación, rate limiter |
| `src/shared/Creatures` | Kit de construcción, 6 especies procedurales y visuales de mutación |
| `src/server/Services` | Servicios autoritativos (datos, economía, criaturas, alimentación, tienda, robo, eventos, monetización, admin...) |
| `src/client/Controllers` | Estado, mundo, criaturas, auras, efectos, audio, entrada, cámara, interfaz |
| `src/client/UI` | Tema, HUD, avisos, ventanas y tutorial |
| `tests` | 8 baterías sobre el build real de Rojo, con Lune |
| `tools/preview` | Previsualización offline aproximada de criaturas y mapa |
| `docs` | Checklist de Studio, assets pendientes, monetización |

## Pruebas

Requiere `rojo`, `lune` (0.9+) en el PATH.

```bash
lune run tests/run            # todo
lune run tests/run Theft      # una batería
lune run tools/preview/run && python3 tools/preview/render.py   # imágenes en build/preview
```

Las pruebas arrancan el servidor y el cliente reales en un DataModel simulado (`tests/lib/Harness.luau`). Lune valida nombres y tipos de propiedades de las instancias, así que también detectan propiedades mal escritas en la interfaz.

## Qué está verificado y qué no

**Verificado con tests (131, todos pasan):** economía y compras, alimentación y crecimiento, anti-duplicación, distancia medida en servidor, rate limiting y validación de remotos, mutaciones, huevos, robo/recuperación/entrega y desconexiones, anti-teleport, persistencia (migraciones, bloqueo de sesión, reintentos, fallo de carga sin sobrescribir), ganancias offline, recibos idempotentes, eventos, renacimiento en dos pasos, permisos de admin, geometría del mapa, construcción de la interfaz y flujo completo cliente↔servidor del primer minuto, límites y limpieza de VFX.

**No verificado (necesita Roblox Studio):** aspecto real de criaturas, auras, partículas e interfaz; físicas, cámara y controles táctiles; rendimiento en móvil; DataStores y MarketplaceService reales; sonidos. Ver `docs/STUDIO_CHECKLIST.md`.

## Problemas conocidos y pendientes

- Audio: no hay IDs propios. Cinco sonidos usan rutas de reserva del motor **sin comprobar** (`AudioConfig`); el resto está en silencio hasta asignar assets.
- Monetización: todos los IDs son `0` (nada es comprable). No hay cosméticos premium más allá del aura de parcela, ni huevos de pago.
- El mapa es funcional pero sobrio (sin decoración, árboles ni música).
- El Bananosaur es la especie con la silueta menos clara en la previsualización; conviene revisarla en Studio.
- No se pudo acceder a Creator Store desde este entorno: no se usa ningún asset externo.
- El equilibrio económico es una primera hipótesis sin datos de jugadores reales.
- Formato: `stylua --check` marca los archivos de configuración de una línea por entrada (intencionado). `selene` no se ha podido ejecutar (necesita descargar la API de Roblox).
