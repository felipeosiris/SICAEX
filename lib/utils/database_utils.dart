import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

class DatabaseUtils {
  static Future<Database> getDatabase() async {
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;

    final appDocDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDocDir.path, 'mi_base.db');

    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      final data = await rootBundle.load('assets/database/mi_base.db');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await dbFile.writeAsBytes(bytes);
      print('Base de datos copiada a: $dbPath');
    } else {
      print('Usando base existente en: $dbPath');
    }

    final db = await dbFactory.openDatabase(dbPath);

    // Ejecutar migración para agregar columna hora si no existe
    await _migrateDatabase(db);

    return db;
  }

  static Future<void> _migrateDatabase(Database db) async {
    try {
      // Verificar si la columna hora existe
      final result = await db.rawQuery("PRAGMA table_info(asistencias)");
      final columnExists = result.any((column) => column['name'] == 'hora');

      if (!columnExists) {
        // Agregar columna hora si no existe
        await db.execute('ALTER TABLE asistencias ADD COLUMN hora TEXT');
        print(
            'Migración completada: columna hora agregada a la tabla asistencias');

        // Actualizar registros existentes con horas por defecto
        await db.execute('''
          UPDATE asistencias 
          SET hora = CASE 
              WHEN id % 5 = 0 THEN '08:00:00'
              WHEN id % 5 = 1 THEN '08:15:00'
              WHEN id % 5 = 2 THEN '08:30:00'
              WHEN id % 5 = 3 THEN '08:45:00'
              WHEN id % 5 = 4 THEN '09:00:00'
          END
          WHERE hora IS NULL
        ''');
        print('Registros existentes actualizados con horas por defecto');
      }
    } catch (e) {
      print('Error en migración: $e');
    }
  }
}
