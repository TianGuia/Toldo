-- Cambios propuestos respecto de la exportación; aplicar primero en desarrollo.
-- Los clientes necesitan operaciones de datos, no administrar tablas.
REVOKE TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON ALL TABLES IN SCHEMA public
  FROM anon, authenticated, PUBLIC;
REVOKE CREATE ON SCHEMA public FROM anon, authenticated, PUBLIC;

-- Las tablas nuevas deberán declarar sus GRANTs explícitamente.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated, PUBLIC;
