# Copia de seguridad — Diseño

**Fecha:** 2026-10-02
**Estado:** Aprobado
**Relación con la Fase 1:** la copia de seguridad ya figuraba en la Fase 1 de la especificación original. El plan de implementación la empujó al Plan 3; esto la devuelve a su sitio.

---

## 1. Por qué ahora

La app va a correr como webapp en un iPhone, y **Safari expulsa el almacenamiento local de los sitios que no se visitan en unos días**. Las aplicaciones añadidas a la pantalla de inicio deberían persistir, pero el historial de Apple en esto es irregular, y quitar el icono borra los datos.

Sin copia de seguridad, eso convierte un capricho del navegador en la pérdida total del historial financiero. La copia deja de ser un seguro contra perder el móvil y pasa a ser **la condición que hace habitable la ruta web**.

Cumple además el segundo propósito que ya tenía: ser el puente entre el Android, la web y el futuro iPhone nativo, porque los datos no se sincronizan entre dispositivos.

## 2. Decisiones

| Decisión | Elección | Motivo |
|---|---|---|
| Cifrado | Sí, con contraseña | Elección del autor, que guarda sus contraseñas en un gestor. |
| Formato | JSON cifrado, no copia del fichero SQLite | En el navegador no hay fichero: Drift guarda en IndexedDB vía WebAssembly. Una copia en bruto del Android no se podría cargar en la web, que es justo el puente que se busca. |
| Al importar | Reemplazar todo | Es lo que significa «restaurar». Fusionar exige decidir qué versión de cada fila gana, y eso es un sistema de sincronización —explícitamente fuera de alcance—. Hecho a medias daría duplicados silenciosos, es decir, cifras infladas que nadie detecta. |
| Red de seguridad | Copia de rescate automática antes de importar | Hace reversible el error de elegir el archivo equivocado. |
| Recordatorio | Aviso pasivo a los 7 días | Siete días es la ventana en la que Safari empieza a borrar. |
| Exportación automática | No | Un navegador no escribe en disco sin confirmación del usuario. Automatizarlo solo en Android daría dos comportamientos distintos, y el que protege no sería el del iPhone. |

## 3. El archivo

### Estructura

Una cabecera en claro y un cuerpo cifrado. El salt y el nonce **no son secretos** y deben ir legibles: sin ellos el archivo sería indescifrable incluso con la contraseña correcta.

```
cabecera (claro):  magic "FINANZAS" · formato (1B) · salt (16B) · nonce (12B)
cuerpo (cifrado):  AES-256-GCM(JSON)
```

`formato` aparece **dos veces**: en la cabecera y dentro del JSON. No es un descuido. El de la cabecera se lee **antes de descifrar**, que es lo que permite rechazar un archivo de una versión futura sin pedir siquiera la contraseña. El del JSON hace que un archivo descifrado se explique solo al abrirlo. Deben coincidir; si no coinciden, el archivo está manipulado y se rechaza.

### Contenido, una vez descifrado

```json
{
  "formato": 1,
  "esquema": 1,
  "exportado": "2026-10-02T22:14:03Z",
  "app": "finanzas 0.1.0",
  "instituciones": [...],
  "cuentas":       [...],
  "categorias":    [...],
  "movimientos":   [...],
  "tipos_cambio":  [...],
  "ajustes":       [...]
}
```

Las seis tablas completas, sin omisiones. **Los importes viajan como enteros de céntimos**, igual que en la base de datos. Nunca como decimales.

### Los dos números de versión

`formato` describe la estructura del archivo. `esquema` describe la versión de la base de datos que lo generó. Son cosas distintas y hacen falta las dos.

Cuando el Plan 2 añada los gastos recurrentes, el esquema pasará a 2. Una copia hecha hoy seguirá diciendo `"esquema": 1`, y la importación sabrá que las tablas nuevas no existían, dejándolas vacías en lugar de fallar. Sin ese campo, una copia de hoy sería inservible dentro de dos meses.

### Cifrado

AES-256-GCM. La clave se deriva de la contraseña con PBKDF2-HMAC-SHA256, salt aleatorio de 16 bytes por archivo y **100.000 iteraciones exactas**. El número va fijo y escrito aquí a propósito: si cambiara entre versiones, las copias antiguas dejarían de abrirse. Subirlo en el futuro exige incrementar `formato` y mantener la lectura del anterior.

Se usa el paquete `cryptography`, que funciona igual en nativo y en web.

GCM aporta algo más que confidencialidad: **detecta la corrupción**. Si un byte del archivo cambia, el descifrado falla ruidosamente en lugar de devolver datos silenciosamente erróneos.

### Nombre

`finanzas-AAAA-MM-DD.backup`

## 4. Flujos

### Exportar

Desde Ajustes.

1. Diálogo de contraseña, con doble campo para evitar erratas. El aviso va **en la propia pantalla, destacado**: *si pierdes esta contraseña, el archivo no se puede recuperar; no hay forma de restablecerla*.
2. Se serializan las seis tablas, se cifra, se entrega.
3. **Entrega según plataforma.** En Android, el menú de compartir del sistema, para mandarlo a Drive, al correo o a Archivos. En web, una descarga del navegador.
4. Se registra la fecha en `app_settings`, que alimenta el recordatorio.
5. Confirmación con cifras: *«Copia creada: 847 movimientos, 6 cuentas»*.

### Restaurar

1. Selección de archivo y contraseña.
2. Se valida la cabecera, se descifra y se parsea. Cualquier fallo aquí termina el proceso **sin haber tocado la base de datos**.
3. **Copia de rescate.** Antes de modificar nada, se guarda el estado actual.
4. **Confirmación con números concretos:** *«Vas a sustituir 847 movimientos por 1.203, de una copia del 2 de octubre»*. Si esas cifras no son las esperadas, el error se ve aquí.
5. Al confirmar, el vaciado y la inserción ocurren **dentro de una transacción**: entra todo o no entra nada.
6. Mientras exista la copia de rescate, Ajustes ofrece **«Deshacer la última restauración»**.

