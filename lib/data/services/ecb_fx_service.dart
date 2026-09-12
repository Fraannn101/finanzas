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
final _rateRe = RegExp(r'currency="([A-Z]{3})"\s+rate="([\d.]+)"');

/// Convierte el XML diario del BCE en tipos «euros por unidad».
EcbDaily parseEcbDaily(String xml) {
  final dateMatch = _dateRe.firstMatch(xml);
  final matches = _rateRe.allMatches(xml).toList();
  if (dateMatch == null || matches.isEmpty) {
    throw const FormatException('El XML del BCE no tiene el formato esperado');
  }

  final supported = Currency.all.map((c) => c.code).toSet();
  final rates = <FxRate>[];
  for (final m in matches) {
    final code = m.group(1)!;
    if (!supported.contains(code)) continue;
    rates.add(FxRate.fromEcbQuote(Currency.byCode(code), double.parse(m.group(2)!)));
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
  /// (sin conexión, servicio caído): la app sigue funcionando con lo que tenga.
  Future<bool> refresh() async {
    try {
      final response = await client.get(_endpoint).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final daily = parseEcbDaily(response.body);
      await repo.saveAll(daily.date, daily.rates, source: 'ecb');
      return true;
    } catch (_) {
      return false;
    }
  }
}
