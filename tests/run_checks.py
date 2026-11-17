"""Run local package checks on macOS; never installs to a phone."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
app = root/'app/EnglishPractice'
skill = root/'skills/english-learning'
with tempfile.TemporaryDirectory(prefix='english-suite-check-') as folder:
    tmp = Path(folder)
    subprocess.run(['swiftc', '-module-cache-path', str(tmp/'modules'), str(app/'Models.swift'), str(app/'OriginalModels.swift'), str(root/'tests/main.swift'), '-o', str(tmp/'seed-check')], check=True)
    subprocess.run([str(tmp/'seed-check'), str(app/'lesson.json')], check=True)
    subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(skill/'tests'), '-v'], check=True)
    word = tmp/'demo.docx'
    subprocess.run([sys.executable, str(skill/'scripts/build_word.py'), str(skill/'examples/demo-lesson.json'), str(word)], check=True)
    subprocess.run([sys.executable, str(skill/'scripts/validate_package.py'), str(word), '--app-source', str(app)], check=True)
