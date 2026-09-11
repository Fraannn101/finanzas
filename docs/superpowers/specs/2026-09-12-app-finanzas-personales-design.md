# App de finanzas personales — Diseño

**Fecha:** 2026-09-12
**Estado:** Aprobado
**Alcance de este documento:** diseño completo de las tres fases; implementación de la Fase 1.

---

## 1. Objetivo

Una aplicación móvil para seguir las finanzas personales de un solo usuario, con cuentas en varias divisas (EUR, GBP, USD) y, más adelante, inversiones en varios brókeres.

El criterio de éxito es la fricción: **apuntar un gasto debe costar tres toques**. Una app de finanzas que se abandona a las dos semanas no sirve de nada, por completa que sea.

Android primero. iOS después, con la misma base de código.

## 2. Decisiones de producto

| Decisión | Elección | Motivo |
|---|---|---|
| Entrada de datos | Manual + importación CSV | La entrada manual bien diseñada es lo que sostiene el uso diario. El CSV da el puente con el banco sin la complejidad regulatoria de PSD2. |
| Ubicación de los datos | Solo en el dispositivo | Un único usuario, un único dispositivo a la vez. Sin servidor, sin coste, sin custodiar datos financieros. |
| Divisa base | EUR | Todos los totales e informes se expresan en euros. |
| Multiusuario | No | Fuera de alcance. |
| Sincronización | No | El paso a iPhone se cubre con exportar/importar. |

### Fases

El diseño cubre las tres. La implementación va por fases, y cada una deja una app usable.

**Fase 1 — Núcleo de dinero.** Cuentas multidivisa, gastos, ingresos, transferencias (incluidas las que cambian de divisa), tarjetas de crédito, categorías, gastos recurrentes, informe de gasto por categoría, patrimonio total, importación CSV, copia de seguridad.

**Fase 2 — Inversiones.** Brókeres, posiciones, compraventas, cotizaciones de mercado, valor de cartera integrado en el patrimonio.

**Fase 3 — Fiscalidad.** Depende de la residencia fiscal y de reglas concretas (FIFO, conversión a la divisa de declaración, retenciones GBP/USD). Se diseñará cuando toque.

### Fuera de alcance de la Fase 1

Presupuestos por categoría y búsqueda/filtrado avanzado quedan para una **Fase 1.5**. Los presupuestos solo son útiles con meses de datos acumulados; la búsqueda es rápida de añadir en cualquier momento.

## 3. Modelo de datos

### Principios

1. **El dinero se guarda en unidades menores, como entero.** 24,50 £ → `2450`. Nunca coma flotante: `0.1 + 0.2 != 0.3` en cualquier lenguaje, y en finanzas eso son saldos que dejan de cuadrar.
2. **Cada movimiento congela su tipo de cambio.** Se guardan el importe nativo, el tipo del día y el equivalente en euros ya calculado. Los informes históricos no cambian nunca.
3. **Una cuenta tiene una divisa y solo una**, fijada al crearla. Hace imposible registrar un movimiento en la moneda equivocada.
4. **Los importes se guardan siempre positivos.** El signo lo determina el tipo de movimiento.
5. **Una transferencia es una sola fila**, con cuenta origen, cuenta destino y ambos importes. No puede existir media transferencia.
6. **El saldo no se almacena: se calcula** sobre el saldo inicial. Un saldo almacenado se desincroniza al editar el pasado.

### Tablas (Fase 1)

**`institutions`** — agrupación visual por banco.
`id` PK · `name` · `icon` · `color` · `sort_order`

**`accounts`**
`id` PK · `institution_id` FK? · `name` · `currency` (ISO 4217, inmutable con movimientos) · `type` (`cash` | `checking` | `savings` | `credit_card`; la Fase 2 añade `investment`) · `initial_balance_minor` INT · `credit_limit_minor` INT? · `is_archived` · `sort_order` · `created_at`

Revolut se modela como tres cuentas (`Libras`/GBP, `Euros`/EUR, `Dólares`/USD) bajo una misma institución. BBVA y Barclays tienen una cuenta cada uno. Cambiar euros por libras dentro de Revolut es una transferencia normal entre dos cuentas.

En una transferencia, `amount_minor` va en la divisa de `account_id` (lo que sale) y `counter_amount_minor` en la de `counter_account_id` (lo que entra). Si ambas cuentas comparten divisa, los dos importes coinciden.

Reglas derivadas de esta forma de guardar:

- **Saldo de una cuenta** = `initial_balance_minor` − (gastos) + (ingresos) − (transferencias donde es `account_id`) + (transferencias donde es `counter_account_id`).
- **Informes de gasto e ingreso ignoran las transferencias.** Mover dinero entre cuentas propias no es gastar ni ingresar; contarlo inflaría ambas cifras.

**`categories`**
`id` PK · `name` · `icon` · `color` · `kind` (`expense` | `income`) · `parent_id` FK? (subcategorías, un nivel) · `is_archived` · `sort_order`

