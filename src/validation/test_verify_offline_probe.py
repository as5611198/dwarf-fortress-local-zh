import copy
import unittest
from verify_offline_probe import validate


class ProbeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.corpus = {'fixture': {'sources': [f'Sentence {i}' for i in range(105)]}}
        self.expected = dict(runId='current-run', version='0.5.10', world='isolated-world', startedAt=1000)
        self.report = dict(self.expected, schema=2, status='passed', finishedAt=1010,
                           worldLoaded=True, mapLoaded=True, focus='dwarfmode/Default', apiEnabled=False,
                           checks=210, failures=[], negativeChecks=1)
        self.report['samples'] = [dict(page=page, language=language, source=source, translation='中文', first_ms=0)
            for language in ['zh-Hant', 'zh-Hans'] for page, entry in self.corpus.items() for source in entry['sources']]
        self.report['fps'] = [dict(tick=1000+i*1000, render=50, paused=True, world='isolated-world',
            worldLoaded=True, mapLoaded=True, focus='dwarfmode/Default', apiEnabled=False) for i in range(6)]
        self.saves = dict(baselineRunId='current-run', protectedFiles=10, changed=[], missing=[], added=[], unexpected=[])

    def test_valid_complete_run(self):
        validate(self.report, self.expected, self.corpus, self.saves)

    def test_menu_result_cannot_pass_as_loaded_world(self):
        for field in ['world', 'worldLoaded', 'mapLoaded', 'focus']:
            report = copy.deepcopy(self.report)
            report.pop(field)
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(report, self.expected, self.corpus, self.saves)

    def test_reject_stale_or_incomplete_run(self):
        for field, value in [('runId', 'previous-run'), ('status', 'running'), ('finishedAt', 999)]:
            report = dict(self.report, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(report, self.expected, self.corpus, self.saves)

    def test_fps_requires_world_at_each_sample(self):
        for field, value in [('world', 'other-world'), ('worldLoaded', False), ('mapLoaded', False),
                             ('focus', 'title'), ('apiEnabled', True), ('render', float('nan'))]:
            report = copy.deepcopy(self.report)
            report['fps'][2][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(report, self.expected, self.corpus, self.saves)

    def test_reject_frozen_or_missing_fps_samples(self):
        for fps in [[], self.report['fps'][:1], [self.report['fps'][0]] * 6]:
            with self.assertRaises(ValueError):
                validate(dict(self.report, fps=fps), self.expected, self.corpus, self.saves)

    def test_missing_or_duplicate_corpus_rows_do_not_count_as_coverage(self):
        for samples in [self.report['samples'][:-1], self.report['samples'][:105] * 2]:
            with self.assertRaises(ValueError):
                validate(dict(self.report, samples=samples), self.expected, self.corpus, self.saves)

    def test_blank_translation_or_failed_negative_control_rejected(self):
        report = copy.deepcopy(self.report)
        report['samples'][0]['translation'] = ''
        with self.assertRaises(ValueError):
            validate(report, self.expected, self.corpus, self.saves)
        with self.assertRaises(ValueError):
            validate(dict(self.report, negativeChecks=0), self.expected, self.corpus, self.saves)

    def test_save_changes_cannot_be_reviewed_away(self):
        for field in ['changed', 'missing', 'added', 'unexpected']:
            saves = dict(self.saves, **{field: ['region4/world.sav']})
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(self.report, self.expected, self.corpus, saves)
        with self.assertRaises(ValueError):
            validate(self.report, self.expected, self.corpus, dict(self.saves, baselineRunId='old-run'))


if __name__ == '__main__':
    unittest.main()
