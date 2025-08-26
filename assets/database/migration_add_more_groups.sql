-- Script para agregar más grupos configurables
-- Este script agrega grupos adicionales para diferentes años y semestres

-- Primero agregar la columna grupo_letra si no existe
ALTER TABLE grupos ADD COLUMN grupo_letra TEXT;

-- Agregar grupos para 4° año (7° y 8° semestre)
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (4, 7, 'A', '4° Año - 7° Semestre - Grupo A');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (4, 8, 'A', '4° Año - 8° Semestre - Grupo A');

-- Agregar grupos para 5° año (9° y 10° semestre)
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (5, 9, 'A', '5° Año - 9° Semestre - Grupo A');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (5, 10, 'A', '5° Año - 10° Semestre - Grupo A');

-- Agregar grupos para 6° año (11° y 12° semestre)
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (6, 11, 'A', '6° Año - 11° Semestre - Grupo A');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (6, 12, 'A', '6° Año - 12° Semestre - Grupo A');

-- Agregar grupos adicionales para 1° año (grupos B, C)
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (1, 1, 'B', '1° Año - 1° Semestre - Grupo B');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (1, 1, 'C', '1° Año - 1° Semestre - Grupo C');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (1, 2, 'B', '1° Año - 2° Semestre - Grupo B');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (1, 2, 'C', '1° Año - 2° Semestre - Grupo C');

-- Agregar grupos adicionales para 2° año (grupos B, C)
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (2, 3, 'B', '2° Año - 3° Semestre - Grupo B');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (2, 3, 'C', '2° Año - 3° Semestre - Grupo C');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (2, 4, 'B', '2° Año - 4° Semestre - Grupo B');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (2, 4, 'C', '2° Año - 4° Semestre - Grupo C');

-- Agregar grupos adicionales para 3° año (grupos B, C)
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (3, 5, 'B', '3° Año - 5° Semestre - Grupo B');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (3, 5, 'C', '3° Año - 5° Semestre - Grupo C');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (3, 6, 'B', '3° Año - 6° Semestre - Grupo B');
INSERT INTO grupos (anio_escolar, semestre, grupo_letra, nombre) VALUES (3, 6, 'C', '3° Año - 6° Semestre - Grupo C');

-- Verificar que los grupos se insertaron correctamente
SELECT * FROM grupos ORDER BY anio_escolar, semestre, grupo_letra;
