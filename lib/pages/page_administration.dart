import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:SICAE/components/components.dart';
import 'package:SICAE/utils/max_width_extension.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:SICAE/utils/database_utils.dart';
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

  // Controladores para el módulo de perfiles
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nombreCompletoController =
      TextEditingController();
  String _selectedRol = 'usuario';
  List<Map<String, dynamic>> usuarios = [];

  // Controladores para el módulo de grupos
  final TextEditingController _grupoAnioController = TextEditingController();
  final TextEditingController _grupoSemestreController =
      TextEditingController();
  final TextEditingController _grupoLetraController = TextEditingController();
  final TextEditingController _grupoNombreController = TextEditingController();
  int? _editingGrupoId;

  // Estadísticas
  Map<String, dynamic> statistics = {};

  // QR Template
  String selectedQrGroup = 'Todos';

  // Variables para carga masiva
  String? selectedBulkUploadGroup;
  List<String> bulkUploadNames = [];
  bool isBulkUploadLoading = false;
  final TextEditingController _bulkUploadTextController =
      TextEditingController();

  // Variables para mantenimiento
  String? selectedMaintenanceGroup;
  String? selectedMaintenanceStudent;
  bool isMaintenanceLoading = false;
  bool isBackupLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    fetchData();
  }

  Future<Database> getDatabase() async {
    return await DatabaseUtils.getDatabase();
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

    // Obtener estadísticas por grupo (consultas separadas para evitar multiplicación)
    final statsResult = await db.rawQuery('''
      SELECT 
        g.id,
        g.nombre AS grupo_nombre,
        g.anio_escolar,
        g.semestre,
        COALESCE(alumnos_count.count, 0) AS total_alumnos
      FROM grupos g
      LEFT JOIN (
        SELECT grupo_id, COUNT(*) as count
        FROM alumnos
        GROUP BY grupo_id
      ) alumnos_count ON g.id = alumnos_count.grupo_id
      ORDER BY g.anio_escolar, g.semestre
    ''');

    // Obtener faltas por grupo en consulta separada
    final faltasResult = await db.rawQuery('''
      SELECT 
        a.grupo_id,
        COUNT(*) as total_faltas
      FROM asistencias ast
      JOIN alumnos a ON ast.alumno_id = a.id
      WHERE ast.presente = 0
      GROUP BY a.grupo_id
    ''');

    // Combinar los resultados
    final Map<int, int> faltasPorGrupo = {};
    for (var falta in faltasResult) {
      faltasPorGrupo[falta['grupo_id'] as int] = falta['total_faltas'] as int;
    }

    // Agregar faltas a las estadísticas (convertir QueryRow a Map para poder modificarlo)
    final List<Map<String, dynamic>> statsResultWithFaltas = [];
    for (var stat in statsResult) {
      final Map<String, dynamic> statMap = Map<String, dynamic>.from(stat);
      final grupoId = statMap['id'] as int;
      statMap['total_faltas'] = faltasPorGrupo[grupoId] ?? 0;
      statsResultWithFaltas.add(statMap);
    }

    // Calcular estadísticas generales
    final totalStudents = studentsResult.length;
    final totalGroups = groupsResult.length;

    // Validar consistencia de estadísticas
    int totalAlumnosEnGrupos = 0;
    for (var stat in statsResultWithFaltas) {
      totalAlumnosEnGrupos += stat['total_alumnos'] as int;
    }

    // Si hay discrepancia, usar el total real de alumnos
    if (totalAlumnosEnGrupos != totalStudents) {
      print(
          '⚠️ Discrepancia en estadísticas: Total alumnos = $totalStudents, Suma por grupos = $totalAlumnosEnGrupos');
    }

    // Calcular total de faltas
    final totalFaltasResult = await db.rawQuery('''
      SELECT COUNT(*) AS total_faltas
      FROM asistencias
      WHERE presente = 0
    ''');

    final totalFaltas = totalFaltasResult.isNotEmpty
        ? (totalFaltasResult.first['total_faltas'] as int? ?? 0)
        : 0;

    // Obtener usuarios
    final usuariosResult = await db.query('usuarios', orderBy: 'username');

    setState(() {
      groups = groupsResult;
      students = studentsResult;
      usuarios = usuariosResult;
      statistics = {
        'totalStudents': totalStudents,
        'totalGroups': totalGroups,
        'totalFaltas': totalFaltas,
        'groupStats': statsResultWithFaltas,
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

  // Funciones para gestión de grupos
  void _showAddGroupDialog() {
    _grupoAnioController.clear();
    _grupoSemestreController.clear();
    _grupoLetraController.clear();
    _grupoNombreController.clear();
    _editingGrupoId = null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Nuevo Grupo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _grupoAnioController,
                decoration: const InputDecoration(
                  labelText: 'Año escolar *',
                  border: OutlineInputBorder(),
                  helperText: 'Ejemplo: 1, 2, 3',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _grupoSemestreController,
                decoration: const InputDecoration(
                  labelText: 'Semestre *',
                  border: OutlineInputBorder(),
                  helperText: 'Ejemplo: 1, 2, 3, 4, 5, 6',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _grupoLetraController,
                decoration: const InputDecoration(
                  labelText: 'Grupo *',
                  border: OutlineInputBorder(),
                  helperText: 'Ejemplo: A, B, C, 1, 2, 3',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _grupoNombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del grupo (opcional)',
                  border: OutlineInputBorder(),
                  helperText:
                      'Si no se especifica, se generará automáticamente',
                ),
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
              addGroup();
              Navigator.pop(context);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _editGroup(Map<String, dynamic> group) {
    _grupoAnioController.text = group['anio_escolar'].toString();
    _grupoSemestreController.text = group['semestre'].toString();
    _grupoLetraController.text = group['grupo_letra'] ?? '';
    _grupoNombreController.text = group['nombre'] ?? '';
    _editingGrupoId = group['id'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Grupo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _grupoAnioController,
                decoration: const InputDecoration(
                  labelText: 'Año escolar *',
                  border: OutlineInputBorder(),
                  helperText: 'Ejemplo: 1, 2, 3',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _grupoSemestreController,
                decoration: const InputDecoration(
                  labelText: 'Semestre *',
                  border: OutlineInputBorder(),
                  helperText: 'Ejemplo: 1, 2, 3, 4, 5, 6',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _grupoLetraController,
                decoration: const InputDecoration(
                  labelText: 'Grupo *',
                  border: OutlineInputBorder(),
                  helperText: 'Ejemplo: A, B, C, 1, 2, 3',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _grupoNombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del grupo (opcional)',
                  border: OutlineInputBorder(),
                  helperText:
                      'Si no se especifica, se generará automáticamente',
                ),
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
              updateGroup();
              Navigator.pop(context);
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  void _viewGroupStudents(Map<String, dynamic> group) async {
    final db = await getDatabase();

    // Obtener alumnos del grupo
    final studentsResult = await db.rawQuery('''
      SELECT a.id, a.nombre, a.friendlyName
      FROM alumnos a
      WHERE a.grupo_id = ?
      ORDER BY a.nombre
    ''', [group['id']]);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.people, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Alumnos del Grupo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        group['nombre'] ?? 'Grupo sin nombre',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Total de alumnos: ${studentsResult.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: studentsResult.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay alumnos en este grupo',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: studentsResult.length,
                        itemBuilder: (context, index) {
                          final student = studentsResult[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.blue[100],
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        student['nombre']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (student['friendlyName']?.toString() !=
                                          student['nombre']?.toString())
                                        Text(
                                          student['friendlyName']?.toString() ??
                                              '',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> addGroup() async {
    if (_grupoAnioController.text.trim().isEmpty ||
        _grupoSemestreController.text.trim().isEmpty ||
        _grupoLetraController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El año, semestre y grupo son obligatorios')),
        );
      }
      return;
    }

    final anio = int.tryParse(_grupoAnioController.text.trim());
    final semestre = int.tryParse(_grupoSemestreController.text.trim());

    if (anio == null || semestre == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El año y semestre deben ser números válidos')),
        );
      }
      return;
    }

    final grupoLetra = _grupoLetraController.text.trim();
    final db = await getDatabase();

    try {
      // Verificar si ya existe un grupo con el mismo año, semestre y grupo
      final existingGroup = await db.query(
        'grupos',
        where: 'anio_escolar = ? AND semestre = ? AND grupo_letra = ?',
        whereArgs: [anio, semestre, grupoLetra],
      );

      if (existingGroup.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Ya existe un grupo con ese año y semestre')),
          );
        }
        return;
      }

      // Generar nombre automático si no se especifica
      String nombre = _grupoNombreController.text.trim();
      if (nombre.isEmpty) {
        nombre = '$anio° Año - $semestre° Semestre - Grupo $grupoLetra';
      }

      await db.insert('grupos', {
        'anio_escolar': anio,
        'semestre': semestre,
        'grupo_letra': grupoLetra,
        'nombre': nombre,
      });

      // Limpiar formulario
      _grupoAnioController.clear();
      _grupoSemestreController.clear();
      _grupoNombreController.clear();

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grupo agregado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al agregar grupo: $e')),
        );
      }
    }
  }

  Future<void> updateGroup() async {
    if (_editingGrupoId == null) return;

    if (_grupoAnioController.text.trim().isEmpty ||
        _grupoSemestreController.text.trim().isEmpty ||
        _grupoLetraController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El año, semestre y grupo son obligatorios')),
        );
      }
      return;
    }

    final anio = int.tryParse(_grupoAnioController.text.trim());
    final semestre = int.tryParse(_grupoSemestreController.text.trim());
    final grupoLetra = _grupoLetraController.text.trim();

    if (anio == null || semestre == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El año y semestre deben ser números válidos')),
        );
      }
      return;
    }

    final db = await getDatabase();

    try {
      // Verificar si ya existe otro grupo con el mismo año, semestre y grupo
      final existingGroup = await db.query(
        'grupos',
        where:
            'anio_escolar = ? AND semestre = ? AND grupo_letra = ? AND id != ?',
        whereArgs: [anio, semestre, grupoLetra, _editingGrupoId],
      );

      if (existingGroup.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Ya existe otro grupo con ese año y semestre')),
          );
        }
        return;
      }

      // Generar nombre automático si no se especifica
      String nombre = _grupoNombreController.text.trim();
      if (nombre.isEmpty) {
        nombre = '$anio° Año - $semestre° Semestre - Grupo $grupoLetra';
      }

      await db.update(
        'grupos',
        {
          'anio_escolar': anio,
          'semestre': semestre,
          'grupo_letra': grupoLetra,
          'nombre': nombre,
        },
        where: 'id = ?',
        whereArgs: [_editingGrupoId],
      );

      // Limpiar formulario
      _grupoAnioController.clear();
      _grupoSemestreController.clear();
      _grupoLetraController.clear();
      _grupoNombreController.clear();
      _editingGrupoId = null;

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grupo actualizado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar grupo: $e')),
        );
      }
    }
  }

  Future<void> _deleteGroup(int grupoId) async {
    final db = await getDatabase();

    try {
      // Verificar si hay alumnos en este grupo
      final alumnosEnGrupo = await db.query(
        'alumnos',
        where: 'grupo_id = ?',
        whereArgs: [grupoId],
      );

      if (alumnosEnGrupo.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No se puede eliminar el grupo porque tiene alumnos asignados'),
            ),
          );
        }
        return;
      }

      await db.delete(
        'grupos',
        where: 'id = ?',
        whereArgs: [grupoId],
      );

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grupo eliminado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar grupo: $e')),
        );
      }
    }
  }

  // Funciones para gestión de usuarios
  Future<void> addUser() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        _nombreCompletoController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todos los campos son obligatorios')),
        );
      }
      return;
    }

    final db = await getDatabase();

    try {
      await db.insert('usuarios', {
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
        'nombre_completo': _nombreCompletoController.text.trim(),
        'rol': _selectedRol,
        'activo': 1,
        'fecha_creacion': DateTime.now().toIso8601String(),
      });

      // Limpiar formulario
      _usernameController.clear();
      _passwordController.clear();
      _nombreCompletoController.clear();
      _selectedRol = 'usuario';

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario agregado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al agregar usuario: $e')),
        );
      }
    }
  }

  Future<void> updateUser(int userId, String newUsername, String newPassword,
      String newNombreCompleto, String newRol, int newActivo) async {
    if (newUsername.trim().isEmpty ||
        newPassword.trim().isEmpty ||
        newNombreCompleto.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todos los campos son obligatorios')),
        );
      }
      return;
    }

    final db = await getDatabase();

    try {
      await db.update(
        'usuarios',
        {
          'username': newUsername.trim(),
          'password': newPassword.trim(),
          'nombre_completo': newNombreCompleto.trim(),
          'rol': newRol,
          'activo': newActivo,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario actualizado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar usuario: $e')),
        );
      }
    }
  }

  Future<void> deleteUser(int userId) async {
    final db = await getDatabase();

    try {
      await db.delete(
        'usuarios',
        where: 'id = ?',
        whereArgs: [userId],
      );

      // Recargar datos
      await fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario eliminado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar usuario: $e')),
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

  // Diálogos para gestión de usuarios
  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Nuevo Usuario'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de usuario *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nombreCompletoController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedRol,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'usuario',
                    child: Text('Usuario'),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Administrador'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedRol = value!;
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
              addUser();
              Navigator.pop(context);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final usernameController = TextEditingController(text: user['username']);
    final passwordController = TextEditingController(text: user['password']);
    final nombreCompletoController =
        TextEditingController(text: user['nombre_completo']);
    String selectedRol = user['rol'];
    int selectedActivo = user['activo'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Usuario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de usuario *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nombreCompletoController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRol,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'usuario',
                      child: Text('Usuario'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrador'),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRol = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selectedActivo,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 1,
                      child: Text('Activo'),
                    ),
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Inactivo'),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedActivo = value!;
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
                updateUser(
                  user['id'],
                  usernameController.text,
                  passwordController.text,
                  nombreCompletoController.text,
                  selectedRol,
                  selectedActivo,
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

  void _showDeleteUserConfirmation(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
            '¿Está seguro de que desea eliminar al usuario ${user['username']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              deleteUser(user['id']);
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

  Widget _buildProfilesTab() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Gestión de usuarios del sistema',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _showAddUserDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Agregar Usuario'),
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
          child: usuarios.isEmpty
              ? const Center(
                  child: Text(
                    'No hay usuarios registrados en el sistema.',
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
                                flex: 2,
                                child: Text('Usuario',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Expanded(
                                flex: 3,
                                child: Text('Nombre Completo',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Expanded(
                                flex: 1,
                                child: Text('Rol',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Expanded(
                                flex: 1,
                                child: Text('Estado',
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
                      // Lista de usuarios
                      Expanded(
                        child: ListView.builder(
                          itemCount: usuarios.length,
                          itemBuilder: (context, index) {
                            final user = usuarios[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8.0),
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      user['username'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(user['nombre_completo']),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user['rol'] == 'admin'
                                            ? Colors.red[100]
                                            : Colors.blue[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user['rol'] == 'admin'
                                            ? 'Admin'
                                            : 'Usuario',
                                        style: TextStyle(
                                          color: user['rol'] == 'admin'
                                              ? Colors.red[700]
                                              : Colors.blue[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user['activo'] == 1
                                            ? Colors.green[100]
                                            : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user['activo'] == 1
                                            ? 'Activo'
                                            : 'Inactivo',
                                        style: TextStyle(
                                          color: user['activo'] == 1
                                              ? Colors.green[700]
                                              : Colors.grey[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () =>
                                              _showEditUserDialog(user),
                                          tooltip: 'Editar',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () =>
                                              _showDeleteUserConfirmation(user),
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

  Widget _buildGroupsTab() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group, color: Colors.green[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Gestión de grupos escolares',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _showAddGroupDialog,
                icon: const Icon(Icons.add),
                label: const Text('Agregar Grupo'),
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
          child: groups.isEmpty
              ? const Center(
                  child: Text(
                    'No hay grupos registrados en el sistema.',
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
                                flex: 1,
                                child: Text('Año',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Expanded(
                                flex: 1,
                                child: Text('Semestre',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Expanded(
                                flex: 1,
                                child: Text('Grupo',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold))),
                            Expanded(
                                flex: 2,
                                child: Text('Nombre del Grupo',
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
                      // Lista de grupos
                      Expanded(
                        child: ListView.builder(
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8.0),
                              padding: const EdgeInsets.all(16.0),
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
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      '${group['anio_escolar']}° Año',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      '${group['semestre']}° Semestre',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      group['grupo_letra'] ?? 'Sin grupo',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      group['nombre'] ?? 'Sin nombre',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Row(
                                      children: [
                                        IconButton(
                                          onPressed: () =>
                                              _viewGroupStudents(group),
                                          icon: const Icon(Icons.visibility),
                                          color: Colors.green,
                                          tooltip: 'Ver alumnos',
                                        ),
                                        IconButton(
                                          onPressed: () => _editGroup(group),
                                          icon: const Icon(Icons.edit),
                                          color: Colors.blue,
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _deleteGroup(group['id']),
                                          icon: const Icon(Icons.delete),
                                          color: Colors.red,
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
                        Tab(
                          icon: Icon(Icons.group),
                          text: 'Grupos',
                        ),
                        Tab(
                          icon: Icon(Icons.person),
                          text: 'Perfiles',
                        ),
                        Tab(
                          icon: Icon(Icons.upload_file),
                          text: 'Carga Masiva',
                        ),
                        Tab(
                          icon: Icon(Icons.warning),
                          text: 'Mantenimiento',
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
                        _buildGroupsTab(),
                        _buildProfilesTab(),
                        _buildBulkUploadTab(),
                        _buildMaintenanceTab(),
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

  // Método para generar friendlyName removiendo acentos
  String _generateFriendlyName(String name) {
    return name
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  // Método para procesar texto pegado
  void _processPastedText() {
    final text = _bulkUploadTextController.text.trim();

    if (text.isEmpty) {
      _showErrorSnackBar('Debe pegar la lista de nombres');
      return;
    }

    // Dividir por líneas y limpiar
    List<String> names = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (names.isEmpty) {
      _showErrorSnackBar('No se encontraron nombres válidos');
      return;
    }

    setState(() {
      bulkUploadNames = names;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lista procesada: ${names.length} nombres encontrados'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Método para procesar la carga masiva
  Future<void> _processBulkUpload() async {
    if (selectedBulkUploadGroup == null) {
      _showErrorSnackBar('Debe seleccionar un grupo');
      return;
    }

    if (bulkUploadNames.isEmpty) {
      _showErrorSnackBar('No hay nombres para cargar');
      return;
    }

    setState(() {
      isBulkUploadLoading = true;
    });

    try {
      final db = await getDatabase();
      int successCount = 0;
      int errorCount = 0;

      for (String name in bulkUploadNames) {
        try {
          // Verificar si el alumno ya existe
          final existingStudent = await db.query(
            'alumnos',
            where: 'nombre = ?',
            whereArgs: [name],
          );

          if (existingStudent.isNotEmpty) {
            errorCount++;
            continue; // Saltar si ya existe
          }

          // Insertar nuevo alumno
          await db.insert('alumnos', {
            'nombre': name,
            'friendlyName': _generateFriendlyName(name),
            'grupo_id': int.parse(selectedBulkUploadGroup!),
          });

          successCount++;
        } catch (e) {
          errorCount++;
          print('Error al insertar $name: $e');
        }
      }

      // Recargar datos
      await fetchData();

      setState(() {
        isBulkUploadLoading = false;
        bulkUploadNames = [];
        selectedBulkUploadGroup = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Carga completada: $successCount exitosos, $errorCount errores'),
            backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        isBulkUploadLoading = false;
      });
      _showErrorSnackBar('Error en la carga masiva: $e');
    }
  }

  // Método para mostrar errores
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Widget para el tab de carga masiva
  Widget _buildBulkUploadTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Carga Masiva de Alumnos',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
          ),
          const SizedBox(height: 20),

          // Selector de grupo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paso 1: Seleccionar Grupo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedBulkUploadGroup,
                  decoration: const InputDecoration(
                    labelText: 'Grupo de destino',
                    border: OutlineInputBorder(),
                    hintText:
                        'Seleccione el grupo donde se cargarán los alumnos',
                  ),
                  items: groups
                      .map((group) => DropdownMenuItem(
                            value: group['id'].toString(),
                            child: Text(group['nombre']),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBulkUploadGroup = value;
                    });
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Carga de texto
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paso 2: Pegar Lista de Alumnos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pega la lista de nombres de alumnos (uno por línea). Puedes copiar desde Excel, Word o cualquier documento.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: TextField(
                    controller: _bulkUploadTextController,
                    maxLines: 6,
                    minLines: 4,
                    decoration: const InputDecoration(
                      hintText:
                          'Pega aquí la lista de nombres...\n\nEjemplo:\nGARCÍA LÓPEZ MARÍA JOSÉ\nRODRÍGUEZ MARTÍNEZ JUAN CARLOS\nPÉREZ GONZÁLEZ ANA LUCÍA',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16.0),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _processPastedText,
                      icon: const Icon(Icons.check),
                      label: const Text('Procesar Lista'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () {
                        _bulkUploadTextController.clear();
                        setState(() {
                          bulkUploadNames = [];
                        });
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Limpiar'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Vista previa
          if (bulkUploadNames.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paso 3: Vista Previa',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nombres encontrados: ${bulkUploadNames.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: ListView.builder(
                      itemCount: bulkUploadNames.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          dense: true,
                          title: Text(bulkUploadNames[index]),
                          leading: Text('${index + 1}'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Botón de confirmación
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paso 4: Confirmar Carga',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Se cargarán ${bulkUploadNames.length} alumnos al grupo seleccionado.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.green[700],
                        ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          isBulkUploadLoading ? null : _processBulkUpload,
                      icon: isBulkUploadLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(isBulkUploadLoading
                          ? 'Procesando...'
                          : 'Confirmar Carga'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Métodos para mantenimiento de base de datos
  Future<void> _deleteGroupWithStudents(String groupId) async {
    final db = await getDatabase();

    try {
      // Obtener información del grupo antes de eliminarlo
      final groupInfo = await db.query(
        'grupos',
        where: 'id = ?',
        whereArgs: [groupId],
      );

      if (groupInfo.isEmpty) {
        _showErrorSnackBar('Grupo no encontrado');
        return;
      }

      final groupName = groupInfo.first['nombre'] ?? 'Grupo sin nombre';

      // Obtener alumnos del grupo
      final studentsInGroup = await db.query(
        'alumnos',
        where: 'grupo_id = ?',
        whereArgs: [groupId],
      );

      // Mostrar confirmación
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Confirmar Eliminación'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Estás seguro de que quieres eliminar el grupo "$groupName"?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text('Esta acción eliminará:'),
              const SizedBox(height: 8),
              Text('• El grupo completo'),
              Text('• ${studentsInGroup.length} alumnos'),
              Text('• Todas las asistencias de estos alumnos'),
              const SizedBox(height: 16),
              Text(
                '⚠️ Esta acción NO se puede deshacer',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Eliminar Todo'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        isMaintenanceLoading = true;
      });

      // Eliminar asistencias de los alumnos del grupo
      for (var student in studentsInGroup) {
        await db.delete(
          'asistencias',
          where: 'alumno_id = ?',
          whereArgs: [student['id']],
        );
      }

      // Eliminar alumnos del grupo
      await db.delete(
        'alumnos',
        where: 'grupo_id = ?',
        whereArgs: [groupId],
      );

      // Eliminar el grupo
      await db.delete(
        'grupos',
        where: 'id = ?',
        whereArgs: [groupId],
      );

      // Recargar datos
      await fetchData();

      setState(() {
        isMaintenanceLoading = false;
        selectedMaintenanceGroup = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Grupo "$groupName" eliminado con ${studentsInGroup.length} alumnos'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        isMaintenanceLoading = false;
      });
      _showErrorSnackBar('Error al eliminar grupo: $e');
    }
  }

  Future<void> _deleteStudentWithAttendances(String studentId) async {
    final db = await getDatabase();

    try {
      // Obtener información del alumno
      final studentInfo = await db.rawQuery('''
        SELECT a.nombre, g.nombre AS grupo_nombre
        FROM alumnos a
        JOIN grupos g ON a.grupo_id = g.id
        WHERE a.id = ?
      ''', [studentId]);

      if (studentInfo.isEmpty) {
        _showErrorSnackBar('Alumno no encontrado');
        return;
      }

      final studentName = studentInfo.first['nombre'];
      final groupName = studentInfo.first['grupo_nombre'];

      // Obtener número de asistencias
      final attendancesCount = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM asistencias
        WHERE alumno_id = ?
      ''', [studentId]);

      final count = attendancesCount.first['count'] as int;

      // Mostrar confirmación
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Confirmar Eliminación'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Estás seguro de que quieres eliminar al alumno "$studentName"?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text('Esta acción eliminará:'),
              const SizedBox(height: 8),
              Text('• El alumno del grupo "$groupName"'),
              Text('• $count registros de asistencia'),
              const SizedBox(height: 16),
              Text(
                '⚠️ Esta acción NO se puede deshacer',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Eliminar Alumno'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        isMaintenanceLoading = true;
      });

      // Eliminar asistencias del alumno
      await db.delete(
        'asistencias',
        where: 'alumno_id = ?',
        whereArgs: [studentId],
      );

      // Eliminar el alumno
      await db.delete(
        'alumnos',
        where: 'id = ?',
        whereArgs: [studentId],
      );

      // Recargar datos
      await fetchData();

      setState(() {
        isMaintenanceLoading = false;
        selectedMaintenanceStudent = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Alumno "$studentName" eliminado con $count asistencias'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        isMaintenanceLoading = false;
      });
      _showErrorSnackBar('Error al eliminar alumno: $e');
    }
  }

  Future<void> _createDatabaseBackup() async {
    try {
      setState(() {
        isBackupLoading = true;
      });

      final db = await getDatabase();

      // Obtener estadísticas de la base de datos
      final studentsCount =
          await db.rawQuery('SELECT COUNT(*) as count FROM alumnos');
      final groupsCount =
          await db.rawQuery('SELECT COUNT(*) as count FROM grupos');
      final attendancesCount =
          await db.rawQuery('SELECT COUNT(*) as count FROM asistencias');
      final usersCount =
          await db.rawQuery('SELECT COUNT(*) as count FROM usuarios');

      final totalStudents = studentsCount.first['count'] as int;
      final totalGroups = groupsCount.first['count'] as int;
      final totalAttendances = attendancesCount.first['count'] as int;
      final totalUsers = usersCount.first['count'] as int;

      // Crear nombre del archivo con fecha y hora
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final backupFileName = 'SICAE_backup_$timestamp.sql';

      // Generar SQL de backup
      String backupSQL = '-- Backup de SICAE - $timestamp\n';
      backupSQL += '-- Generado automáticamente\n\n';

      // Backup de grupos
      backupSQL += '-- Backup de grupos\n';
      final groups = await db.query('grupos');
      for (var group in groups) {
        backupSQL +=
            "INSERT INTO grupos (id, anio_escolar, semestre, grupo_letra, nombre) VALUES (${group['id']}, ${group['anio_escolar']}, ${group['semestre']}, '${group['grupo_letra']}', '${group['nombre']}');\n";
      }
      backupSQL += '\n';

      // Backup de alumnos
      backupSQL += '-- Backup de alumnos\n';
      final students = await db.query('alumnos');
      for (var student in students) {
        backupSQL +=
            "INSERT INTO alumnos (id, nombre, grupo_id, friendlyName) VALUES (${student['id']}, '${student['nombre']}', ${student['grupo_id']}, '${student['friendlyName']}');\n";
      }
      backupSQL += '\n';

      // Backup de asistencias
      backupSQL += '-- Backup de asistencias\n';
      final attendances = await db.query('asistencias');
      for (var attendance in attendances) {
        backupSQL +=
            "INSERT INTO asistencias (id, alumno_id, fecha, hora, presente) VALUES (${attendance['id']}, ${attendance['alumno_id']}, '${attendance['fecha']}', '${attendance['hora']}', ${attendance['presente']});\n";
      }
      backupSQL += '\n';

      // Backup de usuarios
      backupSQL += '-- Backup de usuarios\n';
      final users = await db.query('usuarios');
      for (var user in users) {
        backupSQL +=
            "INSERT INTO usuarios (id, username, password, nombre_completo, rol) VALUES (${user['id']}, '${user['username']}', '${user['password']}', '${user['nombre_completo']}', '${user['rol']}');\n";
      }

      // Mostrar información del backup
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.backup, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Backup Completado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backup generado exitosamente',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text('Archivo: $backupFileName'),
                const SizedBox(height: 8),
                Text('Contenido del backup:'),
                const SizedBox(height: 8),
                Text('• $totalGroups grupos'),
                Text('• $totalStudents alumnos'),
                Text('• $totalAttendances asistencias'),
                Text('• $totalUsers usuarios'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SQL del Backup:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        width: double.maxFinite,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            backupSQL,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '💡 Copia este SQL y guárdalo en un archivo .sql para restaurar la base de datos si es necesario.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  // Aquí podrías implementar la descarga del archivo
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Backup completado. Copia el SQL mostrado para guardarlo.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar SQL'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ],
          ),
        );
      }

      setState(() {
        isBackupLoading = false;
      });
    } catch (e) {
      setState(() {
        isBackupLoading = false;
      });
      _showErrorSnackBar('Error al crear backup: $e');
    }
  }

  Future<void> _clearAllAttendances() async {
    try {
      // Obtener total de asistencias
      final db = await getDatabase();
      final attendancesCount =
          await db.rawQuery('SELECT COUNT(*) as count FROM asistencias');
      final totalCount = attendancesCount.first['count'] as int;

      if (totalCount == 0) {
        _showErrorSnackBar('No hay asistencias para eliminar');
        return;
      }

      // Mostrar confirmación
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Confirmar Limpieza'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Estás seguro de que quieres eliminar TODAS las asistencias?',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text('Esta acción eliminará:'),
              const SizedBox(height: 8),
              Text('• $totalCount registros de asistencia'),
              Text('• Todos los datos de asistencia de todos los alumnos'),
              const SizedBox(height: 16),
              Text(
                '⚠️ Esta acción NO se puede deshacer',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Eliminar Todo'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        isMaintenanceLoading = true;
      });

      // Eliminar todas las asistencias
      await db.delete('asistencias');

      // Recargar datos
      await fetchData();

      setState(() {
        isMaintenanceLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se eliminaron $totalCount registros de asistencia'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        isMaintenanceLoading = false;
      });
      _showErrorSnackBar('Error al limpiar asistencias: $e');
    }
  }

  // Widget para el tab de mantenimiento
  Widget _buildMaintenanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Advertencia principal
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.red[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red[700], size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Zona de Riesgo - Mantenimiento de Base de Datos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.red[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '⚠️ Las acciones en esta sección son IRREVERSIBLES. Se recomienda hacer backup de la base de datos antes de realizar cualquier operación.',
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Crear backup de la base de datos
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.green[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crear Backup de Base de Datos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Genera un archivo SQL con todos los datos actuales. Útil antes de realizar operaciones de mantenimiento.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.green[700],
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isBackupLoading ? null : _createDatabaseBackup,
                    icon: isBackupLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup),
                    label: Text(isBackupLoading
                        ? 'Generando Backup...'
                        : 'Crear Backup SQL'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Eliminar grupo completo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Eliminar Grupo Completo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Elimina un grupo y todos sus alumnos, incluyendo todas las asistencias registradas.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.orange[700],
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedMaintenanceGroup,
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar grupo a eliminar',
                    border: OutlineInputBorder(),
                  ),
                  items: groups
                      .map((group) => DropdownMenuItem(
                            value: group['id'].toString(),
                            child: Text(group['nombre']),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedMaintenanceGroup = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: selectedMaintenanceGroup == null ||
                            isMaintenanceLoading
                        ? null
                        : () =>
                            _deleteGroupWithStudents(selectedMaintenanceGroup!),
                    icon: isMaintenanceLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_forever),
                    label: Text(isMaintenanceLoading
                        ? 'Procesando...'
                        : 'Eliminar Grupo y Alumnos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Eliminar alumno específico
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Eliminar Alumno Específico',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Elimina un alumno específico y todas sus asistencias registradas.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.orange[700],
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedMaintenanceStudent,
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar alumno a eliminar',
                    border: OutlineInputBorder(),
                  ),
                  items: students
                      .map((student) => DropdownMenuItem(
                            value: student['id'].toString(),
                            child: Text(
                                '${student['nombre']} (${student['grupo_nombre']})'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedMaintenanceStudent = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: selectedMaintenanceStudent == null ||
                            isMaintenanceLoading
                        ? null
                        : () => _deleteStudentWithAttendances(
                            selectedMaintenanceStudent!),
                    icon: isMaintenanceLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_remove),
                    label: Text(isMaintenanceLoading
                        ? 'Procesando...'
                        : 'Eliminar Alumno y Asistencias'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Limpiar todas las asistencias
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.red[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Limpiar Todas las Asistencias',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  '⚠️ Elimina TODOS los registros de asistencia de TODOS los alumnos. Los alumnos y grupos se mantienen intactos.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.red[700],
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        isMaintenanceLoading ? null : _clearAllAttendances,
                    icon: isMaintenanceLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.clear_all),
                    label: Text(isMaintenanceLoading
                        ? 'Procesando...'
                        : 'Eliminar Todas las Asistencias'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _friendlyNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nombreCompletoController.dispose();
    _grupoAnioController.dispose();
    _grupoSemestreController.dispose();
    _grupoLetraController.dispose();
    _grupoNombreController.dispose();
    _bulkUploadTextController.dispose();
    super.dispose();
  }
}
