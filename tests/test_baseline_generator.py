import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('baseline', ROOT / 'scripts/build-baseline.py')
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


class BaselineGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'schema-reference.sql').read_text(encoding='utf-8')
        cls.metadata = json.loads((ROOT / 'docs/snapshots/baseline-20261027.json').read_text(encoding='utf-8'))

    def test_committed_baseline_is_reproducible(self):
        actual = (ROOT / 'supabase/migrations/20261027000000_baseline_supabase.sql').read_text(encoding='utf-8')
        self.assertEqual(actual, baseline.assemble(self.source, self.metadata))

    def test_rejects_export_with_production_rows(self):
        with self.assertRaises(ValueError):
            baseline.assemble(self.source + '\nINSERT INTO public.usuarios VALUES (1);', self.metadata)

    def test_rejects_empty_export(self):
        with self.assertRaises(ValueError):
            baseline.assemble('', self.metadata)

    def test_acl_is_reset_before_column_grants(self):
        sql = baseline.assemble(self.source, self.metadata)
        self.assertLess(sql.index('REVOKE ALL ON ALL TABLES'), sql.index('GRANT UPDATE("nombre_publico")'))

    def test_baseline_does_not_create_proposed_domain_entities(self):
        sql = baseline.assemble(self.source, self.metadata)
        self.assertNotIn('CREATE TABLE public.compradores', sql)
        self.assertNotIn('CREATE TABLE public.participantes', sql)
        self.assertIn('usuarios_nombre_publico_unico', sql)

    def test_rejects_unreviewed_cron_commands(self):
        metadata = {**self.metadata, 'cron_jobs': [{'jobname': 'x', 'schedule': '* * * * *',
            'command': "select net.http_post('https://example.test', '{}')", 'active': True}]}
        with self.assertRaises(ValueError):
            baseline.assemble(self.source, metadata)


if __name__ == '__main__':
    unittest.main()
