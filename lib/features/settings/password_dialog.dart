// lib/features/settings/password_dialog.dart
import 'package:flutter/material.dart';

/// Pide una contraseña. Con [confirm], exige escribirla dos veces.
///
/// El aviso va en la pantalla y destacado, no en una ayuda enterrada: es la
/// única oportunidad de decirle al usuario que esto no tiene vuelta atrás.
Future<String?> askPassword(
  BuildContext context, {
  required String title,
  required bool confirm,
}) {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (confirm)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Si pierdes esta contraseña, el archivo no se puede '
                  'recuperar. No hay forma de restablecerla.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            TextField(
              controller: first,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(
                controller: second,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repítela'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.isEmpty) {
                setState(() => error = 'Escribe una contraseña');
                return;
              }
              if (confirm && first.text != second.text) {
                setState(() => error = 'Las dos no coinciden');
                return;
              }
              Navigator.of(dialogContext).pop(first.text);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    ),
  );
}
