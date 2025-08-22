import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:SICAE/components/components.dart';
import 'package:SICAE/utils/max_width_extension.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';

class AdministrationPage extends StatefulWidget {
  static const String name = 'administration';

  const AdministrationPage({super.key});

  @override
  State<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends State<AdministrationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> groups = [];
  bool isLoading = true;
  String selectedGroup = 'Todos';
  String searchQuery = '';

  // Controladores para el formulario
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _friendlyNameController = TextEditingController();
  String _selectedGroupId = '1';

  // Estadísticas
  Map<String, dynamic> statistics = {};

  // QR Template
  String selectedQrGroup = 'Todos';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchData();
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
      print('Base de datos copiada a: $dbPath');
    } else {
      print('Usando base existente en: $dbPath');
    }

    return dbFactory.openDatabase(dbPath);
  }

  Future<void> fetchData() async {
    final db = await getDatabase();

    // Obtener grupos
    final groupsResult =
        await db.query('grupos', orderBy: 'anio_escolar, semestre');

    // Obtener estudiantes con información de grupo
    final studentsResult = await db.rawQuery('''
      SELECT a.id, a.nombre, a.friendlyName, a.grupo_id, 
             g.anio_escolar, g.semestre, g.nombre AS grupo_nombre
      FROM alumnos a
      JOIN grupos g ON a.grupo_id = g.id
      ORDER BY a.nombre
    ''');

    // Obtener estadísticas
    final statsResult = await db.rawQuery('''
      SELECT 
        g.nombre AS grupo_nombre,
        g.anio_escolar,
        g.semestre,
        COUNT(a.id) AS total_alumnos,
        COUNT(CASE WHEN ast.presente = 0 THEN 1 END) AS total_faltas
      FROM grupos g
      LEFT JOIN alumnos a ON g.id = a.grupo_id
      LEFT JOIN asistencias ast ON a.id = ast.alumno_id
      GROUP BY g.id, g.nombre, g.anio_escolar, g.semestre
      ORDER BY g.anio_escolar, g.semestre
    ''');

    // Calcular estadísticas generales
    final totalStudents = studentsResult.length;
    final totalGroups = groupsResult.length;

    // Calcular total de faltas
    final totalFaltasResult = await db.rawQuery('''
      SELECT COUNT(*) AS total_faltas
      FROM asistencias
      WHERE presente = 0
    ''');

    final totalFaltas = totalFaltasResult.isNotEmpty
        ? (totalFaltasResult.first['total_faltas'] as int? ?? 0)
        : 0;

    setState(() {
      groups = groupsResult;
      students = studentsResult;
      statistics = {
        'totalStudents': totalStudents,
        'totalGroups': totalGroups,
        'totalFaltas': totalFaltas,
        'groupStats': statsResult,
      };
      isLoading = false;
    });
  }

  List<Map<String, dynamic>> get filteredStudents {
    return students.where((student) {
      final matchesSearch =
          student['nombre'].toLowerCase().contains(searchQuery.toLowerCase());
      final matchesGroup = selectedGroup == 'Todos' ||
          student['grupo_id'].toString() == selectedGroup;
      return matchesSearch && matchesGroup;
    }).toList();
  }

  List<Map<String, dynamic>> get qrTemplateStudents {
    return students.where((student) {
      final matchesGroup = selectedQrGroup == 'Todos' ||
          student['grupo_id'].toString() == selectedQrGroup;
      return matchesGroup;
    }).toList();
  }

  Future<void> generateQrPdf() async {
    final pdf = pw.Document();
    final qrStudents = qrTemplateStudents;

    if (qrStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay alumnos para generar QR')),
      );
      return;
    }

    // Crear páginas con QRs
    final studentsPerPage = 8; // 4x2 grid

    for (int i = 0; i < qrStudents.length; i += studentsPerPage) {
      final pageStudents = qrStudents.skip(i).take(studentsPerPage).toList();
      final qrWidgets = <pw.Widget>[];

      for (final student in pageStudents) {
        final qrData = student['friendlyName'] ?? student['nombre'];

        // Generar QR real usando QrPainter (misma lógica que en page_preview.dart)
        final qrImage = await QrPainter(
          data: qrData,
          version: QrVersions.auto,
          gapless: true,
        ).toImage(120);
        final qrBytes = await qrImage.toByteData(format: ImageByteFormat.png);

        final qrWidget = pw.Container(
          margin: const pw.EdgeInsets.all(10),
          padding: const pw.EdgeInsets.all(15),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            children: [
              // QR Code real
              pw.Image(
                pw.MemoryImage(qrBytes!.buffer.asUint8List()),
                width: 120,
                height: 120,
              ),
              pw.SizedBox(height: 10),
              // Nombre normal
              pw.Text(
                student['nombre'],
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        );
        qrWidgets.add(qrWidget);
      }

      // Crear grid 4x2
      final rows = <pw.Widget>[];
      for (int j = 0; j < qrWidgets.length; j += 2) {
        final rowWidgets = qrWidgets.skip(j).take(2).toList();
        if (rowWidgets.length == 1) {
          rowWidgets.add(pw.Container()); // Espacio vacío
        }
        rows.add(
          pw.Row(
            children: rowWidgets,
          ),
        );
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    'Plantilla de QR - ${selectedQrGroup == 'Todos' ? 'Todos los grupos' : groups.firstWhere((g) => g['id'].toString() == selectedQrGroup)['nombre']}',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 20),
                ...rows,
              ],
            );
          },
        ),
      );
    }

    // Generar PDF y guardar temporalmente
    final pdfBytes = await pdf.save();

    try {
      // Guardar en directorio temporal
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_template.pdf');
      await file.writeAsBytes(pdfBytes);

      // Intentar abrir con el visor de PDF del sistema
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('PDF abierto. Puedes imprimirlo o guardarlo desde ahí.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        // Si no se puede abrir, mostrar mensaje de éxito
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF generado exitosamente en: ${file.path}'),
              duration: Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Copiar ruta',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: file.path));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Ruta copiada al portapapeles')),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> addStudent() async {
    if (_nameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')),
        );
      }
      return;
    }

    final db = await getDatabase();

    try {
      await db.insert('alumnos', {
        'nombre': _nameController.text.trim(),
        'friendlyName': _friendlyNameController.text.trim().isEmpty
            ? _nameController.text.trim()
            : _friendlyNameController.text.trim(),
        'grupo_id': int.parse(_selectedGroupId),
      });

      // Limpiar formulario
      _nameController.clear();
      _friendlyNameController.clear();
      _selectedGroupId = '1';

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alumno agregado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al agregar alumno: $e')),
        );
      }
    }
  }

  Future<void> updateStudent(int studentId, String newName,
      String newFriendlyName, int newGroupId) async {
    if (newName.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')),
        );
      }
      return;
    }

    final db = await getDatabase();

    try {
      await db.update(
        'alumnos',
        {
          'nombre': newName.trim(),
          'friendlyName': newFriendlyName.trim().isEmpty
              ? newName.trim()
              : newFriendlyName.trim(),
          'grupo_id': newGroupId,
        },
        where: 'id = ?',
        whereArgs: [studentId],
      );

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alumno actualizado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar alumno: $e')),
        );
      }
    }
  }

  Future<void> deleteStudent(int studentId) async {
    final db = await getDatabase();

    try {
      // Primero eliminar asistencias relacionadas
      await db.delete(
        'asistencias',
        where: 'alumno_id = ?',
        whereArgs: [studentId],
      );

      // Luego eliminar el alumno
      await db.delete(
        'alumnos',
        where: 'id = ?',
        whereArgs: [studentId],
      );

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alumno eliminado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar alumno: $e')),
        );
      }
    }
  }

  void _showAddStudentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Nuevo Alumno'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _friendlyNameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre para QR (opcional)',
                  border: OutlineInputBorder(),
                  helperText:
                      'Si no se especifica, se usará el nombre completo',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGroupId,
                decoration: const InputDecoration(
                  labelText: 'Grupo',
                  border: OutlineInputBorder(),
                ),
                items: groups.map((group) {
                  return DropdownMenuItem(
                    value: group['id'].toString(),
                    child: Text(group['nombre']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGroupId = value!;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              addStudent();
              Navigator.pop(context);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _showEditStudentDialog(Map<String, dynamic> student) {
    final nameController = TextEditingController(text: student['nombre']);
    final friendlyNameController =
        TextEditingController(text: student['friendlyName'] ?? '');
    String selectedGroupId = student['grupo_id'].toString();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Alumno'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: friendlyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre para QR (opcional)',
                    border: OutlineInputBorder(),
                    helperText:
                        'Si no se especifica, se usará el nombre completo',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Grupo',
                    border: OutlineInputBorder(),
                  ),
                  items: groups.map((group) {
                    return DropdownMenuItem(
                      value: group['id'].toString(),
                      child: Text(group['nombre']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedGroupId = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                updateStudent(
                  student['id'],
                  nameController.text,
                  friendlyNameController.text,
                  int.parse(selectedGroupId),
                );
                Navigator.pop(context);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content:
            Text('¿Está seguro de que desea eliminar a ${student['nombre']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              deleteStudent(student['id']);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4.0,
                        spreadRadius: 2.0,
                      ),
                    ],
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
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
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
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
                      });
                    },
                    items: [
                      const DropdownMenuItem(
                          value: 'Todos', child: Text('Todos los grupos')),
                      ...groups.map((group) => DropdownMenuItem(
                            value: group['id'].toString(),
                            child: Text(group['nombre']),
                          )),
                    ],
                    icon: const Icon(Icons.arrow_drop_down),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _showAddStudentDialog,
                icon: const Icon(Icons.add),
                label: const Text('Agregar Alumno'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredStudents.isEmpty
                  ? const Center(
                      child: Text(
                        'No se encontraron alumnos para los filtros seleccionados.',
                        style: TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          // Encabezado de la tabla
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                    flex: 3,
                                    child: Text('Nombre',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    flex: 2,
                                    child: Text('Grupo',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    flex: 2,
                                    child: Text('Año',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    flex: 2,
                                    child: Text('Semestre',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    flex: 1,
                                    child: Text('Acciones',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Lista de estudiantes
                          Expanded(
                            child: ListView.builder(
                              itemCount: filteredStudents.length,
                              itemBuilder: (context, index) {
                                final student = filteredStudents[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8.0),
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8.0),
                                    border:
                                        Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              student['nombre'],
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w500),
                                            ),
                                            if (student['friendlyName'] !=
                                                    null &&
                                                student['friendlyName'] !=
                                                    student['nombre'])
                                              Text(
                                                'QR: ${student['friendlyName']}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                          flex: 2,
                                          child: Text(student['grupo_nombre'])),
                                      Expanded(
                                          flex: 2,
                                          child: Text(student['anio_escolar']
                                              .toString())),
                                      Expanded(
                                          flex: 2,
                                          child: Text(
                                              student['semestre'].toString())),
                                      Expanded(
                                        flex: 1,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit,
                                                  color: Colors.blue),
                                              onPressed: () =>
                                                  _showEditStudentDialog(
                                                      student),
                                              tooltip: 'Editar',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete,
                                                  color: Colors.red),
                                              onPressed: () =>
                                                  _showDeleteConfirmation(
                                                      student),
                                              tooltip: 'Eliminar',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildStatisticsTab() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjetas de estadísticas generales
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total de Alumnos',
                  '${statistics['totalStudents']}',
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Total de Grupos',
                  '${statistics['totalGroups']}',
                  Icons.group_work,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Total de Faltas',
                  '${statistics['totalFaltas'] ?? 0}',
                  Icons.cancel,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Estadísticas por grupo
          Text(
            'Estadísticas por Grupo',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          // Tabla de estadísticas por grupo
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                // Encabezado de la tabla
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8.0),
                      topRight: Radius.circular(8.0),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text('Grupo',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 1,
                          child: Text('Alumnos',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 1,
                          child: Text('Faltas',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                // Filas de datos
                ...(statistics['groupStats'] as List<dynamic>).map((groupStat) {
                  final totalFaltas = groupStat['total_faltas'] as int? ?? 0;

                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            groupStat['grupo_nombre'] ?? 'Sin nombre',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text('${groupStat['total_alumnos'] ?? 0}'),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '$totalFaltas',
                            style: TextStyle(
                              color:
                                  totalFaltas > 0 ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Información adicional
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Información General',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                    '• Total de faltas en el sistema: ${statistics['totalFaltas'] ?? 0}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrTemplateTab() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Controles superiores
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
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4.0,
                        spreadRadius: 2.0,
                      ),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedQrGroup,
                      onChanged: (value) {
                        setState(() {
                          selectedQrGroup = value!;
                        });
                      },
                      items: [
                        const DropdownMenuItem(
                            value: 'Todos', child: Text('Todos los grupos')),
                        ...groups.map((group) => DropdownMenuItem(
                              value: group['id'].toString(),
                              child: Text(group['nombre']),
                            )),
                      ],
                      icon: const Icon(Icons.arrow_drop_down),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: generateQrPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Generar PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Información del grupo seleccionado
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Mostrando ${qrTemplateStudents.length} alumnos${selectedQrGroup != 'Todos' ? ' del grupo seleccionado' : ''}',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Vista previa de QRs
          Expanded(
            child: qrTemplateStudents.isEmpty
                ? const Center(
                    child: Text(
                      'No hay alumnos para mostrar en la plantilla de QR.',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: qrTemplateStudents.length,
                    itemBuilder: (context, index) {
                      final student = qrTemplateStudents[index];
                      final qrData =
                          student['friendlyName'] ?? student['nombre'];

                      return Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(color: Colors.grey[300]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4.0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // QR Code
                            Expanded(
                              child: QrImageView(
                                data: qrData,
                                version: QrVersions.auto,
                                size: 120,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Nombre normal
                            Text(
                              student['nombre'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // Nombre para QR
                            Text(
                              'QR: $qrData',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: color,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
                child: Text("Administración", style: headlineTextStyle),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: marginBottom24,
                child:
                    Text("Gestión del sistema SICAE", style: subtitleTextStyle),
              ),
            ),
            Container(margin: marginBottom40),
          ].toMaxWidthSliver(),
          SliverToBoxAdapter(
            child: MaxWidthBox(
              maxWidth: 1200,
              backgroundColor: Colors.white,
              child: Column(
                children: [
                  // Pestañas
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: Colors.blue[700],
                      unselectedLabelColor: Colors.grey[600],
                      indicatorColor: Colors.blue[700],
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.people),
                          text: 'Gestión de Alumnos',
                        ),
                        Tab(
                          icon: Icon(Icons.analytics),
                          text: 'Estadísticas',
                        ),
                        Tab(
                          icon: Icon(Icons.qr_code),
                          text: 'Plantilla de QR',
                        ),
                      ],
                    ),
                  ),
                  // Contenido de las pestañas
                  SizedBox(
                    height: 600, // Altura fija para el contenido
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStudentsTab(),
                        _buildStatisticsTab(),
                        _buildQrTemplateTab(),
                      ],
                    ),
                  ),
                ],
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

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _friendlyNameController.dispose();
    super.dispose();
  }
}
