import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:SICAE/components/components.dart';
import 'package:SICAE/utils/max_width_extension.dart';
import 'package:SICAE/utils/database_utils.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final _textController = TextEditingController();
final _focusNode = FocusNode();

class ListPage extends StatelessWidget {
  static const String name = 'list';

  ListPage({super.key});

  Future<Database> getDatabase() async {
    return await DatabaseUtils.getDatabase();
  }

  Future<void> insertData(int alumnoId) async {
    final db = await getDatabase();
    final now = DateTime.now();
    final fechaHoy = now.toIso8601String().split('T').first;
    final horaHoy =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    await db.insert(
      'asistencias',
      {
        "alumno_id": alumnoId,
        "fecha": fechaHoy,
        "hora": horaHoy,
        "presente": 1
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _textController.clear();
    _focusNode.requestFocus();
  }

  Future<int> getAlumnoIdByName(String name) async {
    final db = await getDatabase();
    final result = await db.query(
      'alumnos',
      columns: ['id'],
      where: 'friendlyName = ?',
      whereArgs: [name],
    );
    if (result.isNotEmpty) {
      return result.first['id'] as int;
    } else {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              const MinimalMenuBar(),
              Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/logo26.png',
                        height: 250,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Bienvenido EPO. 26",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 50),
                      Icon(
                        Icons.qr_code_scanner,
                        size: 100,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Escanee el código QR",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        focusNode: _focusNode,
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'leyendo código QR...',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (value) async {
                          final alumnoId = await getAlumnoIdByName(
                              value.corregirAcentosQR());

                          print(value.corregirAcentosQR());
                          print(alumnoId);

                          if (alumnoId != 0) {
                            await insertData(alumnoId);
                            print('Código QR escaneado: $value');
                          } else {
                            print('Alumno no encontrado con el nombre: $value');
                            _textController.clear();
                            _focusNode.requestFocus();
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Instrucciones para escanear el código QR:",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrangeAccent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "1. Muestre el código QR al escáner.",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "2. Si el código QR es válido, se registrará automáticamente y se escuchará un sonido (beep).",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ].toMaxWidth(),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: MaxWidthBox(
              maxWidth: 1200,
              backgroundColor: Colors.white,
              child: Container(),
            ),
          ),
          ...[
            divider,
            const Footer(),
          ].toMaxWidthSliver(),
        ],
      ),
    );
  }
}

extension NombreConAcentos on String {
  String corregirAcentosQR() {
    return this
        .replaceAll('50049', 'Á')
        .replaceAll('50061', 'Í')
        .replaceAll('50073', 'É')
        .replaceAll('50085', 'Ó')
        .replaceAll('50097', 'Ú')
        .replaceAll('50109', 'Ñ')
        .replaceAll('50121', 'Ü')
        .toUpperCase();
  }
}
