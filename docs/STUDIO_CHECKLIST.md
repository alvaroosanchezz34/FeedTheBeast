# Comprobaciones pendientes en Roblox Studio

Nada de esto se ha podido ejecutar fuera de Roblox. Orden recomendado.

## 1. Arranque (Play Solo)
- [ ] La consola muestra `[FeedTheBeast] server ready` sin errores rojos ni avisos `[Client] ... failed`.
- [ ] Apareces en tu parcela mirando a Gobblo, con tres comidas delante y una línea-guía.
- [ ] HUD: monedas arriba a la izquierda, menú a la izquierda, barra de comida abajo. Chip rojo "TEST MODE" si no hay DataStores.

## 2. Primer minuto (cronometrar)
- [ ] Primera comida recogida < 30 s; primera alimentación < 60 s (prompt E / toque).
- [ ] Al comer: animación de mordisco, partículas en la boca, crece con suavidad, +monedas.
- [ ] La zona dorada cobra al pisarla; el tutorial avanza y desaparece tras gastar o recoger 6 comidas.

## 3. Criaturas y mutaciones (Ajustes → DEV)
- [ ] "Spawn beast" para las 6 especies: siluetas, caras y animación idle correctas; ninguna pieza suelta o girada.
- [ ] "All → Golden / Electric / Cosmic": materiales, aura, orbitadores, anillos y arcos. ¿Se distinguen de lejos? ¿COSMIC es la más vistosa?
- [ ] Nullabyte (Secret): aura doble, glitch moderado, contorno.
- [ ] "Grow all +200" varias veces: el aura se adapta al tamaño; las criaturas no se salen del corral ni bloquean el paso.
- [ ] Calidad Low / Medium / High: cambia de verdad y no deja restos. "Clear effects" limpia.
- [ ] Ningún efecto parpadea ni deslumbra.

## 4. Interfaz
- [ ] Emuladores de dispositivo (iPhone, iPad, 1080p): nada se solapa ni se sale; botones cómodos; el joystick y el salto quedan libres.
- [ ] Los emoji de iconos se ven en todas las plataformas (si no, sustituir por imágenes).
- [ ] Retratos 3D en BEASTS, COLLECTION y la tarjeta de eclosión bien encuadrados.
- [ ] Renacer: dos pantallas, el botón final tarda ~1,5 s en activarse.

## 5. Multijugador (Test → 2-4 jugadores)
- [ ] Cada jugador recibe parcela distinta; carteles con nombre.
- [ ] DEV → Crates: recoger ralentiza, la caja se ve sobre la cabeza, el otro jugador puede robarla manteniendo E, alerta a la víctima, recuperación, entrega en la zona azul.
- [ ] La caja no atraviesa ni empuja al portador (está soldada sin colisión).
- [ ] Desconectar con la caja: cae al suelo.
- [ ] Eventos (DEV): lluvia de comida cayendo, festín dorado, bestia gigante con barra de progreso y reparto.

## 6. Datos (lugar publicado, con "Enable Studio Access to API Services")
- [ ] El progreso persiste al salir y volver; ganancias offline tras > 1 min.
- [ ] Entrar con la misma cuenta en dos servidores: el segundo espera/expulsa con mensaje.

## 7. Rendimiento
- [ ] 8 jugadores con varias criaturas mutadas: FPS y memoria en un móvil real de gama media (MicroProfiler, F9).

## 8. Antes de publicar
- [ ] `GameConfig.Admins.UserIds` con tus IDs; decidir `AllowInStudio` / `AllowPlaceCreator`.
- [ ] Máximo de jugadores del lugar = 8.
- [ ] Assets e IDs de `docs/ASSETS_PENDIENTES.md` y `docs/MONETIZACION.md`.
