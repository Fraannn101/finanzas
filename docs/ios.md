# iOS — estado y pasos pendientes

**Fecha de la revisión:** 2026-10-01
**Dispositivo objetivo:** iPhone 11, iOS 26.3

## Lo que ya está hecho

El proyecto se creó desde el principio con `--platforms android,ios`, así que `ios/` existe y está configurado:

| | |
|---|---|
| Bundle ID | `com.elrockmola.finanzas` |
| Nombre visible | Finanzas |
| `IPHONEOS_DEPLOYMENT_TARGET` | 13.0 |

Revisión de compatibilidad, hecha sobre el código real:

- **Cero código específico de plataforma** en `lib/`. Ni `Platform.`, ni `dart:io`, ni canales nativos, ni vistas de Android. Toda la lógica es Dart puro sobre Flutter.
- **Todas las dependencias declaran iOS.** `path_provider_foundation` usa una carpeta `darwin/` compartida con macOS; `sqlite3` declara `ios:` y `macos:` en su pubspec.
- **Ninguna URL `http://`.** La única llamada de red es al BCE por HTTPS, que App Transport Security permite sin configuración extra.
- **SQLite funcionará.** `sqlite3_flutter_libs 0.6.0+eol` asusta por el nombre pero es un paquete deliberadamente vacío: desde `package:sqlite3` 3.x la librería nativa la compila el propio paquete mediante `hook/build.dart` y `native_toolchain_c`. No falta nada.

No hay, hasta donde se puede comprobar sin un Mac, ningún cambio de código necesario para que esto corra en iPhone.

## El bloqueo

**No se puede compilar ni firmar una app iOS desde Windows.** Apple exige macOS y Xcode. No es una limitación de este proyecto ni de Flutter: la cadena de herramientas de firma de Apple solo existe en macOS.

Hace falta, sin alternativa:

1. **Acceso a macOS con Xcode.** Un Mac propio, uno prestado, o un runner macOS en la nube (GitHub Actions, Codemagic, MacStadium).
2. **Una cuenta de Apple.**
   - **Gratuita:** permite instalar en tus propios dispositivos, pero la app **caduca a los 7 días** y hay que reinstalarla. Sirve para probar, no para usar a diario.
   - **Apple Developer Program, 99 $/año:** perfiles de un año y acceso a TestFlight. Es lo que hace falta para usarla de verdad en el día a día.

## Pasos en el Mac, en orden

```bash
git clone <este repo>
cd Improvements
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

En Xcode, en *Runner → Signing & Capabilities*: elegir el equipo de desarrollo. Con cuenta gratuita, Xcode generará un perfil personal automáticamente.

Después:

```bash
flutter devices          # con el iPhone conectado y desbloqueado
flutter run --release -d <id-del-iphone>
```

La primera vez, el iPhone pedirá confiar en el desarrollador: *Ajustes → General → VPN y gestión de dispositivos*.

## Riesgos conocidos, por orden de probabilidad

1. **Native assets de `sqlite3`.** Es el riesgo real. El paquete compila SQLite en tiempo de build mediante el sistema de *native assets* de Flutter, que es relativamente nuevo. Si falla, fallará aquí y no en otro sitio. **Probarlo lo primero**: una app que arranca y crea una cuenta ya demuestra que la base de datos funciona.
2. **La interfaz es Material, no Cupertino.** Funciona perfectamente en iOS, pero se ve como una app de Android: los diálogos, los controles segmentados y la hoja inferior siguen las convenciones de Google. Es una decisión de diseño pendiente, no un fallo. Adaptarla a Cupertino sería trabajo de interfaz, no de lógica.
3. **Versión de Flutter.** 3.41.4 es de marzo de 2026 e iOS 26.3 es posterior. Compilar contra un SDK anterior y correr en un iOS más nuevo es lo normal y funciona, pero si Xcode se queja, `flutter upgrade` es el primer intento.

## Lo que no cambia

El modelo de datos, los repositorios, la aritmética del dinero y las 94 pruebas son Dart puro: corren igual en macOS, y `flutter test` se puede ejecutar en el Mac para confirmarlo antes de compilar nada.

Los datos **no se sincronizan** entre Android e iOS. Cada instalación tiene su base de datos local. El puente entre ambos es la copia de seguridad, que es trabajo del Plan 3 y todavía no existe.
