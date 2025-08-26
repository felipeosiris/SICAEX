-- Migración para agregar tabla de usuarios
-- Crear tabla de usuarios para autenticación

CREATE TABLE IF NOT EXISTS usuarios (
  id INTEGER PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  nombre_completo TEXT NOT NULL,
  rol TEXT NOT NULL DEFAULT 'usuario', -- 'admin' o 'usuario'
  activo INTEGER NOT NULL DEFAULT 1, -- 0 = inactivo, 1 = activo
  fecha_creacion TEXT NOT NULL DEFAULT (datetime('now')),
  ultimo_acceso TEXT
);

-- Insertar usuario administrador por defecto
INSERT OR IGNORE INTO usuarios (id, username, password, nombre_completo, rol) 
VALUES (1, 'admin', 'epo26pass', 'Administrador del Sistema', 'admin');

-- Crear índices para mejorar el rendimiento
CREATE INDEX IF NOT EXISTS idx_usuarios_username ON usuarios(username);
CREATE INDEX IF NOT EXISTS idx_usuarios_activo ON usuarios(activo);
