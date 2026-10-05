"""Validate a local offline acceptance run before calling it in-world evidence."""
from collections import Counter
import math
import re


def validate(report, expected, corpus, saves):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require(report.get('schema') == 2 and report.get('status') == 'passed', 'Incomplete probe')
    for field in ['runId', 'version', 'world']:
        require(bool(expected.get(field)) and report.get(field) == expected[field], f'Wrong {field}')
    require(report.get('startedAt') == expected['startedAt'] and
            report.get('finishedAt', 0) >= expected['startedAt'], 'Stale run')
    def in_world(row):
        return (row.get('worldLoaded') is True and row.get('mapLoaded') is True and
                row.get('world') == expected['world'] and
                re.match(r'^dwarfmode(?:/|$)', row.get('focus', '')) and row.get('apiEnabled') is False)
    require(in_world(report), 'Probe did not run in the expected fortress')
    if report['checks'] < 210 or report['failures'] or report.get('error'):
        raise ValueError('Live probe must pass')
    if report['apiEnabled'] is not False or report['version'] != expected['version']:
        raise ValueError('Wrong version or AI mode')
    wanted = Counter((page, language, source) for language in ['zh-Hant', 'zh-Hans']
        for page, entry in corpus.items() for source in entry['sources'] if re.search('[A-Za-z]', source))
    samples = report.get('samples', [])
    require(Counter((s.get('page'), s.get('language'), s.get('source')) for s in samples) == wanted,
            'Corpus samples missing, duplicated, or unexpected')
    require(report['checks'] == len(samples), 'Wrong sample count')
    require(all(isinstance(s.get('translation'), str) and s['translation'].strip() and
                any('\u3400' <= c <= '\u9fff' for c in s['translation']) for s in samples), 'Missing Chinese')
    require(report.get('negativeChecks', 0) >= 1, 'Negative control did not pass')
    fps = report.get('fps', [])
    require(len(fps) >= 6 and all(in_world(s) for s in fps), 'Missing in-world FPS evidence')
    require(all(isinstance(s.get('render'), (int, float)) and math.isfinite(s['render']) and
                s['render'] > 0 for s in fps), 'Invalid FPS')
    ticks = [s.get('tick', -1) for s in fps]
    require(all(b > a for a, b in zip(ticks, ticks[1:])) and ticks[-1] - ticks[0] >= 4000,
            'Frozen or insufficient sample interval')
    require(saves.get('baselineRunId') == expected['runId'] and saves.get('protectedFiles', 0) > 0,
            'Missing current save baseline')
    require(all(saves.get(k) == [] for k in ['changed', 'missing', 'added', 'unexpected']),
            'Protected saves changed; release validation blocked')


if __name__ == '__main__':
    import argparse
    import json
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_directory', type=Path)
    args = parser.parse_args()
    def read(name):
        return json.loads((args.run_directory / name).read_text(encoding='utf-8'))
    validate(read('live-probe.json'), read('expected.json'), read('audit-corpus.json'), read('save-verification.json'))
    print('PASS: current run, loaded fortress, complete bilingual corpus, timed FPS, protected saves unchanged')
