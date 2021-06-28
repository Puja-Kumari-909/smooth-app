import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:smooth_app/database/bulk_insertable.dart';
import 'package:smooth_app/database/bulk_deletable.dart';
import 'package:sqflite/sqflite.dart';

/// Manager for bulk database inserts and deletes
///
/// In tests it looked 33% faster to use delete/insert rather than upsert
/// And of course it's much faster to perform bulk actions
/// rather than numerous single actions
/// cf. [BulkInsertable], [BulkDeletable]
class BulkManager {
  /// Max number of parameters in a SQFlite query
  ///
  /// cf. SQLITE_MAX_VARIABLE_NUMBER, "which defaults to 999"
  // TODO(monsieurtanuki): find a way to retrieve this number from SQFlite system tables, cf. https://github.com/tekartik/sqflite/issues/663
  static const int _SQLITE_MAX_VARIABLE_NUMBER = 999;

  /// Optimized bulk insert
  Future<void> insert({
    required final BulkInsertable bulkInsertable,
    required final List<dynamic> parameters,
    required final DatabaseExecutor databaseExecutor,
  }) async {
    final String tableName = bulkInsertable.getTableName();
    final List<String> columnNames = bulkInsertable.getInsertColumns();
    final int numCols = columnNames.length;
    if (parameters.isEmpty) {
      return;
    }
    if (columnNames.isEmpty) {
      throw Exception('There must be at least one column!');
    }
    if (parameters.length % numCols != 0) {
      throw Exception(
          'Parameter list size (${parameters.length}) cannot be divided by $numCols');
    }
    final String variables = '?${',?' * (columnNames.length - 1)}';
    final int maxSlice = _SQLITE_MAX_VARIABLE_NUMBER ~/ numCols;
    for (int start = 0; start < parameters.length; start += maxSlice) {
      final int size = min(parameters.length - start, maxSlice);
      final int additionalRecordsNumber = -1 + size ~/ numCols;
      await databaseExecutor.rawInsert(
        'insert into $tableName(${columnNames.join(',')}) '
        'values($variables)${',($variables)' * additionalRecordsNumber}',
        parameters.sublist(start, start + size),
      );
    }
  }

  /// Optimized bulk delete
  Future<void> delete({
    required final BulkDeletable bulkDeletable,
    required final List<dynamic> parameters,
    required final DatabaseExecutor databaseExecutor,
    final List<dynamic> additionalParameters,
  }) async {
    final String tableName = bulkDeletable.getTableName();
    if (parameters.isEmpty) {
      return;
    }
    final int maxSlice =
        _SQLITE_MAX_VARIABLE_NUMBER - (additionalParameters.length);
    for (int start = 0; start < parameters.length; start += maxSlice) {
      final int size = min(parameters.length - start, maxSlice);
      final List<dynamic> currentParameters = <dynamic>[];
      if (additionalParameters.isNotEmpty) {
        currentParameters.addAll(additionalParameters);
      }
      currentParameters.addAll(parameters.sublist(start, start + size));
      await databaseExecutor.delete(
        tableName,
        where: bulkDeletable.getDeleteWhere(currentParameters),
        whereArgs: currentParameters,
      );
    }
  }
}
