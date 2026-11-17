"""Render with a supplied Documents renderer or LibreOffice and pdftoppm."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('word', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--renderer', type=Path, help='Optional external render_docx.py')
p.add_argument('--soffice', default='soffice', help='LibreOffice executable name or path')
p.add_argument('--pdftoppm', default='pdftoppm')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
if any(a.output.iterdir()):
    p.error('Preview directory must be empty; use a new directory to avoid stale pages')
with tempfile.TemporaryDirectory(prefix='english-render-') as folder:
    tmp = Path(folder)
    env = os.environ.copy()
    if sys.platform == 'darwin':
        fonts = [Path('/System/Library/Fonts'), Path('/System/Library/Fonts/Supplemental'), Path('/Library/Fonts'), Path.home()/'Library/Fonts']
        config = tmp/'fonts.conf'
        config.write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd"><fontconfig>'+''.join('<dir>'+escape(str(f))+'</dir>' for f in fonts if f.exists())+'<cachedir>'+escape(str(tmp/'cache'))+'</cachedir></fontconfig>', encoding='utf-8')
        env['FONTCONFIG_FILE'] = str(config)
    if a.renderer:
        subprocess.run([sys.executable, str(a.renderer), str(a.word.resolve()), '--output_dir', str(a.output.resolve())], env=env, check=True)
    else:
        if not shutil.which(a.soffice) or not shutil.which(a.pdftoppm):
            p.error('Install LibreOffice and Poppler, provide --soffice/--pdftoppm paths, or use --renderer')
        subprocess.run([a.soffice, '-env:UserInstallation='+ (tmp/'profile').as_uri(), '--headless', '--convert-to', 'pdf', '--outdir', str(tmp), str(a.word.resolve())], env=env, check=True)
        pdf = tmp/(a.word.stem+'.pdf')
        if not pdf.exists():
            p.error('LibreOffice did not produce a PDF')
        subprocess.run([a.pdftoppm, '-png', '-r', '120', str(pdf), str(a.output.resolve()/'page')], check=True)
    if not list(a.output.glob('*.png')):
        p.error('Renderer did not produce page PNGs')
print('Pages rendered to', a.output)
