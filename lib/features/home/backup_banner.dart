// lib/features/home/backup_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../settings/settings_screen.dart';

/// Aviso pasivo: ni diálogo ni bloqueo. Siete días es la ventana en la que
/// Safari empieza a expulsar el almacenamiento local, que es el riesgo real
/// cuando la app corre como web en el iPhone.
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  static const _umbral = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dias = ref.watch(daysSinceBackupProvider);

    return dias.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (d) {
        if (d != null && d < _umbral) return const SizedBox.shrink();
        final texto = d == null
            ? 'Sin copia de seguridad'
            : 'Última copia hace $d días';
        return Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: InkWell(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.backup_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texto)),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
