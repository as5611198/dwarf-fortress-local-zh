"""Validate membership and summarize raw lookup diagnostics, never release acceptance."""
import collections
import hashlib
import json
import re
import sys
from pathlib import Path


def summarize(corpus, report):
    expected = collections.Counter((lang, page, source)
        for lang in ('zh-Hant', 'zh-Hans')
        for page, row in corpus['pages'].items() for source in row['sources'])
    actual = collections.Counter((row['language'], row['page'], row['source']) for row in report['samples'])
    if not expected or expected != actual:
        raise ValueError('Missing, extra or duplicate diagnostic rows')
    result = {}
    for lang in ('zh-Hant', 'zh-Hans'):
        groups = {}
        for page in corpus['pages']:
            rows = [row for row in report['samples'] if row['language'] == lang and row['page'] == page]
            returned = sum(isinstance(row['translation'], str) and bool(row['translation']) for row in rows)
            chinese = sum(isinstance(row['translation'], str)
                and bool(re.search('[\u3400-\u9fff\U00020000-\U000323af]', row['translation']))
                and not re.search('[A-Za-z]', row['translation']) for row in rows)
            groups[page] = {'total': len(rows), 'returned': returned, 'chineseWithoutLatin': chinese}
        total = sum(row['total'] for row in groups.values())
        returned = sum(row['returned'] for row in groups.values())
        result[lang] = {'total': total, 'returned': returned, 'returnRate': returned / total,
                        'categories': groups}
    return result


def main():
    corpus_path, broker_path, native_path, manifest_path, out_path = map(Path, sys.argv[1:])
    read = lambda path: json.loads(path.read_text(encoding='utf-8'))
    corpus, broker, native = map(read, (corpus_path, broker_path, native_path))
    if broker.get('apiRequests') != 0 or native.get('workerSubmissions') != 0:
        raise ValueError('Offline execution evidence missing')
    report = {'scope': 'Raw field and fragment diagnostic; NOT whole-game coverage or release acceptance',
        'heldOut': False, 'releaseEligible': False,
        'limitations': corpus['limitations'],
        'evidenceSha256': {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in (corpus_path, broker_path, native_path, manifest_path)},
        'broker': summarize(corpus, broker), 'nativeStatic': summarize(corpus, native)}
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({kind: {lang: {k: v for k, v in data.items() if k != 'categories'}
                            for lang, data in report[kind].items()}
                     for kind in ('broker', 'nativeStatic')}, indent=2))


if __name__ == '__main__':
    main()
