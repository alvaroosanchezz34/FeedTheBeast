# Assets pendientes

El juego no usa ningún asset externo. No se pudo acceder a Creator Store desde el entorno de desarrollo, así que no se buscó ni descargó nada. Todo lo visual es procedural (Parts, ParticleEmitter, Beam, Highlight, PointLight) con las tres texturas de partículas del motor (`rbxasset://textures/particles/*`).

## Audio (`src/shared/Config/AudioConfig.lua`)
Todos los `id` están vacíos. Asigna `rbxassetid://...` de sonidos propios o con licencia comprobada:

`PickupFood, Eat, Grow, Purchase, Coins, Error, Click, Hatch, MutationGolden, MutationElectric, MutationCosmic, RareFind, SecretReveal, Steal, StolenAlert, Recover, Deliver, EventStart, EventEnd, Rebirth, ElectricZap` y música `Main`, `Event`.

Cinco sonidos tienen una ruta de reserva del motor (`fallback`): `electronicpingshort.mp3`, `snap.mp3`, `button.mp3`, `clickfast.mp3`. Salen de una lista pública de sonidos clásicos de Roblox y **no se han comprobado**: si no cargan, el cliente avisa una vez y los desactiva. Para apagarlas: `UseEngineFallbacks = false`.

## Modelos
Las 6 criaturas son prototipos con Parts. Para sustituir una por un modelo de artista, cambia su módulo en `src/shared/Creatures/Species/` manteniendo los anclajes `Head, Mouth, Top, AuraAnchor, Ground`, las articulaciones con nombre y los roles `Body/Belly/Accent/Detail` (los usan mutaciones y auras).

## Iconos
La comida usa modelos 3D propios (en el mapa y como icono en `ViewportFrame`). Los emoji quedan solo en botones y textos; si alguna plataforma no los muestra bien, sustituir por imágenes subidas.

## Si añades modelos de terceros
Revisa procedencia y licencia, abre y lee todos sus scripts, elimina `require(id)`, `loadstring`, remotos y `HttpService` que no reconozcas, y registra aquí su origen y atribución.

## Mallas (opcional, mejora de calidad)
Criaturas, comida y mapa están hechos con piezas básicas y `SpecialMesh` de esfera: no dependen de ningún asset. Si se quiere más calidad, cada especie (`src/shared/Creatures/Species/*.lua`) y cada comida (`src/shared/Food/FoodModels.lua`) se puede sustituir por un `MeshPart` propio manteniendo los mismos nombres de anclaje (`Mouth`, `Top`, `Center`) y articulaciones. No se ha buscado ni descargado nada de Creator Store desde este entorno (no es accesible), así que no hay ningún ID de terceros en el proyecto.
