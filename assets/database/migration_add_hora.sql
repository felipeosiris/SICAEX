-- Migración para agregar columna hora a la tabla asistencias
-- Ejecutar este script para actualizar la base de datos existente

-- Agregar columna hora a la tabla asistencias
ALTER TABLE asistencias ADD COLUMN hora TEXT;

-- Actualizar registros existentes con hora por defecto (opcional)
-- UPDATE asistencias SET hora = '00:00:00' WHERE hora IS NULL;
