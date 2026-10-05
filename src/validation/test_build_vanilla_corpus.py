import tempfile
import unittest
from pathlib import Path
from build_vanilla_corpus import collect, select


class CorpusTests(unittest.TestCase):
    def test_legacy_raw_bytes_do_not_drop_an_entire_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'vanilla_creatures' / 'objects'
            folder.mkdir(parents=True)
            (folder / 'raw.txt').write_bytes(b'comment \xf8\n[NAME:fox:foxes:vulpine]\n')
            self.assertEqual(collect(root)['creatures'], {'fox', 'foxes', 'vulpine'})

    def test_exact_spacing_long_descriptions_and_all_inline_fields_survive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'vanilla_creatures' / 'objects'
            folder.mkdir(parents=True)
            description = 'A creature.  ' + 'It wanders far. ' * 30
            (folder / 'creature.txt').write_text(
                '[NAME:dog:dogs:canine][PREFSTRING:loyalty]\n'
                f'[DESCRIPTION:{description}]\n', encoding='utf-8')
            rows = collect(root)
            self.assertEqual(rows['creatures'], {'dog', 'dogs', 'canine'})
            self.assertEqual(rows['preferences'], {'loyalty'})
            self.assertEqual(rows['creature_descriptions'], {description.strip()})

    def test_text_headers_and_unexpanded_runtime_slots_are_not_queries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = root / 'vanilla_text' / 'objects'
            folder.mkdir(parents=True)
            (folder / 'text.txt').write_text(
                'File header\n[OBJECT:TEXT_SET]\n[TEXT_SET:GREET]\n'
                'Greetings.  My name is [SPEAKER:TRANS_NAME].\n'
                'A baby!  How adorable!\n', encoding='utf-8')
            self.assertEqual(collect(root), {'text_literals': {'A baby!  How adorable!'}})

    def test_selection_does_not_depend_on_dictionary_hits_or_input_order(self):
        forward = {'a': {'known', 'unknown'}, 'b': {'third'}}
        reverse = dict(reversed(list(forward.items())))
        self.assertEqual(select(forward, 120), select(reverse, 120))
        self.assertEqual(len(select(forward, 120)), 3)


if __name__ == '__main__':
    unittest.main()
