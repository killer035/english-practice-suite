"""Exercise generated Word and corruptions at the public package boundary."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('validator', ROOT/'scripts/validate_package.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name)
        self.data = json.loads((ROOT/'examples/demo-lesson.json').read_text(encoding='utf-8'))

    def build(self, d):
        source = self.folder/'lesson.json'
        word = self.folder/'lesson.docx'
        source.write_text(json.dumps(d, ensure_ascii=False), encoding='utf-8')
        subprocess.run([sys.executable, str(ROOT/'scripts/build_word.py'), str(source), str(word)], check=True, stdout=subprocess.DEVNULL)
        return word

    def test_demo_roundtrip(self):
        self.assertEqual(validator.validate(self.build(self.data))['sentences'], self.data['sentences'])

    def test_partial_sentence_rejected(self):
        self.data['learningPoints'][0]['sentenceEn'] = 'one useful phrase'
        with self.assertRaisesRegex(ValueError, 'full sentence'):
            validator.validate(self.build(self.data))

    def test_bad_time_rejected(self):
        self.data['sentences'][0]['end'] = 100
        with self.assertRaisesRegex(ValueError, 'Invalid time'):
            validator.validate(self.build(self.data))

    def test_paragraph_drift_rejected(self):
        self.data['paragraphs'][0]['en'] = 'Different text'
        with self.assertRaisesRegex(ValueError, 'Paragraph text'):
            validator.validate(self.build(self.data))

    def test_demo_cannot_claim_real_media(self):
        with self.assertRaisesRegex(ValueError, 'Demo times'):
            validator.validate(self.build(self.data), self.folder/'no-video.mp4')


if __name__ == '__main__':
    unittest.main()
