// lib/features/settings/settings_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/backup/backup_crypto.dart';
import '../../data/backup/backup_file.dart';
import '../../data/backup/backup_service.dart';
import 'password_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final dias = ref.watch(daysSinceBackupProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              'COPIA DE SEGURIDAD',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Exportar copia'),
            subtitle: Text(
              dias == null ? 'Nunca has hecho una' : 'Última hace $dias días',
            ),
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Restaurar copia'),
            subtitle: const Text('Sustituye todos los datos actuales'),
            enabled: !_busy,
            onTap: _import,
          ),
          FutureBuilder<bool>(
            future: ref.read(backupServiceProvider).hasRescue(),
            builder: (_, snapshot) => snapshot.data == true
                ? ListTile(
                    leading: const Icon(Icons.undo),
                    title: const Text('Deshacer la última restauración'),
                    enabled: !_busy,
                    onTap: _undo,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final password = await askPassword(
      context,
      title: 'Contraseña de la copia',
      confirm: true,
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      // Se exporta **una sola vez**: cada llamada a `export` genera un archivo
      // nuevo y consume el rescate, así que hacerlo dos veces para enseñar un
      // resumen daría dos copias distintas.
      final bytes = await service.export(password);
      final resumen = await service.summarize(bytes, password);
      await BackupFile.deliver(bytes);
      ref.invalidate(daysSinceBackupProvider);
      _say(
        'Copia creada: ${resumen.movimientos} movimientos, '
        '${resumen.cuentas} cuentas',
      );
    } catch (e) {
      _say('No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    // `pick` puede lanzar: lectura fallida del archivo, o un archivo
    // demasiado grande para ser una copia. Sin este try, el usuario vería un
    // error crudo de plataforma.
    final Uint8List? bytes;
    try {
      bytes = await BackupFile.pick();
    } on BackupFormatError catch (e) {
      _say(e.toString());
      return;
    } catch (e) {
      _say('No se pudo leer el archivo: $e');
      return;
    }
    if (bytes == null || !mounted) return;

    final password = await askPassword(
      context,
      title: 'Contraseña del archivo',
      confirm: false,
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    final service = ref.read(backupServiceProvider);
    try {
      final resumen = await service.summarize(bytes, password);
      final actuales = await service.currentCounts();
      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Restaurar esta copia?'),
          content: Text(
            'Vas a sustituir ${actuales.movimientos} movimientos por '
            '${resumen.movimientos}, de una copia del '
            '${resumen.exportado.toLocal().toString().substring(0, 10)}.\n\n'
            'Se guardará una copia de rescate por si te equivocas de archivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      await service.import(bytes, password);
      _invalidateAll();
      _say('Restaurado: ${resumen.movimientos} movimientos');
    } on BackupPasswordError catch (e) {
      _say(e.toString());
    } on BackupFormatError catch (e) {
      _say(e.toString());
    } on BackupTooNewError catch (e) {
      _say(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).undoImport();
      _invalidateAll();
      _say('Restauración deshecha');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateAll() {
    ref.invalidate(accountsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(balancesProvider);
    ref.invalidate(netWorthProvider);
    ref.invalidate(monthTransactionsProvider);
    ref.invalidate(daysSinceBackupProvider);
    if (mounted) setState(() {});
  }
}
