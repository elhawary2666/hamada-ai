// lib/core/services/export_service.dart
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../di/providers.dart';

part 'export_service.g.dart';

@riverpod
ExportService exportService(ExportServiceRef ref) =>
    ExportService(db: ref.watch(databaseHelperProvider));

class ExportService {
  ExportService({required this.db});
  final DatabaseHelper db;

  Future<void> exportTransactionsCSV({int? year, int? month}) async {
    final now = DateTime.now();
    final y   = year  ?? now.year;
    final m   = month ?? now.month;

    final rows = await db.getTransactionsByMonth(y, m);

    final csvData = [
      // Header
      ['التاريخ', 'النوع', 'المبلغ', 'الفئة', 'الوصف', 'طريقة الدفع'],
      // Data
      ...rows.map((r) => [
        DateFormat('yyyy/MM/dd').format(
            DateTime.fromMillisecondsSinceEpoch(r['date'] as int)),
        r['type'] == 'income' ? 'دخل' : 'مصروف',
        (r['amount'] as num).toStringAsFixed(2),
        r['category'] ?? '',
        r['description'] ?? '',
        r['payment_method'] ?? 'cash',
      ]),
    ];

    final csv      = const ListToCsvConverter().convert(csvData);
    final tempDir  = await getTemporaryDirectory();
    final fileName = 'hamada_finance_${y}_${m.toString().padLeft(2,'0')}.csv';
    final file     = File('${tempDir.path}/$fileName');
    await file.writeAsString('\uFEFF$csv'); // BOM for Arabic in Excel

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'حماده AI — بيانات مالية $m/$y',
    );
  }

  Future<void> exportAllDataCSV() async {
    // Export all transactions all time
    final rows = await db.getAll(
      Tables.financeTransactions,
      orderBy: 'date DESC',
    );

    final csvData = [
      ['التاريخ', 'النوع', 'المبلغ', 'الفئة', 'الوصف', 'طريقة الدفع'],
      ...rows.map((r) => [
        DateFormat('yyyy/MM/dd').format(
            DateTime.fromMillisecondsSinceEpoch(r['date'] as int)),
        r['type'] == 'income' ? 'دخل' : 'مصروف',
        (r['amount'] as num).toStringAsFixed(2),
        r['category'] ?? '',
        r['description'] ?? '',
        r['payment_method'] ?? '',
      ]),
    ];

    final csv     = const ListToCsvConverter().convert(csvData);
    final tempDir = await getTemporaryDirectory();
    final file    = File('${tempDir.path}/hamada_all_transactions.csv');
    await file.writeAsString('\uFEFF$csv');

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'حماده AI — كل البيانات المالية',
    );
  }
}
