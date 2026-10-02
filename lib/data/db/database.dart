// lib/data/db/database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Institutions, Accounts, Categories, Transactions, FxRates, AppSettings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'finanzas'));

  /// Base en memoria, para las pruebas.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedCategories();
        },
        beforeOpen: (details) async {
          // Sin esto SQLite ignora las claves foráneas en silencio.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedCategories() async {
    const expenses = <(String, String)>[
      ('Súper', '🛒'),
      ('Restaurantes', '🍽️'),
      ('Casa', '🏠'),
      ('Transporte', '⛽'),
      ('Salud', '💊'),
      ('Ocio', '🎬'),
      ('Compras', '🛍️'),
      ('Suscripciones', '🔁'),
      ('Otros', '📦'),
    ];
    const incomes = <(String, String)>[
      ('Nómina', '💼'),
      ('Freelance', '🧾'),
      ('Regalos', '🎁'),
      ('Otros ingresos', '📥'),
    ];

    var order = 0;
    for (final (name, icon) in expenses) {
      await into(categories).insert(CategoriesCompanion.insert(
        name: name,
        kind: CategoryKind.expense,
        icon: Value(icon),
        sortOrder: Value(order++),
      ));
    }
    order = 0;
    for (final (name, icon) in incomes) {
      await into(categories).insert(CategoriesCompanion.insert(
        name: name,
        kind: CategoryKind.income,
        icon: Value(icon),
        sortOrder: Value(order++),
      ));
    }
  }
}
