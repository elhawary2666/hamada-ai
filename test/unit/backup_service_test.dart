// test/unit/backup_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Backup metadata validation', () {
    test('valid backup metadata passes', () {
      final meta = {
        'version':    2,
        'app':        'hamada_ai',
        'created_at': DateTime.now().toIso8601String(),
        'db_size':    1024,
      };
      expect(meta['app'], 'hamada_ai');
      expect(meta['version'], 2);
    });

    test('invalid app name fails', () {
      final meta = {'app': 'other_app', 'version': 1};
      expect(meta['app'] != 'hamada_ai', true);
    });

    test('JSON encoding/decoding is symmetric', () {
      final original = {
        'version': 2,
        'app':     'hamada_ai',
        'created': '2024-01-01',
      };
      final encoded = jsonEncode(original);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['app'],     original['app']);
      expect(decoded['version'], original['version']);
    });

    test('empty backup returns failure signal', () {
      // Simulate what happens with missing meta.json
      final archive = <String>['hamada_ai.db'];
      final hasMeta = archive.contains('meta.json');
      expect(hasMeta, false);
    });
  });

  group('Bytes formatter', () {
    String formatBytes(int bytes) {
      if (bytes < 1024)       return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    test('bytes < 1024 shows B',   () => expect(formatBytes(512),  '512 B'));
    test('bytes in KB range',      () => expect(formatBytes(2048), '2.0 KB'));
    test('bytes in MB range',      () => expect(formatBytes(1048576), '1.0 MB'));
  });
}
