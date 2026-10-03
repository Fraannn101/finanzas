import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/civil_date.dart';
import '../core/money.dart';
import '../data/backup/backup_service.dart';
import '../data/db/database.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/fx_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/services/ecb_fx_service.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final accountRepoProvider =
    Provider((ref) => AccountRepository(ref.watch(dbProvider)));

final fxRepoProvider = Provider((ref) => FxRepository(ref.watch(dbProvider)));

final transactionRepoProvider = Provider((ref) => TransactionRepository(
      ref.watch(dbProvider),
      ref.watch(accountRepoProvider),
      ref.watch(fxRepoProvider),
    ));

final ecbServiceProvider =
    Provider((ref) => EcbFxService(ref.watch(fxRepoProvider)));

/// Se lanza una vez al arrancar. Si falla, la app sigue con lo que tenga.
///
/// Cuando la descarga va bien, se rehacen los movimientos que se guardaron
/// con un tipo prestado: es el único momento en que puede haber llegado el
/// tipo real que les faltaba.
final fxRefreshProvider = FutureProvider<bool>((ref) async {
  final ok = await ref.watch(ecbServiceProvider).refresh();
  if (ok) await ref.watch(transactionRepoProvider).recomputeEstimated();
  return ok;
});

final accountsProvider = StreamProvider(
    (ref) => ref.watch(accountRepoProvider).watchActiveAccounts());

final balancesProvider = StreamProvider<Map<int, Money>>(
    (ref) => ref.watch(accountRepoProvider).watchBalances());

final netWorthProvider = FutureProvider<Money>((ref) async {
  // Depende de los saldos para recalcularse cuando cambie un movimiento.
  ref.watch(balancesProvider);
  await ref.watch(fxRefreshProvider.future);
  return ref
      .watch(accountRepoProvider)
      .netWorthEur(ref.watch(fxRepoProvider), todayCivil());
});

final categoryRepoProvider =
    Provider((ref) => CategoryRepository(ref.watch(dbProvider)));

final categoriesProvider = StreamProvider(
    (ref) => ref.watch(categoryRepoProvider).watchActive());

final monthTransactionsProvider = StreamProvider((ref) {
  final now = DateTime.now();
  return ref.watch(transactionRepoProvider).watchBetween(
        from: firstDayOfMonth(now),
        to: lastDayOfMonth(now),
      );
});

final backupServiceProvider =
    Provider((ref) => BackupService(ref.watch(dbProvider)));

/// Días desde la última copia. `null` si nunca se ha hecho ninguna.
final daysSinceBackupProvider = FutureProvider<int?>((ref) async {
  // Depende de los movimientos para refrescarse al usar la app.
  ref.watch(monthTransactionsProvider);
  final date = await ref.watch(backupServiceProvider).lastBackupDate();
  if (date == null) return null;
  return DateTime.now().toUtc().difference(date).inDays;
});