**`transactions`**
`id` PK · `type` (`expense` | `income` | `transfer`) · `account_id` FK · `amount_minor` INT ≥ 0 · `currency` (copiada de la cuenta) · `fx_rate_to_eur` (8 decimales, congelado) · `amount_eur_minor` INT · `fx_is_estimated` BOOL · `date` DATE (sin hora) · `category_id` FK? (nulo en transferencias) · `counter_account_id` FK? · `counter_amount_minor` INT? · `merchant` TEXT? · `note` TEXT? · `recurring_rule_id` FK? · `import_batch_id` FK? · `dedupe_hash` TEXT? · `created_at` · `updated_at`

**`fx_rates`**
`date` + `currency` PK · `rate_to_eur` · `source` (`ecb` | `manual`)

Los tipos también se guardan como entero, escalados ×10⁸ (1 GBP = 1,17234500 EUR → `117234500`). Misma razón que los importes: nada de coma flotante en los cálculos de dinero.

**`recurring_rules`**
`id` PK · campos plantilla del movimiento (`type`, `account_id`, `category_id`, `amount_minor`, `merchant`, `note`) · `frequency` (`weekly` | `monthly` | `yearly`) · `interval` INT · `day_of_month` INT? · `weekday` INT? · `mode` (`auto` | `confirm`) · `start_date` · `end_date` DATE? · `next_due_date` · `last_generated_date` · `is_paused`

**`recurring_skips`**
`rule_id` + `date` PK — meses saltados sin borrar la regla.

**`import_batches`**
`id` PK · `account_id` FK · `filename` · `imported_at` · `row_count` · `column_mapping` JSON

**`settings`** — clave/valor: divisa base, tema, fecha de última descarga de tipos, recordatorio de copia de seguridad.

### Tablas de la Fase 2 (diseñadas, no implementadas)

**`holdings`** — `account_id` FK (tipo `investment`) · `ticker` · `isin` · `quantity` DECIMAL · `currency`
**`trades`** — `holding_id` FK · `side` (compra/venta) · `quantity` · `price_minor` · `fee_minor` · `date`
**`price_quotes`** — `ticker` + `date` PK · `close_minor` · `currency`

Cuelgan de una cuenta de tipo `investment`. Ninguna tabla de la Fase 1 se modifica al llegar la Fase 2.

## 4. Arquitectura

### Capas

```
Pantallas (Flutter)
      ↓  lee estado, envía intenciones
Controladores (Riverpod)
      ↓  pide y guarda datos
Repositorios  ← las reglas del dinero viven aquí
      ↓  consultas con tipos comprobados
Drift / SQLite  ← archivo local en el dispositivo
```

Las pantallas no conocen SQLite. Los repositorios no conocen Riverpod. La lógica del dinero se prueba entera sin emulador.

### Tecnología

| Pieza | Elección | Motivo |
|---|---|---|
| Framework | Flutter 3.41 | Una base de código para Android e iOS. Ya instalado. |
| Base de datos | Drift sobre SQLite | Consultas verificadas en compilación y streams reactivos: al guardar, la lista y el saldo se actualizan solos. |
| Estado | Riverpod | Encaja con los streams de Drift, menos ceremonia que BLoC. |
| Dinero | `Money(minorUnits, currency)` | Objeto de valor propio. Sumar GBP con EUR no compila. |

### Servicios transversales

- **FxService** — descarga los tipos del BCE una vez al día (API pública, sin registro ni clave). Si falla, usa el último conocido.
- **RecurringService** — al abrir la app, genera los recurrentes `auto` pendientes y encola los `confirm`.
- **CsvImportService** — mapeo de columnas, detección de duplicados, vista previa antes de escribir.
- **BackupService** — exportación cifrada a un archivo. Seguro ante pérdida del móvil y vía de migración a iPhone.

### Estructura del código

```
lib/
├── core/           money.dart · fx.dart · formatting.dart · result.dart
├── data/
│   ├── db/         tablas · DAOs · migraciones · vistas de saldo
│   └── repositories/
├── features/       transactions/ · accounts/ · categories/ ·
│                   recurring/ · reports/ · import/ · settings/
└── app/            navegación · tema · arranque
```

Organización por funcionalidad, no por tipo de archivo: todo lo de recurrentes vive junto.

## 5. Interfaz

### Pantalla principal y hoja de añadir

La pantalla de inicio es la lista de movimientos del mes con el patrimonio total en euros arriba. El botón `+` levanta una **hoja desde abajo** sin salir de la lista: sigues viendo el saldo mientras apuntas.

La hoja contiene, de arriba abajo:

