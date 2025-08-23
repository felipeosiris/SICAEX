-- Script para actualizar registros existentes con horas por defecto
-- Este script asigna horas aleatorias entre 8:00 y 9:00 AM para registros existentes

-- Actualizar registros que no tienen hora asignada
UPDATE asistencias 
SET hora = CASE 
    WHEN id % 5 = 0 THEN '08:00:00'
    WHEN id % 5 = 1 THEN '08:15:00'
    WHEN id % 5 = 2 THEN '08:30:00'
    WHEN id % 5 = 3 THEN '08:45:00'
    WHEN id % 5 = 4 THEN '09:00:00'
END
WHERE hora IS NULL;
