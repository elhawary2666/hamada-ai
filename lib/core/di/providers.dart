// lib/core/di/providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../database/database_helper.dart';

part 'providers.g.dart';

@riverpod
DatabaseHelper databaseHelper(DatabaseHelperRef ref) =>
    DatabaseHelper.instance;
