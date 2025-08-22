import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:SICAE/components/components.dart';
import 'package:SICAE/utils/max_width_extension.dart';
import 'package:path_provider/path_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:excel/excel.dart'; // Importación para manejar Excel

class AttendancePage extends StatefulWidget {
  static const String name = 'attendance';

  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  bool isLoading = true;
  Map<String, List<Map<String, dynamic>>> groupedAttendance = {};

  Future<Database> getDatabase() async {
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
    }

    return dbFactory.openDatabase(dbPath);
  }

  @override
  void initState() {
    super.initState();
    fetchAttendance();
  }

  Future<void> fetchAttendance() async {
    final db = await getDatabase();
    final today = DateTime.now().toIso8601String().split('T').first;

    final result = await db.rawQuery('''
      SELECT a.nombre, a.friendlyName, g.anio_escolar AS anio, g.semestre, g.nombre AS grupo_nombre, asi.presente
      FROM asistencias asi
      JOIN alumnos a ON asi.alumno_id = a.id
      JOIN grupos g ON a.grupo_id = g.id
      WHERE asi.fecha = ?
    ''', [today]);

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var entry in result) {
      final groupKey = 'Año ${entry['anio']} - Semestre ${entry['semestre']}';
      grouped.putIfAbsent(groupKey, () => []).add(entry);
    }

    grouped.forEach((key, value) {
      value.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    });

    setState(() {
      groupedAttendance = grouped;
      isLoading = false;
    });
  }

  Future<void> downloadAttendanceReport() async {
    final excel = Excel.createExcel();
    final sheet = excel['Asistencia'];

    // Establecer estilos de celda siguiendo la lógica de file_context_0
    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue, // Azul
      fontColorHex: ExcelColor.white, // Blanco
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    final dataStylePresente = CellStyle(
      backgroundColorHex: ExcelColor.green, // Verde
      fontColorHex: ExcelColor.green, // Verde
    );

    final dataStyleAusente = CellStyle(
      backgroundColorHex: ExcelColor.red, // Rojo
      fontColorHex: ExcelColor.red, // Rojo
    );

    // Agregar encabezados y fusionar celdas
    final titulo = sheet.cell(CellIndex.indexByString("A1"));
    titulo.value = TextCellValue('Escuela preparatoria oficial No. 42');
    titulo.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("C1"));

    final subtitulo = sheet.cell(CellIndex.indexByString("A2"));
    subtitulo.value = TextCellValue('Reporte de Asistencia');
    subtitulo.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByString("A2"), CellIndex.indexByString("C2"));

    final fechaReporte = sheet.cell(CellIndex.indexByString("A3"));
    fechaReporte.value = TextCellValue(DateTime.now().toIso8601String().split('T').first);
    fechaReporte.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByString("A3"), CellIndex.indexByString("C3"));

    sheet.appendRow([TextCellValue('')]);

    final headerRow = sheet.appendRow([
      TextCellValue('Nombre'),
      TextCellValue('Grupo'),
      TextCellValue('Presente')
    ]);

    // Agregar datos de asistencia
    groupedAttendance.forEach((groupName, students) {
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue(groupName)]);
      for (var student in students) {
        sheet.appendRow([
          TextCellValue(student['nombre']),
          TextCellValue(student['grupo_nombre']),
          TextCellValue(student['presente'].toString() == '1' ? '✅' : '❌')
        ]);
      }
    });

    final directory = await getApplicationDocumentsDirectory();
    final filePath = p.join(directory.path, 'reporte_asistencia.xlsx');
    final fileBytes = excel.encode();
    final file = File(filePath);
    await file.writeAsBytes(fileBytes!);

    final shell = Shell();

    if (Platform.isWindows) {
      await shell.run('start ${directory.path}');
    } else if (Platform.isMacOS) {
      await shell.run('open ${directory.path}');
    } else if (Platform.isLinux) {
      await shell.run('xdg-open ${directory.path}');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reporte descargado en $filePath')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now().toIso8601String().split('T').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          ...[
            const MinimalMenuBar(),
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: marginBottom12,
                child: Text("Asistencia del día", style: headlineTextStyle),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: marginBottom24,
                child: Text("Fecha: $hoy", style: subtitleTextStyle),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: ElevatedButton(
                onPressed: downloadAttendanceReport,
                child: Text('Descargar Reporte de Asistencia'),
              ),
            ),
            Container(margin: marginBottom12),
            Align(
              alignment: Alignment.center,
              child: ElevatedButton(
                onPressed: downloadAttendanceReport,
                child: Text('     Descargar Reporte General     '),
              ),
            ),
            divider,
            Container(margin: marginBottom40),
          ].toMaxWidthSliver(),
          SliverToBoxAdapter(
            child: MaxWidthBox(
              maxWidth: 1200,
              backgroundColor: Colors.white,
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : groupedAttendance.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No hay registros de asistencia para hoy.',
                              style: TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: groupedAttendance.entries.map((entry) {
                            final groupName = entry.key;
                            final students = entry.value;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24.0, horizontal: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(groupName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 12),
                                  ...students.map((student) => ListTile(
                                        leading: const Icon(Icons.check_circle,
                                            color: Colors.green),
                                        title: Text(student['nombre'] ?? ''),
                                        subtitle: Text(
                                            'Grupo: ${student['grupo_nombre']}'),
                                      )),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
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
