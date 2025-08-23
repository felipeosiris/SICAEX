import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:process_run/process_run.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:excel/excel.dart';
import 'package:permission_handler/permission_handler.dart';

class PreviewPage extends StatefulWidget {
  static const String name = 'preview';

  final String nameArgument;
  final String friendlyNameArgument;
  final String gradeArgument;
  final String groupArgument;

  const PreviewPage({
    super.key,
    required this.nameArgument,
    required this.friendlyNameArgument,
    required this.gradeArgument,
    required this.groupArgument,
  });

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  bool editando = false;
  late TextEditingController _nombreController;
  late String currentFriendlyName;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.nameArgument);
    currentFriendlyName = widget.friendlyNameArgument;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

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

    final db = await dbFactory.openDatabase(dbPath);

    // Ejecutar migración para agregar columna hora si no existe
    await _migrateDatabase(db);

    return db;
  }

  Future<void> _migrateDatabase(Database db) async {
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

  String removerAcentos(String texto) {
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
    };
    return texto.split('').map((c) => acentos[c] ?? c).join();
  }

  Future<void> actualizarNombre() async {
    final nuevoNombre = _nombreController.text.trim().toUpperCase();
    final nuevoFriendly = removerAcentos(nuevoNombre).toUpperCase();

    final db = await getDatabase();
    await db.update(
      'alumnos',
      {'nombre': nuevoNombre, 'friendlyName': nuevoFriendly},
      where: 'friendlyName = ?',
      whereArgs: [currentFriendlyName],
    );

    setState(() {
      editando = false;
      currentFriendlyName = nuevoFriendly;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nombre actualizado exitosamente')),
    );
  }

  Future<void> exportarHistorialAlumnoExcel(
      String nombreAlumno, BuildContext context) async {
    final db = await getDatabase();

    final alumnoResp = await db.query(
      'alumnos',
      columns: ['id'],
      where: 'nombre = ?',
      whereArgs: [nombreAlumno],
      limit: 1,
    );

    if (alumnoResp.isEmpty) return;

    final alumnoId = alumnoResp.first['id'] as int;

    final now = DateTime.now();
    final anioEscolar = now.month >= 8 ? now.year : now.year - 1;
    final fechaInicio = DateTime(anioEscolar, 8, 1);

    final todasLasFechas = <String>[];
    for (DateTime d = fechaInicio;
        !d.isAfter(now);
        d = d.add(const Duration(days: 1))) {
      todasLasFechas.add(d.toIso8601String().split('T').first);
    }

    final asistencias = await db.query(
      'asistencias',
      columns: ['fecha', 'presente'],
      where: 'alumno_id = ? AND fecha >= ?',
      whereArgs: [alumnoId, fechaInicio.toIso8601String()],
    );

    final fechasConAsistencia = {
      for (var a in asistencias)
        (a['fecha'] as String).split('T').first: a['presente'] == 1
    };

    final excel = Excel.createExcel();
    final sheet = excel['Asistencias'];

    excel.delete('Sheet1');

    // Encabezado principal
    final titulo =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titulo.value =
        TextCellValue('REPORTE DE ASISTENCIAS DEL ALUMNO $nombreAlumno');
    titulo.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.green,
      fontColorHex: ExcelColor.black,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0));

    // Encabezados
    final header =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
    header.value = TextCellValue('Fecha');
    header.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    final header2 =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1));
    header2.value = TextCellValue('Asistencia');
    header2.cellStyle = header.cellStyle;

    // Filas
    for (int i = 0; i < todasLasFechas.length; i++) {
      final fecha = todasLasFechas[i];
      final presente = fechasConAsistencia[fecha] == true;
      final rowIndex = i + 2;

      final fechaCell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
      fechaCell.value = TextCellValue(fecha);

      final asistenciaCell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex));
      asistenciaCell.value =
          TextCellValue(presente ? '✅ Presente' : '❌ Ausente');
      asistenciaCell.cellStyle = CellStyle(
        backgroundColorHex: presente ? ExcelColor.green : ExcelColor.red,
        fontColorHex: presente ? ExcelColor.green : ExcelColor.red,
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'asistencias_$nombreAlumno.xlsx');
    final fileBytes = excel.encode()!;
    final file = File(path);
    await file.writeAsBytes(fileBytes);

    final shell = Shell();

    if (Platform.isWindows) {
      await shell.run('start ${dir.path}');
    } else if (Platform.isMacOS) {
      await shell.run('open ${dir.path}');
    } else if (Platform.isLinux) {
      await shell.run('xdg-open ${dir.path}');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Excel generado en: $path')),
    );
  }

  Future<void> exportarHistorialAlumnoPorNombre(String nombreAlumno) async {
    final db = await getDatabase();

    final alumnoResp = await db.query(
      'alumnos',
      columns: ['id'],
      where: 'nombre = ?',
      whereArgs: [nombreAlumno],
      limit: 1,
    );

    if (alumnoResp.isEmpty) return;

    final alumnoId = alumnoResp.first['id'] as int;

    final now = DateTime.now();
    final anioEscolar = now.month >= 8 ? now.year : now.year - 1;
    final fechaInicio = DateTime(anioEscolar, 8, 1);

    final todasLasFechas = <String>[];
    for (DateTime d = fechaInicio;
        !d.isAfter(now);
        d = d.add(const Duration(days: 1))) {
      todasLasFechas.add(d.toIso8601String().split('T').first);
    }

    final asistencias = await db.query(
      'asistencias',
      columns: ['fecha', 'presente'],
      where: 'alumno_id = ? AND fecha >= ?',
      whereArgs: [alumnoId, fechaInicio.toIso8601String()],
    );

    final fechasConAsistencia = {
      for (var a in asistencias)
        (a['fecha'] as String).split('T').first: a['presente'] == 1
    };

    final rows = <List<String>>[
      ['Fecha', 'Presente']
    ];
    for (final fecha in todasLasFechas) {
      final presente = fechasConAsistencia.containsKey(fecha)
          ? (fechasConAsistencia[fecha]! ? '✅' : '❌')
          : '❌';
      rows.add([fecha, presente]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = utf8.encode('\uFEFF$csv');

    // Descarga CSV omitida para Flutter Web
    // Usa `printing` o agrega botón adicional si deseas descargarlo como archivo
  }

  Future<void> _generateAndDownloadPDF() async {
    final pdf = pw.Document();
    final qrImage = await QrPainter(
      data: currentFriendlyName,
      version: QrVersions.auto,
      gapless: true,
    ).toImage(200);
    final qrBytes = await qrImage.toByteData(format: ImageByteFormat.png);

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(currentFriendlyName, style: pw.TextStyle(fontSize: 20)),
              pw.SizedBox(height: 20),
              pw.Image(pw.MemoryImage(qrBytes!.buffer.asUint8List()),
                  width: 150, height: 150),
              pw.SizedBox(height: 20),
              pw.Text(widget.groupArgument, style: pw.TextStyle(fontSize: 16)),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${currentFriendlyName}_qr.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final double cardWidth = MediaQuery.of(context).size.width / 2;
    final double fontSize = MediaQuery.of(context).size.width < 600 ? 12 : 20;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _nombreController.text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cardWidth, maxHeight: 400),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrImageView(
                            data: currentFriendlyName,
                            version: QrVersions.auto,
                            size: 200.0,
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _generateAndDownloadPDF,
                            child: const Text('Descargar'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nombreController.text,
                              style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 10),
                            if (!editando)
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    editando = true;
                                  });
                                },
                                child: const Text('Editar'),
                              )
                            else ...[
                              TextField(
                                controller: _nombreController,
                                decoration: const InputDecoration(
                                    labelText: 'Nuevo nombre'),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: actualizarNombre,
                                    child: const Text('Guardar'),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        editando = false;
                                        _nombreController.text =
                                            widget.nameArgument;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey),
                                    child: const Text('Cancelar'),
                                  ),
                                ],
                              )
                            ],
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => exportarHistorialAlumnoExcel(
                                  _nombreController.text, context),
                              child: const Text('Descargar reporte global'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const FooterLocal(),
        ],
      ),
    );
  }
}

class FooterLocal extends StatelessWidget {
  const FooterLocal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: const Align(
        alignment: Alignment.centerRight,
        child: Text(
          "La generación de QR se realiza sin acentos para evitar errores de escaneo.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }
}
