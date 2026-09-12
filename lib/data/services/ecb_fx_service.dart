import 'package:http/http.dart' as http;
import '../../core/currency.dart';
import '../../core/fx.dart';
import '../repositories/fx_repository.dart';

class EcbDaily {
  final String date;
  final List<FxRate> rates;
  const EcbDaily(this.date, this.rates);
}

final _dateRe = RegExp(r'time="(\d{4}-\d{2}-\d{2})"');

/// Se localiza cada etiqueta `<Cube .../>` y luego se leen sus atributos por
/// separado, sin depender del orden. Una expresión que exigiera
/// `currency="..." rate="..."` pegados dejaría de encontrar la divisa —en
/// silencio, sin error— el día que el BCE cambie el orden o meta un atributo
/// nuevo entre medias.
final _cubeRe = RegExp(r'<Cube\s+([^>]*?)/>');
final _attrRe = RegExp(r'(\w+)="([^"]*)"');

/// Convierte el XML diario del BCE en tipos «euros por unidad».
EcbDaily parseEcbDaily(String xml) {
  final dateMatch = _dateRe.firstMatch(xml);
  if (dateMatch == null) {
    throw const FormatException('El XML del BCE no tiene el formato esperado');
  }

  final supported = Currency.all.map((c) => c.code).toSet();
  final rates = <FxRate>[];
  for (final cube in _cubeRe.allMatches(xml)) {
    final attrs = <String, String>{
      for (final a in _attrRe.allMatches(cube.group(1)!))
        a.group(1)!: a.group(2)!,
    };
    final code = attrs['currency'];
    final quote = attrs['rate'];
    if (code == null || quote == null || !supported.contains(code)) continue;
    rates.add(FxRate.fromEcbQuote(Currency.byCode(code), double.parse(quote)));
  }

  if (rates.isEmpty) {
    throw const FormatException('El XML del BCE no tiene el formato esperado');
  }
  return EcbDaily(dateMatch.group(1)!, rates);
}

class EcbFxService {
  static final Uri _endpoint =
      Uri.parse('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml');

  final FxRepository repo;
  final http.Client client;

  EcbFxService(this.repo, {http.Client? client})
      : client = client ?? http.Client();

  /// Descarga los tipos del día y los guarda. Devuelve `false` si no se pudo
  /// (sin conexión, servicio caído, XML ilegible): la app sigue funcionando
  /// con lo que tenga.
  ///
  /// Un fallo al **escribir** sí se propaga. Que no haya red es normal y se
  /// arregla solo; que la base de datos local no acepte una escritura no se
  /// arregla reintentando, y devolver el mismo `false` lo disfrazaría de
  /// problema de cobertura.
  Future<bool> refresh() async {
    final EcbDaily daily;
    try {
      final response =
          await client.get(_endpoint).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      daily = parseEcbDaily(response.body);
    } catch (_) {
      return false;
    }
    await repo.saveAll(daily.date, daily.rates, source: 'ecb');
    return true;
  }
}
