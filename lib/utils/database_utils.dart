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

      // Verificar si la columna grupo_letra existe en la tabla grupos
      final gruposResult = await db.rawQuery("PRAGMA table_info(grupos)");
      final grupoLetraExists =
          gruposResult.any((column) => column['name'] == 'grupo_letra');

      if (!grupoLetraExists) {
        // Agregar columna grupo_letra si no existe
        await db.execute('ALTER TABLE grupos ADD COLUMN grupo_letra TEXT');
        print(
            'Migración completada: columna grupo_letra agregada a la tabla grupos');

        // Actualizar registros existentes con grupo_letra por defecto
        await db.execute('''
          UPDATE grupos 
          SET grupo_letra = 'A'
          WHERE grupo_letra IS NULL
        ''');
        print('Registros existentes actualizados con grupo_letra por defecto');
      }

      // Verificar si la tabla usuarios existe
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='usuarios'");
      if (tables.isEmpty) {
        // Crear tabla usuarios
        await db.execute('''
          CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            nombre_completo TEXT NOT NULL,
            rol TEXT NOT NULL DEFAULT 'usuario',
            activo INTEGER NOT NULL DEFAULT 1,
            fecha_creacion TEXT NOT NULL DEFAULT (datetime('now')),
            ultimo_acceso TEXT
          )
        ''');

        // Crear índices
        await db.execute(
            'CREATE INDEX idx_usuarios_username ON usuarios(username)');
        await db
            .execute('CREATE INDEX idx_usuarios_activo ON usuarios(activo)');

        // Insertar usuario administrador por defecto
        await db.insert('usuarios', {
          'username': 'admin',
          'password': 'epo26pass',
          'nombre_completo': 'Administrador del Sistema',
          'rol': 'admin',
          'activo': 1,
          'fecha_creacion': DateTime.now().toIso8601String(),
        });

        print('Migración completada: tabla usuarios creada');
      }
    } catch (e) {
      print('Error en migración: $e');
    }
  }

  // Función para autenticar usuarios
  static Future<Map<String, dynamic>?> authenticateUser(
      String username, String password) async {
    try {
      final db = await getDatabase();

      // Buscar usuario por username y password
      final result = await db.query(
        'usuarios',
        where: 'username = ? AND password = ? AND activo = 1',
        whereArgs: [username, password],
        limit: 1,
      );

      if (result.isNotEmpty) {
        final user = result.first;

        // Actualizar último acceso
        await db.update(
          'usuarios',
          {'ultimo_acceso': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [user['id']],
        );

        return user;
      }

      return null;
    } catch (e) {
      print('Error en autenticación: $e');
      return null;
    }
  }
}
