// lib/core/services/backup_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

part 'backup_service.g.dart';

// ─── Result ───────────────────────────────────────────────────

enum BackupStatus { success, failure, cancelled }

class BackupResult {
  final BackupStatus status;
  final String       message;
  const BackupResult._(this.status, this.message);

  factory BackupResult.success(String msg) => BackupResult._(BackupStatus.success, msg);
  factory BackupResult.failure(String msg) => BackupResult._(BackupStatus.failure, msg);
  factory BackupResult.cancelled()         => BackupResult._(BackupStatus.cancelled, 'تم الإلغاء');

  bool get isSuccess   => status == BackupStatus.success;
  bool get isCancelled => status == BackupStatus.cancelled;
}

// ─── Provider ─────────────────────────────────────────────────

@riverpod
BackupService backupService(BackupServiceRef ref) => BackupService();

// ─── Service ──────────────────────────────────────────────────

class BackupService {
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Export a zip backup and open the share sheet
  Future<BackupResult> exportBackup() async {
    try {
      final dbPath = p.join(await getDatabasesPath(), 'hamada_ai.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return BackupResult.failure('قاعدة البيانات مش موجودة');
      }

      final prefs    = await SharedPreferences.getInstance();
      final prefsMap = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        prefsMap[key] = prefs.get(key);
      }

      final tempDir   = await getTemporaryDirectory();
      final now       = DateTime.now();
      final ts        = '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
      final zipPath   = p.join(tempDir.path, 'hamada_backup_$ts.zip');

      final archive = Archive();

      // Database file
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('hamada_ai.db', dbBytes.length, dbBytes));

      // Preferences JSON
      final prefsBytes = utf8.encode(jsonEncode(prefsMap));
      archive.addFile(ArchiveFile('preferences.json', prefsBytes.length, prefsBytes));

      // Metadata
      final meta = {
        'version':    2,
        'created_at': now.toIso8601String(),
        'app':        'hamada_ai',
        'db_size':    dbBytes.length,
      };
      final metaBytes = utf8.encode(jsonEncode(meta));
      archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

      // Write zip
      final zipBytes = ZipEncoder().encode(archive)!;
      await File(zipPath).writeAsBytes(zipBytes);

      // Share
      await Share.shareXFiles(
        [XFile(zipPath, mimeType: 'application/zip')],
        subject: 'حماده AI — نسخة احتياطية $ts',
        text:    'نسخة احتياطية من تطبيق حماده AI\nحجم قاعدة البيانات: ${_formatBytes(dbBytes.length)}',
      );

      _log.i('✅ Backup exported: $zipPath (${_formatBytes(zipBytes.length)})');
      return BackupResult.success(
        'تم التصدير ✅\nالحجم: ${_formatBytes(zipBytes.length)}',
      );
    } catch (e, s) {
      _log.e('Backup export failed', error: e, stackTrace: s);
      return BackupResult.failure('فشل التصدير: ${e.toString().substring(0, 80)}');
    }
  }

  /// Import a zip backup chosen by the user
  Future<BackupResult> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type:             FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle:      'اختار ملف النسخة الاحتياطية',
      );

      if (result == null || result.files.isEmpty) {
        return BackupResult.cancelled();
      }

      final zipPath  = result.files.first.path;
      if (zipPath == null) return BackupResult.failure('مسار الملف فاضي');

      final zipBytes = await File(zipPath).readAsBytes();
      final archive  = ZipDecoder().decodeBytes(zipBytes);

      // Validate
      final metaFile = archive.findFile('meta.json');
      if (metaFile == null) {
        return BackupResult.failure('الملف مش نسخة احتياطية صحيحة — مفيش meta.json');
      }
      final meta = jsonDecode(utf8.decode(metaFile.content as List<int>)) as Map<String, dynamic>;
      if (meta['app'] != 'hamada_ai') {
        return BackupResult.failure('الملف ده مش من تطبيق حماده AI');
      }

      // Restore database
      final dbFile = archive.findFile('hamada_ai.db');
      if (dbFile != null) {
        final dbPath = p.join(await getDatabasesPath(), 'hamada_ai.db');
        await File(dbPath).writeAsBytes(dbFile.content as List<int>);
        _log.i('✅ Database restored: ${_formatBytes((dbFile.content as List<int>).length)}');
      }

      // Restore preferences
      final prefsFile = archive.findFile('preferences.json');
      if (prefsFile != null) {
        final prefsData = jsonDecode(utf8.decode(prefsFile.content as List<int>)) as Map<String, dynamic>;
        final prefs     = await SharedPreferences.getInstance();
        for (final entry in prefsData.entries) {
          final v = entry.value;
          if (v is bool)         await prefs.setBool(entry.key, v);
          else if (v is int)     await prefs.setInt(entry.key, v);
          else if (v is double)  await prefs.setDouble(entry.key, v);
          else if (v is String)  await prefs.setString(entry.key, v);
          else if (v is List)    await prefs.setStringList(entry.key, v.cast<String>());
        }
        _log.i('✅ Prefs restored: ${prefsData.length} keys');
      }

      return BackupResult.success(
        'تم الاسترجاع بنجاح ✅\n'
        'تاريخ النسخة: ${meta['created_at'] ?? 'غير معروف'}\n'
        '⚠️ أعد تشغيل التطبيق عشان التغييرات تتطبق',
      );
    } catch (e, s) {
      _log.e('Backup import failed', error: e, stackTrace: s);
      return BackupResult.failure('فشل الاسترجاع: ${e.toString().substring(0, 100)}');
    }
  }

  String _pad(int n)            => n.toString().padLeft(2, '0');
  String _formatBytes(int bytes) {
    if (bytes < 1024)       return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
