import 'package:drift/drift.dart';
import '../../core/civil_date.dart';
import '../../core/currency.dart';
import '../../core/fx.dart';
import '../db/database.dart';

/// No hay ningún tipo de cambio conocido para esta divisa.
class NoFxRateAvailable implements Exception {
  final Currency currency;
  NoFxRateAvailable(this.currency);

  @override
  String toString() =>
      'Sin tipo de cambio para ${currency.code}. Conéctate a internet una vez '
      'para descargarlos.';
}

/// Un tipo resuelto para una fecha concreta. [isEstimated] indica que se ha
/// usado el tipo de un día anterior.
class ResolvedRate {
  final FxRate rate;
  final bool isEstimated;
  const ResolvedRate(this.rate, this.isEstimated);
}

class FxRepository {
  final AppDatabase db;
  FxRepository(this.db);

  Future<void> save(String date, FxRate rate, {required String source}) =>
      db.into(db.fxRates).insertOnConflictUpdate(FxRatesCompanion.insert(
            date: date,
            currency: rate.currency.code,
            rateToEurScaled: rate.scaled,
            source: source,
          ));

  Future<void> saveAll(String date, List<FxRate> rates,
          {required String source}) =>
      db.batch((b) {
        for (final rate in rates) {
          b.insert(
            db.fxRates,
            FxRatesCompanion.insert(
              date: date,
              currency: rate.currency.code,
              rateToEurScaled: rate.scaled,
              source: source,
            ),
            onConflict: DoUpdate((_) => FxRatesCompanion(
                  rateToEurScaled: Value(rate.scaled),
                  source: Value(source),
                )),
          );
        }
      });

  /// El tipo del día, o el último anterior marcado como estimado.
  Future<ResolvedRate> rateFor(Currency currency, String date) async {
    if (currency == Currency.eur) {
      return ResolvedRate(FxRate.identity(Currency.eur), false);
    }

    final exact = await (db.select(db.fxRates)
          ..where((r) => r.currency.equals(currency.code) & r.date.equals(date)))
        .getSingleOrNull();
    if (exact != null) {
      return ResolvedRate(FxRate(currency, exact.rateToEurScaled), false);
    }

    final previous = await (db.select(db.fxRates)
          ..where((r) =>
              r.currency.equals(currency.code) & r.date.isSmallerThanValue(date))
          ..orderBy([(r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    if (previous != null) {
      return ResolvedRate(
        FxRate(currency, previous.rateToEurScaled),
        !_isNonBusinessDay(date),
      );
    }

    throw NoFxRateAvailable(currency);
  }

  /// Sábado o domingo: el BCE no publica y el tipo del último día hábil es,
  /// por diseño, **el correcto**, no una estimación provisional. Marcarlo
  /// como estimado pondría el icono de reloj en dos de cada siete días y la
  /// señal dejaría de significar nada.
  ///
  /// Los festivos de TARGET2 (Navidad, Año Nuevo, Viernes Santo) sí se
  /// marcarán, porque no se pueden saber sin un calendario. Son unos nueve
  /// días al año; es una imprecisión asumida, no un descuido.
  static bool _isNonBusinessDay(String isoDate) {
    // `parseCivilDate` y no `DateTime.parse`: una sola puerta de entrada para
    // las fechas del proyecto, con su limitación documentada en un solo sitio.
    final weekday = parseCivilDate(isoDate).weekday;
    return weekday == DateTime.saturday || weekday == DateTime.sunday;
  }

  Future<String?> latestStoredDate() async {
    final row = await (db.select(db.fxRates)
          ..orderBy([(r) => OrderingTerm(expression: r.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.date;
  }
}
