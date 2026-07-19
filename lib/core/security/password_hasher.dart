import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final class Argon2idPasswordHasher {
  const Argon2idPasswordHasher({
    this.memoryKiB = 65536,
    this.iterations = 3,
    this.parallelism = 4,
    this.outputLength = 32,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int outputLength;

  Future<String> hash(String password) async {
    _validatePassword(password);
    final salt = _randomBytes(16);
    return Isolate.run(
      () => _encode(
        password,
        salt,
        memoryKiB,
        iterations,
        parallelism,
        outputLength,
      ),
    );
  }

  Future<bool> verify(String password, String encoded) async {
    if (password.isEmpty || password.length > 1024) return false;
    final parsed = _parse(encoded);
    if (parsed == null) return false;
    final actual = await Isolate.run(
      () => _derive(
        password,
        parsed.salt,
        parsed.memoryKiB,
        parsed.iterations,
        parsed.parallelism,
        parsed.hash.length,
      ),
    );
    return constantTimeEquals(actual, parsed.hash);
  }

  static bool constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var index = 0; index < length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  void _validatePassword(String password) {
    if (password.length < 12 || password.length > 1024) {
      throw const FormatException(
        'The sync password must contain between 12 and 1024 characters.',
      );
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static String _encode(
    String password,
    Uint8List salt,
    int memory,
    int iterations,
    int parallelism,
    int outputLength,
  ) {
    final hash = _derive(
      password,
      salt,
      memory,
      iterations,
      parallelism,
      outputLength,
    );
    final encodedSalt = base64Url.encode(salt).replaceAll('=', '');
    final encodedHash = base64Url.encode(hash).replaceAll('=', '');
    return '\$argon2id\$v=19\$m=$memory,t=$iterations,p=$parallelism'
        '\$$encodedSalt\$$encodedHash';
  }

  static Uint8List _derive(
    String password,
    Uint8List salt,
    int memory,
    int iterations,
    int parallelism,
    int outputLength,
  ) {
    final generator = Argon2BytesGenerator()
      ..init(
        Argon2Parameters(
          Argon2Parameters.ARGON2_id,
          Uint8List.fromList(salt),
          desiredKeyLength: outputLength,
          memory: memory,
          iterations: iterations,
          lanes: parallelism,
          version: Argon2Parameters.ARGON2_VERSION_13,
        ),
      );
    return generator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static _EncodedArgon2? _parse(String encoded) {
    try {
      final parts = encoded.split(r'$');
      if (parts.length != 6 || parts[1] != 'argon2id' || parts[2] != 'v=19') {
        return null;
      }
      final parameters = <String, int>{};
      for (final value in parts[3].split(',')) {
        final pair = value.split('=');
        if (pair.length != 2) return null;
        parameters[pair[0]] = int.parse(pair[1]);
      }
      final memory = parameters['m'];
      final iterations = parameters['t'];
      final parallelism = parameters['p'];
      if (memory == null ||
          memory < 8192 ||
          memory > 131072 ||
          iterations == null ||
          iterations < 2 ||
          iterations > 8 ||
          parallelism == null ||
          parallelism < 1 ||
          parallelism > 4) {
        return null;
      }
      final salt = base64Url.decode(base64Url.normalize(parts[4]));
      final hash = base64Url.decode(base64Url.normalize(parts[5]));
      if (salt.length < 16 || salt.length > 64 || hash.length != 32) {
        return null;
      }
      return _EncodedArgon2(
        salt: salt,
        hash: hash,
        memoryKiB: memory,
        iterations: iterations,
        parallelism: parallelism,
      );
    } on Object {
      return null;
    }
  }
}

final class _EncodedArgon2 {
  const _EncodedArgon2({
    required this.salt,
    required this.hash,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  final Uint8List salt;
  final Uint8List hash;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
}
