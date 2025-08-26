import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:SICAE/components/components.dart';
import 'package:SICAE/pages/page_preview.dart';
import 'package:SICAE/utils/max_width_extension.dart';
import 'package:path_provider/path_provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

class StudentsPage extends StatefulWidget {
  static const String name = 'students';

  const StudentsPage({super.key});

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  Map<String, List<Map<String, dynamic>>> groupedStudents = {};
  Map<String, List<Map<String, dynamic>>> filteredStudents = {};
  String selectedGrade = 'Todos';
  String selectedSemester = 'Todos';
  String selectedGroup = 'Todos';
  String searchQuery = '';
  bool isLoading = true;
  List<Map<String, dynamic>> groups = [];

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
      print('Base de datos copiada a: $dbPath');
    } else {
      print('Usando base existente en: $dbPath');
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
    fetchStudents();
  }

  Future<void> fetchStudents() async {
    final db = await getDatabase();

    // Obtener grupos
    final groupsResult = await db.query('grupos',
        orderBy: 'anio_escolar, semestre, grupo_letra');

    // Obtener estudiantes con información de grupo
    final result = await db.rawQuery('''
      SELECT a.id, a.nombre, a.friendlyName, a.grupo_id, g.anio_escolar, g.semestre, g.grupo_letra, g.nombre AS grupo_nombre
      FROM alumnos a
      JOIN grupos g ON a.grupo_id = g.id
      ORDER BY g.anio_escolar, g.semestre, g.grupo_letra, a.nombre
    ''');

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var student in result) {
      final groupName = student['grupo_nombre']?.toString() ?? 'Sin grupo';
      grouped.putIfAbsent(groupName, () => []).add(student);
    }

    grouped.forEach((key, value) {
      value.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    });

    setState(() {
      groups = groupsResult;
      groupedStudents = grouped;
      filteredStudents = grouped;
      isLoading = false;
    });
  }

  void applyFilters() {
    final Map<String, List<Map<String, dynamic>>> filtered = {};
    groupedStudents.forEach((groupName, students) {
      final filteredList = students.where((student) {
        final grado = student['anio_escolar'];
        final semestre = student['semestre'];
        final grupoId = student['grupo_id'];

        final matchesGrade =
            selectedGrade == 'Todos' || grado.toString() == selectedGrade;
        final matchesSemester = selectedSemester == 'Todos' ||
            semestre.toString() == selectedSemester;
        final matchesGroup =
            selectedGroup == 'Todos' || grupoId.toString() == selectedGroup;
        final matchesSearch =
            student['nombre'].toLowerCase().contains(searchQuery.toLowerCase());

        return matchesGrade && matchesSemester && matchesGroup && matchesSearch;
      }).toList();

      if (filteredList.isNotEmpty) {
        filtered[groupName] = filteredList;
      }
    });

    setState(() {
      filteredStudents = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text("Alumnos", style: headlineTextStyle),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: marginBottom24,
                child: Text("Lista de alumnos registrados.",
                    style: subtitleTextStyle),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Filtro por año
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.25,
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4.0,
                                spreadRadius: 2.0,
                              ),
                            ],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedGrade,
                              onChanged: (value) {
                                setState(() {
                                  selectedGrade = value!;
                                  applyFilters();
                                });
                              },
                              items: [
                                const DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos los años'),
                                ),
                                ...groups
                                    .map((group) => DropdownMenuItem(
                                          value:
                                              group['anio_escolar'].toString(),
                                          child: Text(
                                              '${group['anio_escolar']}° Año'),
                                        ))
                                    .toSet()
                                    .toList(),
                              ],
                              icon: const Icon(Icons.arrow_drop_down),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Filtro por semestre
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.25,
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4.0,
                                spreadRadius: 2.0,
                              ),
                            ],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedSemester,
                              onChanged: (value) {
                                setState(() {
                                  selectedSemester = value!;
                                  applyFilters();
                                });
                              },
                              items: [
                                const DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos los semestres'),
                                ),
                                ...groups
                                    .map((group) => DropdownMenuItem(
                                          value: group['semestre'].toString(),
                                          child: Text(
                                              '${group['semestre']}° Semestre'),
                                        ))
                                    .toSet()
                                    .toList(),
                              ],
                              icon: const Icon(Icons.arrow_drop_down),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Filtro por grupo específico
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.25,
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4.0,
                                spreadRadius: 2.0,
                              ),
                            ],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedGroup,
                              onChanged: (value) {
                                setState(() {
                                  selectedGroup = value!;
                                  applyFilters();
                                });
                              },
                              items: [
                                const DropdownMenuItem(
                                  value: 'Todos',
                                  child: Text('Todos los grupos'),
                                ),
                                ...groups.map((group) => DropdownMenuItem(
                                      value: group['id'].toString(),
                                      child: Text(group['nombre'] ??
                                          '${group['anio_escolar']}° Año - ${group['semestre']}° Semestre'),
                                    )),
                              ],
                              icon: const Icon(Icons.arrow_drop_down),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4.0,
                                spreadRadius: 2.0,
                              ),
                            ],
                          ),
                          child: TextField(
                            onChanged: (value) {
                              setState(() {
                                searchQuery = value;
                                applyFilters();
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'Buscar por nombre...',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
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
                  : filteredStudents.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No se encontraron alumnos para los filtros seleccionados.',
                              style: TextStyle(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: filteredStudents.entries.map((entry) {
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
                                        title: Text(student['nombre'] ?? ''),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon:
                                                  const Icon(Icons.visibility),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        PreviewPage(
                                                      nameArgument:
                                                          student['nombre'],
                                                      friendlyNameArgument:
                                                          student[
                                                              'friendlyName'],
                                                      gradeArgument: student[
                                                              'anio_escolar']
                                                          .toString(),
                                                      groupArgument: student[
                                                          'grupo_nombre'],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
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
