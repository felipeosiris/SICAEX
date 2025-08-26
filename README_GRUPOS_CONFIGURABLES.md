# Grupos Configurables - SICAE

## Descripción

Se ha implementado una nueva funcionalidad de grupos configurables en el sistema SICAE que permite a los administradores crear, editar y gestionar grupos escolares de manera dinámica.

## Características

### 1. Gestión de Grupos
- **Crear grupos**: Los administradores pueden crear nuevos grupos especificando:
  - Año escolar (1°, 2°, 3°, 4°, 5°, 6°)
  - Semestre (1°, 2°, 3°, 4°, 5°, 6°, 7°, 8°, 9°, 10°, 11°, 12°)
  - Grupo (A, B, C, 1, 2, 3, etc.)
  - Nombre personalizado (opcional)

- **Editar grupos**: Modificar la información de grupos existentes
- **Eliminar grupos**: Eliminar grupos que no tengan alumnos asignados
- **Validaciones**: 
        - No se pueden crear grupos duplicados (mismo año, semestre y grupo)
      - No se pueden eliminar grupos con alumnos asignados

### 2. Nueva Pestaña "Grupos"
Se ha agregado una nueva pestaña en la página de administración que incluye:
- Lista de todos los grupos existentes
- Botón para agregar nuevos grupos
- Acciones para editar y eliminar grupos
- Interfaz intuitiva con filtros y búsqueda

### 3. Filtros Mejorados en la Página de Estudiantes
La página de estudiantes ahora incluye:
- Filtro por año escolar
- Filtro por semestre
- Filtro por grupo específico
- Búsqueda por nombre de alumno
- Los filtros se generan dinámicamente basados en los grupos existentes

### 4. Base de Datos Actualizada
Se han agregado grupos adicionales a la base de datos:
- Grupos para 4°, 5° y 6° año
- Múltiples grupos por año/semestre (Grupo A, Grupo B, etc.)
- Total de 24 grupos configurables

## Estructura de la Base de Datos

### Tabla `grupos`
```sql
CREATE TABLE grupos (
  id INTEGER PRIMARY KEY,
  anio_escolar INTEGER NOT NULL,
  semestre INTEGER NOT NULL,
  grupo_letra TEXT,
  nombre TEXT
);
```

### Relación con Alumnos
Los alumnos están vinculados a grupos a través del campo `grupo_id` en la tabla `alumnos`.

## Uso

### Para Administradores

1. **Acceder a la gestión de grupos**:
   - Ir a la página de Administración
   - Seleccionar la pestaña "Grupos"

2. **Crear un nuevo grupo**:
   - Hacer clic en "Agregar Grupo"
   - Completar los campos requeridos (Año, Semestre, Grupo)
   - El nombre se genera automáticamente si no se especifica

3. **Editar un grupo existente**:
   - Hacer clic en el ícono de editar (lápiz)
   - Modificar los campos necesarios
   - Guardar los cambios

4. **Eliminar un grupo**:
   - Hacer clic en el ícono de eliminar (basura)
   - Solo se puede eliminar si no tiene alumnos asignados

### Para Usuarios

1. **Filtrar estudiantes por grupo**:
   - En la página de Estudiantes
   - Usar los filtros de año, semestre y grupo específico
   - Los filtros se actualizan automáticamente según los grupos disponibles

## Archivos Modificados

### Archivos Principales
- `lib/pages/page_administration.dart` - Nueva pestaña de grupos
- `lib/pages/page_students.dart` - Filtros mejorados
- `assets/database/dump.sqlite.sql` - Grupos adicionales

### Archivos de Migración
- `assets/database/migration_add_more_groups.sql` - Script para agregar grupos

## Beneficios

1. **Flexibilidad**: Los administradores pueden crear grupos según las necesidades específicas de la institución
2. **Escalabilidad**: El sistema puede manejar múltiples años y semestres
3. **Organización**: Mejor gestión y visualización de los estudiantes por grupos
4. **Mantenimiento**: Fácil actualización y gestión de grupos sin necesidad de modificar código

## Notas Técnicas

- Los grupos se validan para evitar duplicados
- La eliminación de grupos está protegida para evitar pérdida de datos
- Los filtros se generan dinámicamente basados en los grupos existentes
- La interfaz es responsive y se adapta a diferentes tamaños de pantalla

## Próximas Mejoras

- Importación masiva de grupos desde archivos CSV
- Asignación masiva de estudiantes a grupos
- Estadísticas por grupo
- Exportación de listas por grupo
