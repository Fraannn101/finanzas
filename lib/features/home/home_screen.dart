// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/formatting.dart';
import '../../data/db/database.dart';
import '../../data/repositories/fx_repository.dart';
import '../accounts/accounts_screen.dart';
import '../transactions/add_sheet.dart';
import '../transactions/edit_screen.dart';
import 'transaction_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(monthTransactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final netWorth = ref.watch(netWorthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Este mes'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: netWorth.when(
                data: (m) => Text(formatMoney(m),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                loading: () => const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                // Si falta el tipo de una sola divisa no hay total posible.
                // Un total parcial disfrazado de total sería peor, pero el
                // guion debe poder decir por qué.
                error: (e, _) => Tooltip(
                  message: e is NoFxRateAvailable
                      ? e.toString()
                      : 'No se ha podido calcular el total',
                  child: const Text('—'),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Cuentas',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
        ],
      ),
      body: transactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no hay movimientos este mes.\n'
                  'Toca + para añadir el primero.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final accountsById = {
            for (final a in accounts.value ?? const <Account>[]) a.id: a,
          };
          final categoriesById = {
            for (final c in categories.value ?? const <Category>[]) c.id: c,
          };
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final tx = list[i];
              final category = categoriesById[tx.categoryId];
              return TransactionTile(
                tx: tx,
                accountName: accountsById[tx.accountId]?.name ?? '—',
                categoryName: category?.name,
                categoryIcon: category?.icon ?? '🏷️',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => EditTransactionScreen(txId: tx.id)),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
