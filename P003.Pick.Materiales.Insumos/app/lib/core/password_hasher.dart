import 'dart:convert';
import 'package:crypto/crypto.dart';

class PasswordHasher {
  static const int iteraciones = 10000;

  static String hash(String pin, String saltHex) {
    final salt = _hexADecodable(saltHex);
    var bloque = <int>[...salt, 0, 0, 0, 1];
    var u = Hmac(sha256, utf8.encode(pin)).convert(bloque).bytes;
    final acumulado = List<int>.from(u);
    for (var i = 1; i < iteraciones; i++) {
      u = Hmac(sha256, utf8.encode(pin)).convert(u).bytes;
      for (var j = 0; j < u.length; j++) {
        acumulado[j] ^= u[j];
      }
    }
    return _bytesAHex(acumulado);
  }

  static List<int> _hexADecodable(String hex) {
    final out = List<int>.generate(hex.length ~/ 2, (i) {
      return int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    });
    return out;
  }

  static String _bytesAHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
