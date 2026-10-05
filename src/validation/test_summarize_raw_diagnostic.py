import copy
import unittest
from summarize_raw_diagnostic import summarize


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.corpus = {'pages': {'test': {'sources': ['a', 'b']}}}
        self.report = {'samples': [{'language': lang, 'page': 'test', 'source': source, 'translation': target}
            for lang in ('zh-Hant', 'zh-Hans') for source, target in [('a', '中文'), ('b', None)]]}

    def test_misses_stay_in_denominator(self):
        result = summarize(self.corpus, self.report)
        self.assertEqual(result['zh-Hant']['returnRate'], 0.5)
        self.assertEqual(result['zh-Hans']['categories']['test']['chineseWithoutLatin'], 1)

    def test_duplicate_cannot_replace_missing_row(self):
        report = copy.deepcopy(self.report)
        report['samples'][1] = copy.deepcopy(report['samples'][0])
        with self.assertRaises(ValueError):
            summarize(self.corpus, report)

    def test_empty_or_english_fallback_is_not_chinese(self):
        report = copy.deepcopy(self.report)
        report['samples'][0]['translation'] = 'a'
        report['samples'][1]['translation'] = ''
        result = summarize(self.corpus, report)['zh-Hant']['categories']['test']
        self.assertEqual(result['returned'], 1)
        self.assertEqual(result['chineseWithoutLatin'], 0)
