import 'package:drift/drift.dart';
import '../db/database.dart';
import '../db/tables.dart';

class CategoryRepository {
  final AppDatabase db;
  CategoryRepository(this.db);

  Stream<List<Category>> watchActive() => (db.select(db.categories)
        ..where((c) => c.isArchived.equals(false))
        ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
      .watch();

  Future<List<Category>> ofKind(CategoryKind kind) => (db.select(db.categories)
        ..where((c) => c.isArchived.equals(false) & c.kind.equalsValue(kind))
        ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
      .get();

  /// Categorías de un tipo ordenadas por uso real, para los chips de la hoja
  /// de añadir. Las que nunca has usado quedan detrás, en el orden sembrado.
  Stream<List<Category>> watchMostUsed(CategoryKind kind) => db
      .customSelect(
        '''
        SELECT c.* FROM categories c
        LEFT JOIN transactions t ON t.category_id = c.id
        WHERE c.is_archived = 0 AND c.kind = ?1
        GROUP BY c.id
        ORDER BY COUNT(t.id) DESC, c.sort_order ASC
        ''',
        variables: [Variable<String>(kind.name)],
        readsFrom: {db.categories, db.transactions},
      )
      .watch()
      .map((rows) => rows.map((r) => db.categories.map(r.data)).toList());

  Future<int> create({
    required String name,
    required CategoryKind kind,
    String icon = '🏷️',
  }) =>
      db.into(db.categories).insert(
            CategoriesCompanion.insert(name: name, kind: kind, icon: Value(icon)),
          );

  /// Se archiva, no se borra: los movimientos conservan su categoría.
  Future<void> archive(int id) => (db.update(db.categories)
        ..where((c) => c.id.equals(id)))
      .write(const CategoriesCompanion(isArchived: Value(true)));
}
