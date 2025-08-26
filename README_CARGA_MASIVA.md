# Carga Masiva de Alumnos - SICAE

## Descripción

Se ha implementado una nueva funcionalidad de carga masiva de alumnos en el sistema SICAE que permite a los administradores cargar múltiples alumnos desde un archivo CSV de manera rápida y eficiente.

## Características

### 1. Interfaz Intuitiva
- **Selector de Grupo**: Dropdown con todos los grupos disponibles en la base de datos
- **Carga de Archivo**: Botón para seleccionar archivo CSV
- **Vista Previa**: Muestra los nombres que se van a cargar
- **Confirmación**: Botón para confirmar la carga masiva

### 2. Procesamiento Automático
- **Asignación de Grupo**: Todos los alumnos se asignan al grupo seleccionado
- **Generación de FriendlyName**: Se genera automáticamente removiendo acentos y ñ
- **Validación de Duplicados**: Evita cargar alumnos que ya existen
- **Manejo de Errores**: Muestra estadísticas de éxito y errores

### 3. Formato del Archivo CSV

El archivo CSV debe tener la siguiente estructura:

```csv
nombre
"GARCÍA LÓPEZ MARÍA JOSÉ"
"RODRÍGUEZ MARTÍNEZ JUAN CARLOS"
"PÉREZ GONZÁLEZ ANA LUCÍA"
"SÁNCHEZ DÍAZ CARLOS"
"LÓPEZ FERNÁNDEZ SOFÍA"
```

#### Requisitos:
- **Columna obligatoria**: `nombre` (con comillas dobles)
- **Formato**: UTF-8 para caracteres especiales
- **Separador**: Coma (,)
- **Primera fila**: Headers (nombre)

### 4. Proceso de Carga

1. **Seleccionar Grupo**: Elegir el grupo de destino de la lista desplegable
2. **Cargar Archivo**: Seleccionar el archivo CSV con los nombres
3. **Revisar Vista Previa**: Verificar los nombres que se van a cargar
4. **Confirmar Carga**: Ejecutar la carga masiva

### 5. Validaciones

- **Archivo válido**: Verifica que sea un archivo CSV
- **Columna requerida**: Verifica que exista la columna "nombre"
- **Nombres únicos**: Evita duplicados por nombre
- **Nombres no vacíos**: Valida que no haya nombres vacíos
- **Grupo seleccionado**: Verifica que se haya elegido un grupo

### 6. Resultados

Al finalizar la carga, el sistema muestra:
- **Número de alumnos cargados exitosamente**
- **Número de errores** (duplicados, etc.)
- **Mensaje de confirmación**

## Uso

### Para Administradores

1. **Acceder a la carga masiva**:
   - Ir a la página de Administración
   - Hacer clic en la pestaña "Carga Masiva"

2. **Preparar el archivo CSV**:
   - Crear un archivo CSV con la columna "nombre"
   - Incluir los nombres completos de los alumnos
   - Guardar en formato UTF-8

3. **Ejecutar la carga**:
   - Seleccionar el grupo de destino
   - Cargar el archivo CSV
   - Revisar la vista previa
   - Confirmar la carga

### Ejemplo de Archivo CSV

Se incluye un archivo de ejemplo: `ejemplo_carga_masiva.csv`

```csv
nombre
"GARCÍA LÓPEZ MARÍA JOSÉ"
"RODRÍGUEZ MARTÍNEZ JUAN CARLOS"
"PÉREZ GONZÁLEZ ANA LUCÍA"
"SÁNCHEZ DÍAZ CARLOS"
"LÓPEZ FERNÁNDEZ SOFÍA"
```

## Notas Importantes

- **Backup**: Se recomienda hacer backup de la base de datos antes de cargas masivas
- **Pruebas**: Probar primero con pocos registros
- **Formato**: Asegurar que el archivo esté en formato UTF-8
- **Nombres**: Usar nombres completos como aparecen en documentos oficiales

## Solución de Problemas

### Error: "El archivo CSV debe tener una columna llamada 'nombre'"
- Verificar que la primera fila contenga exactamente "nombre"
- Asegurar que no haya espacios extra

### Error: "No hay nombres para cargar"
- Verificar que el archivo no esté vacío
- Asegurar que haya datos después de la fila de headers

### Alumnos no se cargan
- Verificar que los nombres no existan ya en la base de datos
- Revisar el formato del archivo CSV
