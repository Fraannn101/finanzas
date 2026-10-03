// lib/data/backup/backup_file.dart
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Lo único que distingue Android de la web.
///
/// En Android se abre el menú de compartir, que es lo que permite mandar la
/// copia a Drive o al correo —es decir, **sacarla del dispositivo**, que es
/// justo de lo que protege—. En web solo cabe una descarga: un navegador no
/// escribe en el disco sin que el usuario confirme, y eso es una protección
/// suya, no una carencia nuestra.
class BackupFile {
  static String nameFor(DateTime when) {
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    return 'finanzas-$y-$m-$d.backup';
  }

  static Future<void> deliver(Uint8List bytes, {DateTime? when}) async {
    final name = nameFor(when ?? DateTime.now());
    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        mimeType: MimeType.other,
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: name, mimeType: 'application/octet-stream')
        ],
        subject: name,
      ),
    );
  }

  /// `null` si el usuario cancela.
  static Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile();
    return file?.readAsBytes();
  }
}
