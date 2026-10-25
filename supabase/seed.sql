-- Datos sintéticos de desarrollo; nunca copiar cuentas reales.
INSERT INTO public.categorias (nombre) VALUES ('Ropa'), ('Comida'), ('Coleccionables') ON CONFLICT (nombre) DO NOTHING;
