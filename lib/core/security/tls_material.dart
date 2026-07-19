import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';

import '../foundation/foundation.dart';
import 'secret_store.dart';

final class TlsMaterial {
  const TlsMaterial({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  SecurityContext createContext() {
    final context = SecurityContext();
    context.useCertificateChainBytes(utf8.encode(certificatePem));
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }
}

final class TlsMaterialManager {
  const TlsMaterialManager(this._secrets, this._clock);

  final SecretStore _secrets;
  final Clock _clock;

  Future<TlsMaterial> loadOrCreate() async {
    final certificate = await _secrets.read('tlsCertificate');
    final privateKey = await _secrets.read('tlsPrivateKey');
    if (certificate == null && privateKey == null) return rotate();
    if (certificate == null || privateKey == null) {
      throw const TlsMaterialException('tls_material_incomplete');
    }
    return _validate(certificate, privateKey);
  }

  Future<TlsMaterial> rotate() async {
    final generated = await Isolate.run(_generate);
    final material = _validate(
      generated.certificatePem,
      generated.privateKeyPem,
    );
    await _secrets.write('tlsPrivateKey', material.privateKeyPem);
    await _secrets.write('tlsCertificate', material.certificatePem);
    return material;
  }

  TlsMaterial _validate(String certificate, String privateKey) {
    try {
      final parsed = X509Utils.x509CertificateFromPem(certificate);
      final validity = parsed.tbsCertificate!.validity;
      final now = _clock.now();
      if (now.isBefore(validity.notBefore.toUtc()) ||
          now.isAfter(validity.notAfter.toUtc())) {
        throw const TlsMaterialException('tls_certificate_expired');
      }
      if (!X509Utils.checkX509Signature(certificate)) {
        throw const TlsMaterialException('tls_certificate_invalid');
      }
      final material = TlsMaterial(
        certificatePem: certificate,
        privateKeyPem: privateKey,
        fingerprint: _formatFingerprint(parsed.sha256Thumbprint ?? ''),
      );
      material.createContext();
      return material;
    } on TlsMaterialException {
      rethrow;
    } on Object {
      throw const TlsMaterialException('tls_material_invalid');
    }
  }

  static TlsMaterial _generate() {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      const {'CN': 'ephtodo local sync', 'O': 'ephtodo'},
      privateKey,
      publicKey,
      san: const ['localhost'],
    );
    final random = Random.secure();
    final serial = List<int>.generate(16, (_) => random.nextInt(256))
        .fold<BigInt>(
          BigInt.zero,
          (value, byte) => (value << 8) | BigInt.from(byte),
        );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      397,
      sans: const ['localhost'],
      extKeyUsage: const [ExtendedKeyUsage.SERVER_AUTH],
      cA: false,
      serialNumber: serial.toString(),
      notBefore: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );
    final key = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    final fingerprint = _formatFingerprint(
      X509Utils.x509CertificateFromPem(certificate).sha256Thumbprint ?? '',
    );
    return TlsMaterial(
      certificatePem: certificate,
      privateKeyPem: key,
      fingerprint: fingerprint,
    );
  }

  static String _formatFingerprint(String value) {
    final normalized = value.replaceAll(':', '').toUpperCase();
    if (normalized.length != 64) {
      throw const TlsMaterialException('tls_fingerprint_invalid');
    }
    return [
      for (var index = 0; index < normalized.length; index += 2)
        normalized.substring(index, index + 2),
    ].join(':');
  }
}

final class TlsMaterialException implements Exception {
  const TlsMaterialException(this.code);
  final String code;
}
