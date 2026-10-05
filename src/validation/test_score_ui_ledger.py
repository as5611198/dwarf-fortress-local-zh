import unittest
from score_ui_ledger import summarize, CATEGORIES


def row(category, source, result='success', cohort='holdout'):
    return dict(category=category, source=source, settled=result,
                firstDisplay=result, cohort=cohort)


class LedgerScoringTests(unittest.TestCase):
    def test_missing_categories_do_not_produce_an_overall_score(self):
        result = summarize([row(CATEGORIES[0], str(i)) for i in range(30)])
        self.assertIsNone(result['settled']['overall'])
        self.assertFalse(result['ready'])
        self.assertEqual(len(result['incomplete']), 14)

    def test_partial_pending_incorrect_and_unverified_are_misses(self):
        rows = [row(c, str(i), ['success', 'partial', 'pending', 'incorrect', 'unverified'][i % 5])
                for c in CATEGORIES for i in range(30)]
        result = summarize(rows)
        self.assertAlmostEqual(result['settled']['overall'], .2)
        self.assertFalse(result['ready'])

    def test_equal_category_weights_prevent_many_easy_labels_dominating(self):
        rows = [row(c, str(i), 'miss' if c == CATEGORIES[0] else 'success')
                for c in CATEGORIES for i in range(300 if c == CATEGORIES[1] else 30)]
        result = summarize(rows)
        self.assertAlmostEqual(result['settled']['overall'], 14/15)
        self.assertTrue(result['ready'])

    def test_regressions_and_baseline_are_not_independent_acceptance_samples(self):
        rows = [row(c, str(i), cohort='regression') for c in CATEGORIES for i in range(30)]
        rows.append(row(CATEGORIES[0], 'new', cohort='baseline-development'))
        result = summarize(rows)
        self.assertIsNone(result['settled']['overall'])
        self.assertEqual(result['nonHoldout'], 451)

    def test_repeated_sources_cannot_inflate_denominator(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            summarize([row(CATEGORIES[0], 'same'), row(CATEGORIES[0], 'same')])

    def test_unknown_category_or_result_is_rejected(self):
        for item in [row('made-up', 'x'), row(CATEGORIES[0], 'x', 'contains-CJK')]:
            with self.subTest(item=item), self.assertRaises(ValueError):
                summarize([item])

    def test_first_display_is_reported_separately(self):
        rows = [dict(row(c, str(i)), firstDisplay='unverified') for c in CATEGORIES for i in range(30)]
        result = summarize(rows)
        self.assertEqual(result['settled']['overall'], 1)
        self.assertEqual(result['firstDisplay']['overall'], 0)
        self.assertFalse(result['ready'])


if __name__ == '__main__':
    unittest.main()