### La copia de rescate va sin cifrar y no sale de la app

Es deliberado. La alternativa —un archivo cifrado— obligaría a pedir una **segunda contraseña en mitad de una restauración**, y ese es exactamente el diálogo que nadie lee, lo que haría fallar la red de seguridad justo cuando se necesita.

Al quedarse dentro del almacenamiento de la app, no está más expuesta que la base de datos en uso, que tampoco está cifrada. No empeora la seguridad y funciona sin intervención.

**Dónde vive y cuánto dura.** Se guarda como el mismo JSON sin cifrar, en una fila de `app_settings` bajo la clave `rescate`. Eso la hace idéntica en Android y en web sin depender del sistema de ficheros, y la mete en la misma transacción que todo lo demás. Solo se conserva **la más reciente**: una restauración nueva sustituye la anterior. Se borra al pulsar «Deshacer la última restauración» o al exportar una copia nueva, momento en el que ya existe un respaldo mejor.

**La trampa que esto esconde.** La importación reemplaza las seis tablas, y `app_settings` es una de ellas. Escrito ingenuamente, el rescate quedaría sobrescrito por el `app_settings` del archivo importado: la restauración destruiría la red de seguridad creada para protegerte de ella, y «Deshacer» no funcionaría jamás.

Por eso **`rescate` se escribe después de reemplazar las tablas, dentro de la misma transacción**, y nunca se toma del archivo importado. Dos claves más reciben el mismo trato por el mismo motivo: `ultima_copia`, porque la fecha de copia del dispositivo que hizo el archivo no dice nada sobre este, y `rescate_fecha`.

Las tres claves son **locales al dispositivo**, no datos del usuario. Al exportar se omiten: una copia no debe arrastrar el rescate de otro aparato ni su calendario de respaldos.

### Recordatorio

La fecha de la última copia vive en `app_settings` bajo la clave `ultima_copia`. Pasados **7 días**, la pantalla de inicio muestra una línea discreta: *«Última copia hace 23 días»*, que al tocarse lleva a exportar. No es un diálogo, no bloquea nada y desaparece al hacer la copia.

Si nunca se ha hecho ninguna, el texto es otro: *«Sin copia de seguridad»*, porque ahí el riesgo no es parcial.

## 5. Errores

| Situación | Comportamiento |
|---|---|
| Contraseña incorrecta | GCM falla al autenticar. *«Contraseña incorrecta, o el archivo está dañado»*. Las dos causas son indistinguibles y fingir lo contrario sería mentir. |
| Archivo corrupto o truncado | Mismo camino. Se detecta antes de parsear. **Nunca se importan datos a medias.** |
| Archivo que no es de la app | La cabecera se comprueba antes de intentar descifrar. *«Este archivo no es una copia de Finanzas»*. |
| Copia de una versión más nueva | `formato` mayor que el conocido: se rechaza. Importarla perdería campos en silencio. |
| Copia de un esquema anterior | Se acepta. Las tablas inexistentes entonces quedan vacías. |
| Fallo a mitad de la importación | La transacción revierte. La base de datos queda intacta. |
| Sin espacio al exportar | El error se propaga. Una copia que falla en silencio es peor que no tenerla. |
| Copia con otra divisa base | Se avisa y se permite. Los importes en euros están congelados en cada movimiento, así que siguen siendo correctos. |

## 6. Pruebas

El criterio es que **la ida y vuelta sea exacta**. Una copia que restaura «casi bien» no sirve.

- **Ida y vuelta completa.** Poblar con cuentas en EUR, GBP y USD; movimientos de los tres tipos; transferencias entre divisas; categorías archivadas; tipos de cambio. Exportar, vaciar, importar, y comparar **cada fila de cada tabla campo a campo**. Idénticas, no parecidas.
- **Los saldos cuadran tras restaurar.** Se recalculan desde los movimientos, de modo que una fila perdida o duplicada se delata sola. Es la prueba que de verdad detecta fallos.
- **Contraseña incorrecta falla** sin tocar la base de datos.
- **Un byte alterado rompe el descifrado.** Corromper el archivo a propósito y comprobar que se detecta en vez de devolver basura.
- **Una copia con `esquema: 1` se importa** en una app con esquema 2, dejando vacías las tablas nuevas.
- **Una copia con `formato: 99` se rechaza.**
- **La copia de rescate deshace** una importación equivocada. Y, específicamente, **sobrevive a la importación**: el archivo importado trae su propio `app_settings`, y la prueba comprueba que el `rescate` local sigue ahí después, no el del archivo. Sin esta prueba, el «Deshacer» parecería implementado y no funcionaría nunca.
- **Las claves locales no se exportan.** `rescate`, `rescate_fecha` y `ultima_copia` no aparecen en el JSON generado.
- **Los importes sobreviven como enteros.** 2450 céntimos vuelven como 2450, no como 24.5 reconvertido. Es la prueba contra que alguien «mejore» el JSON usando decimales.
- **El salt cambia en cada archivo.** Dos exportaciones de los mismos datos con la misma contraseña producen bytes distintos.

El cifrado en sí no se prueba a mano: `cryptography` es código revisado. Lo que se prueba es **que se usa correctamente**.

## 7. Criterio de terminación

La función está lista cuando el autor puede exportar desde el Android, borrar los datos de la app, restaurar desde el archivo, y comprobar que el patrimonio total y todos los saldos por cuenta coinciden al céntimo con los de antes.
