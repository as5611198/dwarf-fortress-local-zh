"""Score human-reviewed complete UI units, never infer quality from CJK hits.

Input: {"schema": 1, "units": [...]}. Evidence/visibility review belongs to the
ledger author. This arithmetic report alone never establishes release safety.
"""
import argparse
import json
from pathlib import Path

CATEGORIES = (
    'fortress/construction-jobs', 'fortress/stocks-trade',
    'fortress/residents-health', 'fortress/military', 'fortress/announcements',
    'legends/navigation', 'legends/figures', 'legends/sites-entities',
    'legends/artifacts', 'legends/events',
    'adventure/creation', 'adventure/exploration', 'adventure/conversation',
    'adventure/combat-status', 'adventure/journal',
)
RESULTS = {'success', 'miss', 'partial', 'pending', 'incorrect', 'unverified'}
COHORTS = {'holdout', 'regression', 'baseline-development'}


def summarize(units):
    counts = {stage: {c: {'units': 0, 'success': 0} for c in CATEGORIES}
              for stage in ('settled', 'firstDisplay')}
    seen, non_holdout = set(), 0
    for unit in units:
        category, source = unit['category'], unit['source']
        if category not in CATEGORIES or not isinstance(source, str) or not source.strip():
            raise ValueError('invalid category or complete source')
        key = (category, source)
        if key in seen:
            raise ValueError(f'duplicate linguistic unit: {key!r}')
        seen.add(key)
        cohort = unit['cohort']
        if cohort not in COHORTS:
            raise ValueError(f'invalid cohort: {cohort!r}')
        for stage in counts:
            if unit[stage] not in RESULTS:
                raise ValueError(f'invalid assessment: {unit[stage]!r}')
        if cohort != 'holdout':
            non_holdout += 1
            continue
        for stage in counts:
            counts[stage][category]['units'] += 1
            counts[stage][category]['success'] += unit[stage] == 'success'
    incomplete = [c for c in CATEGORIES if counts['settled'][c]['units'] < 30]
    result = {'scope': 'Equal-mode/equal-category representative UI benchmark; not exhaustive whole-game coverage.',
              'incomplete': incomplete, 'nonHoldout': non_holdout}
    for stage, categories in counts.items():
        for values in categories.values():
            n = values['units']
            values['rate'] = values['success'] / n if n else None
        modes = {mode: (sum(categories[c]['rate'] for c in CATEGORIES if c.startswith(mode + '/')) / 5
                        if all(categories[c]['units'] >= 30 for c in CATEGORIES if c.startswith(mode + '/')) else None)
                 for mode in ('fortress', 'legends', 'adventure')}
        result[stage] = {'categories': categories, 'modes': modes,
                         'overall': sum(modes.values()) / 3 if not incomplete else None}
    result['ready'] = not incomplete and all(result[s]['overall'] >= .9 for s in counts)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ledger', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    ledger = json.loads(args.ledger.read_text(encoding='utf-8'))
    if ledger.get('schema') != 1:
        raise ValueError('unsupported ledger schema')
    result = summarize(ledger['units'])
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(text, encoding='utf-8')
    else:
        print(text, end='')


if __name__ == '__main__':
    main()
