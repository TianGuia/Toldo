-- Solo lectura, ejecutar antes de desplegar 20261027000200_align_domain_contract.sql.
-- No lista datos personales; cuenta las condiciones que bloquearían la migración.
SELECT 'productos_sin_puesto_ambiguos' AS condicion, count(*) AS pendientes
FROM public.productos p WHERE p.id_puesto IS NULL
  AND (SELECT count(*) FROM public.puestos pu WHERE pu.id_vendedor = p.id_vendedor) <> 1
UNION ALL
SELECT 'productos_en_puesto_ajeno', count(*)
FROM public.productos p JOIN public.puestos pu ON pu.id = p.id_puesto
WHERE p.id_vendedor <> pu.id_vendedor
UNION ALL
SELECT 'ofertas_sin_productos', count(*) FROM public.ofertas o
WHERE NOT EXISTS (SELECT 1 FROM public.oferta_productos op WHERE op.id_oferta = o.id)
UNION ALL
SELECT 'ofertas_con_productos_ajenos', count(*) FROM public.oferta_productos op
JOIN public.ofertas o ON o.id = op.id_oferta JOIN public.productos p ON p.id = op.id_producto
WHERE o.id_vendedor <> p.id_vendedor;
