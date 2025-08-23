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

  // Variables para el dropdown de filtro
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  // Función para obtener el nombre del mes
  String _getMesNombre(int mes) {
    final meses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return meses[mes - 1];
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

  @override
  void initState() {
    super.initState();
    fetchAttendance();
  }

  Future<void> fetchAttendance() async {
    final db = await getDatabase();
    final today = DateTime.now().toIso8601String().split('T').first;

    final result = await db.rawQuery('''
      SELECT a.nombre, a.friendlyName, g.anio_escolar AS anio, g.semestre, g.nombre AS grupo_nombre, asi.presente, asi.hora
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
    final db = await getDatabase();
    final excel = Excel.createExcel();
    final sheet = excel['Asistencia'];

    // Obtener fecha y hora actual para el nombre del archivo
    final now = DateTime.now();
    final fechaHora =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';

    // Establecer estilos de celda
    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    // Función para obtener el día de la semana
    String getDiaSemana(String fecha) {
      final date = DateTime.parse(fecha);
      final dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      return dias[date.weekday - 1];
    }

    // Función para calcular tiempo de tardanza
    String calcularTiempoTardanza(String? horaRegistrada) {
      if (horaRegistrada == null) return 'NA';

      try {
        final partes = horaRegistrada.split(':');
        final hora = int.parse(partes[0]);
        final minuto = int.parse(partes[1]);

        // Hora de entrada: 8:00 AM
        final horaEntrada = 8;
        final minutoEntrada = 0;

        // Calcular diferencia en minutos
        final minutosRegistrados = hora * 60 + minuto;
        final minutosEntrada = horaEntrada * 60 + minutoEntrada;

        if (minutosRegistrados <= minutosEntrada) {
          return 'En tiempo';
        } else {
          final tardanza = minutosRegistrados - minutosEntrada;
          final horasTardanza = tardanza ~/ 60;
          final minutosTardanza = tardanza % 60;

          if (horasTardanza > 0) {
            return '${horasTardanza}h ${minutosTardanza}m tarde';
          } else {
            return '${minutosTardanza}m tarde';
          }
        }
      } catch (e) {
        return 'NA';
      }
    }

    // Función para determinar resultado
    String determinarResultado(String? horaRegistrada) {
      if (horaRegistrada == null) return 'Falta';

      try {
        final partes = horaRegistrada.split(':');
        final hora = int.parse(partes[0]);
        final minuto = int.parse(partes[1]);

        // Hora de entrada: 8:00 AM
        final horaEntrada = 8;
        final minutoEntrada = 0;

        // Calcular diferencia en minutos
        final minutosRegistrados = hora * 60 + minuto;
        final minutosEntrada = horaEntrada * 60 + minutoEntrada;

        if (minutosRegistrados <= minutosEntrada) {
          return 'En tiempo';
        } else {
          return 'Tardanza';
        }
      } catch (e) {
        return 'Falta';
      }
    }

    // Obtener todos los alumnos con asistencia del día actual
    final today = DateTime.now().toIso8601String().split('T').first;
    final alumnosResult = await db.rawQuery('''
      SELECT a.id, a.nombre, g.nombre AS grupo_nombre, g.anio_escolar AS anio, g.semestre,
             asi.hora, asi.presente
      FROM alumnos a
      JOIN grupos g ON a.grupo_id = g.id
      LEFT JOIN asistencias asi ON a.id = asi.alumno_id AND asi.fecha = ?
      ORDER BY a.nombre ASC
    ''', [today]);

    // Verificar si hay datos de asistencia para el día actual
    if (alumnosResult.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('No hay datos de asistencia para generar el reporte')),
      );
      return;
    }

    // Agregar encabezados y fusionar celdas
    final titulo = sheet.cell(CellIndex.indexByString("A1"));
    titulo.value = TextCellValue('Escuela preparatoria oficial No. 26');
    titulo.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByString("A1"),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0));

    final subtitulo = sheet.cell(CellIndex.indexByString("A2"));
    subtitulo.value = TextCellValue('Reporte de Asistencia del Día');
    subtitulo.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByString("A2"),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1));

    final fechaReporte = sheet.cell(CellIndex.indexByString("A3"));
    fechaReporte.value = TextCellValue(
        'Generado el: ${DateTime.now().toIso8601String().split('T').first}');
    fechaReporte.cellStyle = headerStyle;
    sheet.merge(CellIndex.indexByString("A3"),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 2));

    // Agregar nota sobre filtros y fines de semana
    final notaFiltros = sheet.cell(CellIndex.indexByString("A4"));
    notaFiltros.value = TextCellValue(
        'Nota: Use los filtros en la fila 5 para filtrar por mes (MM/YYYY). Celdas vacías = fines de semana');
    notaFiltros.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.yellow,
      fontColorHex: ExcelColor.black,
      italic: true,
    );
    sheet.merge(
        CellIndex.indexByString("A4"),
        CellIndex.indexByColumnRow(
            columnIndex: 6, rowIndex: 3)); // 7 columnas totales

    sheet.appendRow([TextCellValue('')]);

    // Encabezados de columnas: Nombre, Grupo, Hora Entrada, Hora Registrada, Resultado, Día, Tiempo
    final headerRow = [
      TextCellValue('Nombre'),
      TextCellValue('Grupo'),
      TextCellValue('Hora Entrada'),
      TextCellValue('Hora Registrada'),
      TextCellValue('Resultado'),
      TextCellValue('Día'),
      TextCellValue('Tiempo')
    ];
    sheet.appendRow(headerRow);

    // Aplicar colores específicos a cada encabezado
    // Nombre (azul)
    final headerNombre =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5));
    headerNombre.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Grupo (azul)
    final headerGrupo =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 5));
    headerGrupo.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Hora Entrada (azul)
    final headerHoraEntrada =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 5));
    headerHoraEntrada.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Hora Registrada (amarillo)
    final headerHoraRegistrada =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 5));
    headerHoraRegistrada.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.yellow,
      fontColorHex: ExcelColor.black,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Resultado (verde/rojo según el caso)
    final headerResultado =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 5));
    headerResultado.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.green,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Día (azul)
    final headerDia =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 5));
    headerDia.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Tiempo (naranja)
    final headerTiempo =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 5));
    headerTiempo.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.orange,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Agregar fila de filtros (fila 6)
    final filterRow = [
      TextCellValue(''), // Filtro para Nombre
      TextCellValue(''), // Filtro para Grupo
      TextCellValue(''), // Filtro para Hora Entrada
      TextCellValue(''), // Filtro para Hora Registrada
      TextCellValue(''), // Filtro para Resultado
      TextCellValue(''), // Filtro para Día
      TextCellValue('') // Filtro para Tiempo
    ];
    sheet.appendRow(filterRow);

    // Aplicar estilo a la fila de filtros
    for (int i = 0; i < headerRow.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 6));
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.lightBlue,
        fontColorHex: ExcelColor.black,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Agregar datos de cada alumno
    for (var alumno in alumnosResult) {
      final nombre = alumno['nombre'] as String;
      final grupo =
          '${alumno['grupo_nombre']} (Año ${alumno['anio']} - Semestre ${alumno['semestre']})';
      final horaRegistrada = alumno['hora'] as String?;
      final presente = alumno['presente'] as int?;

      // Obtener día de la semana
      final diaSemana = getDiaSemana(today);

      // Calcular datos
      final horaEntrada = '08:00';
      final resultado =
          presente == 1 ? determinarResultado(horaRegistrada) : 'Falta';
      final tiempo =
          presente == 1 ? calcularTiempoTardanza(horaRegistrada) : 'NA';

      // Crear fila
      final row = [
        TextCellValue(nombre),
        TextCellValue(grupo),
        TextCellValue(horaEntrada),
        TextCellValue(horaRegistrada ?? 'NA'),
        TextCellValue(resultado),
        TextCellValue(diaSemana),
        TextCellValue(tiempo)
      ];

      sheet.appendRow(row);

      // Aplicar colores a las celdas
      final rowIndex = sheet.maxRows - 1;

      // Hora Entrada (azul)
      final cellHoraEntrada = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex));
      cellHoraEntrada.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.blue,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Hora Registrada (amarillo)
      final cellHoraRegistrada = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex));
      cellHoraRegistrada.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.yellow,
        fontColorHex: ExcelColor.black,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Resultado (verde si en tiempo, rojo si tardanza)
      final cellResultado = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex));
      cellResultado.cellStyle = CellStyle(
        backgroundColorHex:
            resultado == 'En tiempo' ? ExcelColor.green : ExcelColor.red,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Día (azul)
      final cellDia = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex));
      cellDia.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.blue,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Tiempo (naranja)
      final cellTiempo = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex));
      cellTiempo.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.orange,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath =
        p.join(directory.path, 'reporte_asistencia_$fechaHora.xlsx');
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
      SnackBar(
          content:
              Text('Reporte de asistencia del día descargado en $filePath')),
    );
  }

  Future<void> downloadGeneralReport({int? year, int? month}) async {
    final targetYear = year ?? selectedYear;
    final targetMonth = month ?? selectedMonth;
    final db = await getDatabase();
    final excel = Excel.createExcel();
    final sheet = excel['Reporte General'];

    // Establecer estilos de celda
    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    // Función para obtener el día de la semana
    String getDiaSemana(String fecha) {
      final date = DateTime.parse(fecha);
      final dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      return dias[date.weekday - 1];
    }

    // Función para formatear fecha con día de la semana
    String formatearFecha(String fecha) {
      final date = DateTime.parse(fecha);
      final diaSemana = getDiaSemana(fecha);
      return '${date.day}/${date.month} ($diaSemana)';
    }

    // Obtener todas las fechas del mes seleccionado
    final primerDia = DateTime(targetYear, targetMonth, 1);
    final ultimoDia = DateTime(targetYear, targetMonth + 1, 0);
    final fechas = <String>[];

    for (DateTime fecha = primerDia;
        fecha.isBefore(ultimoDia.add(const Duration(days: 1)));
        fecha = fecha.add(const Duration(days: 1))) {
      fechas.add(fecha.toIso8601String().split('T').first);
    }

    // Obtener todos los alumnos
    final alumnosResult = await db.rawQuery('''
      SELECT a.id, a.nombre, g.nombre AS grupo_nombre, g.anio_escolar AS anio, g.semestre
      FROM alumnos a
      JOIN grupos g ON a.grupo_id = g.id
      ORDER BY a.nombre ASC
    ''');

    // Obtener todas las asistencias del mes
    final asistenciasResult = await db.rawQuery('''
      SELECT alumno_id, fecha, presente
      FROM asistencias
      WHERE strftime('%Y', fecha) = ? AND strftime('%m', fecha) = ?
    ''', [targetYear.toString(), targetMonth.toString().padLeft(2, '0')]);

    // Crear mapa de asistencias para búsqueda rápida
    final asistenciasMap = <String, int>{};
    for (var asistencia in asistenciasResult) {
      final key = '${asistencia['alumno_id']}_${asistencia['fecha']}';
      asistenciasMap[key] = asistencia['presente'] as int;
    }

    // Agregar encabezados y fusionar celdas
    final titulo = sheet.cell(CellIndex.indexByString("A1"));
    titulo.value = TextCellValue('Escuela preparatoria oficial No. 26');
    titulo.cellStyle = headerStyle;
    sheet.merge(
        CellIndex.indexByString("A1"),
        CellIndex.indexByColumnRow(
            columnIndex: fechas.length + 4, rowIndex: 0));

    final subtitulo = sheet.cell(CellIndex.indexByString("A2"));
    subtitulo.value = TextCellValue('Reporte General de Asistencia');
    subtitulo.cellStyle = headerStyle;
    sheet.merge(
        CellIndex.indexByString("A2"),
        CellIndex.indexByColumnRow(
            columnIndex: fechas.length + 4, rowIndex: 1));

    final fechaReporte = sheet.cell(CellIndex.indexByString("A3"));
    fechaReporte.value = TextCellValue(
        'Generado el: ${DateTime.now().toIso8601String().split('T').first}');
    fechaReporte.cellStyle = headerStyle;
    sheet.merge(
        CellIndex.indexByString("A3"),
        CellIndex.indexByColumnRow(
            columnIndex: fechas.length + 4, rowIndex: 2));

    // Agregar nota sobre filtros y fines de semana
    final notaFiltros = sheet.cell(CellIndex.indexByString("A4"));
    notaFiltros.value = TextCellValue(
        'Nota: Use los filtros en la fila 5 para filtrar por mes (MM/YYYY). Celdas vacías = fines de semana');
    notaFiltros.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.yellow,
      fontColorHex: ExcelColor.black,
      italic: true,
    );
    sheet.merge(
        CellIndex.indexByString("A4"),
        CellIndex.indexByColumnRow(
            columnIndex: fechas.length + 4, rowIndex: 3));

    sheet.appendRow([TextCellValue('')]);

    // Encabezados de columnas: Nombre, Grupo, todas las fechas, y estadísticas
    final headerRow = [TextCellValue('Nombre'), TextCellValue('Grupo')];
    for (String fecha in fechas) {
      headerRow.add(TextCellValue(formatearFecha(fecha)));
    }
    headerRow.add(TextCellValue('Asistencias'));
    headerRow.add(TextCellValue('Faltas'));
    headerRow.add(TextCellValue('Porcentaje'));
    sheet.appendRow(headerRow);

    // Aplicar estilo a los encabezados
    for (int i = 0; i < headerRow.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
      cell.cellStyle = headerStyle;
    }

    // Agregar fila de filtros (fila 6)
    final filterRow = [TextCellValue(''), TextCellValue('')]; // Nombre y Grupo
    for (String fecha in fechas) {
      final date = DateTime.parse(fecha);
      final mes = '${date.month}/${date.year}';
      filterRow.add(TextCellValue(mes));
    }
    filterRow.add(TextCellValue('')); // Asistencias
    filterRow.add(TextCellValue('')); // Faltas
    filterRow.add(TextCellValue('')); // Porcentaje
    sheet.appendRow(filterRow);

    // Aplicar estilo a la fila de filtros
    for (int i = 0; i < filterRow.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 6));
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.lightBlue,
        fontColorHex: ExcelColor.black,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Aplicar colores a las columnas de estadísticas
    final asistenciasHeader = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: fechas.length + 2, rowIndex: 5));
    asistenciasHeader.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.green,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    final faltasHeader = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: fechas.length + 3, rowIndex: 5));
    faltasHeader.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.orange,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    final porcentajeHeader = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: fechas.length + 4, rowIndex: 5));
    porcentajeHeader.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.blue,
      fontColorHex: ExcelColor.white,
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Agregar datos de cada alumno
    for (var alumno in alumnosResult) {
      final nombre = alumno['nombre'] as String;
      final grupo =
          '${alumno['grupo_nombre']} (Año ${alumno['anio']} - Semestre ${alumno['semestre']})';
      final alumnoId = alumno['id'] as int;

      // Crear fila con nombre y grupo
      final row = [
        TextCellValue(nombre),
        TextCellValue(grupo),
      ];

      int asistencias = 0;
      int totalDias = 0;

      // Agregar datos de asistencia para cada fecha
      for (String fecha in fechas) {
        final date = DateTime.parse(fecha);
        final esFinDeSemana = date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday;

        if (esFinDeSemana) {
          row.add(TextCellValue('')); // Celda vacía para fines de semana
        } else {
          totalDias++;
          final key = '${alumnoId}_$fecha';
          final presente = asistenciasMap[key];

          if (presente == 1) {
            row.add(TextCellValue('✅'));
            asistencias++;
          } else {
            row.add(TextCellValue('❌'));
          }
        }
      }

      // Calcular estadísticas
      final faltas = totalDias - asistencias;
      final porcentaje = totalDias > 0
          ? ((asistencias / totalDias) * 100).toStringAsFixed(1)
          : '0.0';

      // Agregar columnas de estadísticas
      row.add(TextCellValue('$asistencias/$totalDias'));
      row.add(TextCellValue(faltas.toString()));
      row.add(TextCellValue('$porcentaje%'));

      sheet.appendRow(row);

      // Aplicar colores a las celdas de estadísticas
      final rowIndex = sheet.maxRows - 1;

      final asistenciasCell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: fechas.length + 2, rowIndex: rowIndex));
      asistenciasCell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.green,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      final faltasCell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: fechas.length + 3, rowIndex: rowIndex));
      faltasCell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.orange,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      final porcentajeCell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: fechas.length + 4, rowIndex: rowIndex));
      porcentajeCell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.blue,
        fontColorHex: ExcelColor.white,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final mesNombre = _getMesNombre(targetMonth);
    final filePath = p.join(
        directory.path, 'reporte_asistencia_${mesNombre}_$targetYear.xlsx');
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
      SnackBar(
          content: Text(
              'Reporte de ${_getMesNombre(targetMonth)} $targetYear descargado en $filePath')),
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
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dropdown para mes
                      Container(
                        margin: const EdgeInsets.only(right: 16),
                        child: DropdownButton<int>(
                          value: selectedMonth,
                          hint: const Text('Mes'),
                          items: List.generate(12, (index) {
                            final mes = index + 1;
                            return DropdownMenuItem<int>(
                              value: mes,
                              child: Text(_getMesNombre(mes)),
                            );
                          }),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                selectedMonth = newValue;
                              });
                            }
                          },
                        ),
                      ),
                      // Dropdown para año
                      Container(
                        margin: const EdgeInsets.only(right: 16),
                        child: DropdownButton<int>(
                          value: selectedYear,
                          hint: const Text('Año'),
                          items: List.generate(5, (index) {
                            final year = DateTime.now().year - 2 + index;
                            return DropdownMenuItem<int>(
                              value: year,
                              child: Text(year.toString()),
                            );
                          }),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                selectedYear = newValue;
                              });
                            }
                          },
                        ),
                      ),
                      // Botón de descarga
                      ElevatedButton(
                        onPressed: () => downloadGeneralReport(),
                        child: Text(
                            'Descargar Reporte de ${_getMesNombre(selectedMonth)} $selectedYear'),
                      ),
                    ],
                  ),
                ],
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
