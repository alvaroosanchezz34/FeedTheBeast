# Monetización: qué hay y qué falta configurar

`src/shared/Config/MonetizationConfig.lua`. **Todos los `id` son `0` (placeholder): nada se puede comprar ni se concede** hasta que los cambies.

## Pasos en el Creator Dashboard
1. Crea los Game Passes y Developer Products de la tabla y fija su precio.
2. Copia cada ID en `MonetizationConfig` (`id = ...`).
3. Prueba en un lugar publicado: comprar, salir a mitad, volver a entrar.

| Clave | Tipo | Efecto | Precio a probar |
|---|---|---|---|
| VIP | Game Pass | +20 % monedas | ~199 R$ |
| AUTO_FEED | Game Pass | Alimenta sola desde la mochila cada 3 s | ~99 R$ |
| EXTRA_SLOT | Game Pass | +1 corral | ~99 R$ |
| GROWTH_BOOST | Developer Product | x2 crecimiento 15 min (acumulable hasta 24 h) | ~49 R$ |
| PLOT_AURA | Developer Product | Brillo cosmético en la parcela | ~149 R$ |

Los precios son hipótesis, no recomendaciones basadas en datos.

## Cómo funciona
- `ProcessReceipt` guarda el `PurchaseId` junto con la recompensa y solo responde `PurchaseGranted` cuando el guardado se confirma; cualquier fallo devuelve `NotProcessedYet` (Roblox reintenta) y un reintento no duplica.
- Los pases se verifican con `UserOwnsGamePassAsync`; si la comprobación falla no se concede nada.
- Ningún producto da monedas directas ni permite robar criaturas.

## No implementado a propósito
- Huevos o paquetes aleatorios de pago: exigen publicar probabilidades y están restringidos en algunos países; decide primero si los quieres.
- Catálogo de cosméticos premium (auras y apariencias de criatura): la arquitectura de auras lo permite, falta el contenido.
- VIP no tiene todavía etiqueta de chat ni corona, aunque la descripción del pase lo menciona: añádelo o cambia el texto antes de venderlo.
