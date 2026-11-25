-- RF-25, RF-49 y RNF-4. Los eventos invalidan las consultas públicas de la app.
-- Puestos ya pertenece a esta publicación. Las tablas conservan sus políticas RLS.
alter publication supabase_realtime add table public.ofertas, public.productos,
  public.tianguis, public.tianguis_zonas;