1. Selector **Gasto / Ingreso / Transferencia**.
2. **Importe** en grande, con el símbolo de la divisa de la cuenta seleccionada y, debajo, la equivalencia en euros en vivo (*"24,50 £ · ≈ 28,70 €"*).
3. Fila de **chips de cuenta**, cada uno con su divisa (`Revolut £`, `Revolut €`, `BBVA €`, `Barclays £`), ordenados por frecuencia de uso. `Ver todas ›` abre la lista completa agrupada por institución, con el saldo de cada cuenta.
4. Fila de **chips de categoría**, también por frecuencia. `Todas ›` abre el selector completo.
5. **Teclado numérico** con botón Guardar, más accesos a fecha y nota.

**La divisa no se elige nunca por separado: la determina la cuenta.** Tocar `Revolut £` cambia el importe a libras. Registrar un movimiento en la moneda equivocada es imposible por construcción.

**Valores por defecto:** cuenta más usada, categoría más frecuente, fecha de hoy. El caso normal son tres toques: importe → categoría → Guardar.

**Transferencias:** la hoja pasa a mostrar dos cuentas (origen y destino) y pide **ambos importes** — lo que salió y lo que entró. De ahí sale el tipo real aplicado por el banco, comisión incluida.

### Otras pantallas

- **Edición de un movimiento** — formulario completo, con todos los campos visibles (tipo, importe, cuenta, categoría, fecha, comercio, nota). La velocidad importa al crear; al corregir importa la visibilidad.
- **Cuentas** — agrupadas por institución, con subtotal por institución en euros.
- **Informes** — gasto por categoría (mes a mes, con gráfico) y evolución del patrimonio total.
- **Recurrentes** — reglas activas y pantalla de "Próximos" con lo que viene este mes, con opción de saltar un mes concreto.
- **Importar CSV** — selección de archivo, mapeo de columnas, vista previa con duplicados marcados.
- **Ajustes** — copia de seguridad, divisa base, tema, gestión de categorías e instituciones.

## 6. Casos límite y errores

| Situación | Comportamiento |
|---|---|
| El BCE no publica fines de semana ni festivos | Se usa el tipo del último día hábil. Es lo estándar y es correcto. |
| Sin internet al guardar | Se usa el último tipo conocido y el movimiento se marca `fx_is_estimated`. Al llegar el tipo real, se recalculan solo los marcados. Nunca se bloquea el guardado. |
| Recurrente "día 31" en febrero | Se usa el último día del mes. |
| La app no se abre en tres meses | Se generan **todos** los recurrentes pendientes, no solo el último, sin duplicar. Cada regla recuerda hasta qué fecha generó. |
| Liquidación de tarjeta de crédito | Es una **transferencia** de la cuenta corriente a la tarjeta, no un gasto. El gasto se registró al comprar; contarlo otra vez duplicaría el gasto en los informes. |
| Borrar cuenta o categoría con movimientos | No se borra: se archiva. Desaparece de la interfaz y sus movimientos siguen contando. |
| Cambiar la divisa de una cuenta | Permitido solo si la cuenta no tiene movimientos. Con movimientos: archivar y crear otra. |
| Importar dos veces el mismo extracto | Huella por fila (fecha + importe + concepto + cuenta). La vista previa marca las existentes y no las reinserta. |
| Mapeo de columnas erróneo | El lote de importación se deshace entero de un toque. |
| Husos horarios | Las fechas se guardan sin hora. Un gasto de las 23:50 no salta de día. |
| Migración de esquema | Copia de seguridad automática antes de cada migración. |
| Borrado accidental de un movimiento | Deshacer desde el aviso emergente. |

### Redondeo

La conversión a euros redondea al céntimo más cercano, con el medio hacia arriba. Los informes suman los importes en euros ya redondeados de cada movimiento, de modo que el total mostrado siempre coincide con la suma de las líneas visibles.

## 7. Pruebas

Desarrollo guiado por pruebas: la prueba primero. En una app donde un error de redondeo es dinero que no cuadra, es lo que separa confiar de no confiar en lo que ves.

- **Unitarias** (el grueso): aritmética de `Money`, conversión y redondeo de divisas, cálculo de fechas de recurrentes (febrero, meses saltados, generación atrasada), parser de CSV, huella de duplicados, cálculo de saldos.
- **De base de datos**, con SQLite en memoria: repositorios y **migraciones** — migrar una base con datos representativos entre versiones y verificar que no se pierde nada.
- **De widget**: la hoja de añadir guarda exactamente lo seleccionado; elegir `Revolut £` cambia la divisa del importe.
- **De integración**: crear cuentas en tres divisas → registrar gastos en cada una → el patrimonio en euros cuadra al céntimo.

**Excluido:** comparaciones pixel a pixel. Frágiles y de coste desproporcionado para un proyecto personal.

## 8. Criterio de terminación de la Fase 1

La Fase 1 está lista cuando el autor puede usar la app como registro principal de sus finanzas durante un mes completo sin recurrir a otra herramienta: cuentas en EUR/GBP/USD dadas de alta, gastos e ingresos diarios en tres toques, transferencias entre divisas, recurrentes generándose solos, patrimonio total correcto en euros, y una copia de seguridad restaurable.
