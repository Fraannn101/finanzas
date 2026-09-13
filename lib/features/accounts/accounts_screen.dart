// lib/features/accounts/accounts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/currency.dart';
import '../../core/formatting.dart';
import '../../core/money.dart';
import '../../data/repositories/account_repository.dart';
import 'new_account_dialog.dart';

final _groupsProvider = FutureProvider<List<AccountGroup>>((ref) async {
  ref.watch(accountsProvider); // recarga al crear o archivar
  return ref.watch(accountRepoProvider).groupedByInstitution();
});

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(_groupsProvider);
    final balances = ref.watch(balancesProvider).value ?? const <int, Money>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no tienes cuentas.\nToca + para crear la primera.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final group in list) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Text(
                    group.institution?.name ?? 'Sin banco',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final account in group.accounts)
                  ListTile(
                    title: Text(account.name),
                    subtitle: Text(account.currency),
                    trailing: Text(
                      formatMoney(balances[account.id] ??
                          Money.zero(Currency.byCode(account.currency))),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onLongPress: () =>
                        _confirmArchive(context, ref, account.id, account.name),
                  ),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const NewAccountDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmArchive(
      BuildContext context, WidgetRef ref, int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Archivar «$name»?'),
        content: const Text(
          'Desaparecerá de las listas, pero sus movimientos se conservan y '
          'siguen contando en tu histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(accountRepoProvider).archive(id);
      ref.invalidate(_groupsProvider);
    }
  }
}
