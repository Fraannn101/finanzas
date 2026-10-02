import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// El archivo no tiene la forma esperada.
class BackupFormatError implements Exception {
  final String message;
  BackupFormatError(this.message);
  @override
  String toString() => message;
}

/// La contraseña no abre el archivo, o el archivo está dañado. Las dos causas
/// son indistinguibles: GCM solo dice que la autenticación ha fallado, y
/// fingir que sabemos cuál de las dos es sería mentir al usuario.
class BackupPasswordError implements Exception {
  @override
  String toString() => 'Contraseña incorrecta, o el archivo está dañado';
}

/// Cabecera en claro + cuerpo cifrado con AES-256-GCM.
///
/// El salt y el nonce van legibles a propósito: no son secretos, y sin ellos
/// el archivo no se podría descifrar ni con la contraseña correcta.
class BackupCrypto {
  static const magic = 'FINANZAS';
  static const formatVersion = 1;

  static const _magicLength = 8;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _headerLength = _magicLength + 1 + _saltLength + _nonceLength;

  /// Fijo y documentado a propósito: si cambiara entre versiones, las copias
  /// antiguas dejarían de abrirse. Subirlo exige incrementar [formatVersion]
  /// y conservar la lectura del anterior.
  static const _iterations = 100000;

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  /// Lee la versión de formato **sin descifrar**, que es lo que permite
  /// rechazar un archivo del futuro sin pedir siquiera la contraseña.
  static int readFormat(Uint8List bytes) {
    if (bytes.length < _headerLength) {
      throw BackupFormatError('Este archivo no es una copia de Finanzas');
    }
    if (utf8.decode(bytes.sublist(0, _magicLength), allowMalformed: true) != magic) {
      throw BackupFormatError('Este archivo no es una copia de Finanzas');
    }
    return bytes[_magicLength];
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      _kdf.deriveKeyFromPassword(password: password, nonce: salt);

  /// La cabecera entera se pasa como datos autenticados (AAD). No se cifra
  /// —hay que poder leerla sin contraseña— pero sí queda firmada, de modo que
  /// cambiar un byte rompe el descifrado. Sin esto, el byte de versión sería
  /// libre de manipular: `decrypt` seguiría funcionando y devolvería el texto
  /// correcto bajo una versión mentida.
  static Uint8List _header(int version, List<int> salt, List<int> nonce) =>
      Uint8List.fromList([...utf8.encode(magic), version, ...salt, ...nonce]);

  static Future<Uint8List> encrypt(String json, String password) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(password, salt);
    final header = _header(formatVersion, salt, nonce);

    final box = await _cipher.encrypt(
      utf8.encode(json),
      secretKey: key,
      nonce: nonce,
      aad: header,
    );

    return Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<String> decrypt(Uint8List bytes, String password) async {
    readFormat(bytes); // valida la cabecera antes de nada

    final salt = bytes.sublist(_magicLength + 1, _magicLength + 1 + _saltLength);
    final nonce = bytes.sublist(_magicLength + 1 + _saltLength, _headerLength);
    final rest = bytes.sublist(_headerLength);
    if (rest.length < 16) {
      throw BackupFormatError('El archivo está incompleto');
    }
    final cipherText = rest.sublist(0, rest.length - 16);
    final mac = Mac(rest.sublist(rest.length - 16));

    final key = await _deriveKey(password, salt);
    try {
      final clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
        aad: bytes.sublist(0, _headerLength),
      );
      return utf8.decode(clear);
    } catch (_) {
      throw BackupPasswordError();
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = SecretKeyData.random(length: length);
    return Uint8List.fromList(random.bytes);
  }
}
