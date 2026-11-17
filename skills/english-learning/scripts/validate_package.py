"""Portable structural checks; optional original-media and macOS app checks."""
import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def compact(value):
    return ''.join(value.split())


def validate(word, video=None, ffprobe='ffprobe'):
    with zipfile.ZipFile(word) as z:
        root = ET.fromstring(z.read('customXml/english-practice.xml'))
        require(root.tag == '{urn:english-practice:lesson:v1}lesson' and root.get('version') == '1', 'Unsupported lesson version')
        d = json.loads(root.text)
        xml = ET.fromstring(z.read('word/document.xml'))
        visible = compact(''.join(xml.itertext()))
    require(re.fullmatch(r'[a-fA-F0-9]{64}', d['videoSHA256']) is not None, 'Invalid SHA256')
    duration = d['videoDuration']
    require(isinstance(duration, (int, float)) and math.isfinite(duration) and duration > 0, 'Invalid duration')
    def interval(item):
        a, b = item['start'], item['end']
        require(all(isinstance(t, (int, float)) and math.isfinite(t) for t in (a, b)) and 0 <= a < b <= duration, 'Invalid time: '+item['id'])
    def unique(items):
        ids = [x['id'] for x in items]
        require(len(ids) == len(set(ids)) and all(ids), 'Duplicate/empty IDs')
    for name in ('paragraphs', 'sentences', 'learningPoints'):
        require(bool(d[name]), 'Empty '+name)
        unique(d[name])
    ss = {s['id']: s for s in d['sentences']}
    last = -1
    for s in ss.values():
        interval(s)
        require(s['start'] >= last, 'Overlapping or unordered sentences')
        last = s['end']
        require(s['en'].strip() and s['zh'].strip(), 'Missing bilingual sentence')
        require(compact(s['en']) in visible and compact(s['zh']) in visible, 'Sentence absent from visible Word')
    covered = []
    for p in d['paragraphs']:
        interval(p)
        group = [ss[x] for x in p['sentenceIDs']]
        require(bool(group) and all(s['paragraph'] == p['id'] for s in group), 'Paragraph membership mismatch')
        require(p['start'] == group[0]['start'] and p['end'] == group[-1]['end'], 'Paragraph timing mismatch')
        for key in ('en', 'zh'):
            require(compact(p[key]) == compact(''.join(s[key] for s in group)), 'Paragraph text mismatch')
            require(compact(p[key]) in visible, 'Paragraph absent from visible Word')
        covered.extend(p['sentenceIDs'])
    require(covered == list(ss), 'Paragraphs must cover sentences exactly once in order')
    for point in d['learningPoints']:
        s = ss[point['sentenceID']]
        require(point['category'] in ('核心单词', '核心词组', '核心句式'), 'Unknown category')
        require(point['term'] and point['meaning'], 'Missing term/meaning')
        for key, source in (('sentenceEn', 'en'), ('sentenceZh', 'zh'), ('start', 'start'), ('end', 'end')):
            require(point[key] == s[source], 'Learning point differs from full sentence: '+point['id'])
        for key in ('term', 'meaning', 'sentenceEn', 'sentenceZh'):
            require(compact(point[key]) in visible, 'Learning point absent from visible Word')
        if point['category'] == '核心单词':
            require(point['ipa'] and point['pos'], 'Missing IPA/POS')
    for s in ss.values():
        label = lambda t: f'{int(t)//60:02}:{t%60:05.2f}'
        require(label(s['start'])+'–'+label(s['end']) in visible, 'Missing visible sentence time')
    if video:
        require(d.get('timingStatus') != 'synthetic-demo', 'Demo times cannot validate a real video')
        h = hashlib.sha256()
        with Path(video).open('rb') as f:
            for block in iter(lambda: f.read(1024*1024), b''):
                h.update(block)
        require(h.hexdigest() == d['videoSHA256'].lower(), 'Wrong original video fingerprint')
        if shutil.which(ffprobe):
            raw = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(video)], text=True))
            streams = [s for s in raw['streams'] if s['codec_type'] == 'audio']
            require(bool(streams), 'No audio stream')
            audio = streams[0]
            require('duration' in audio, 'Audio duration unavailable; verify media with another probe')
            probe = dict(duration=float(raw['format']['duration']), audioStart=float(audio.get('start_time', 0)), audioDuration=float(audio['duration']))
        elif sys.platform == 'darwin' and shutil.which('swift'):
            probe = json.loads(subprocess.check_output(['swift', '-module-cache-path', str(Path(tempfile.gettempdir())/'english-skill-swift-cache'), str(Path(__file__).with_name('media_probe.swift')), str(video)], text=True))
        else:
            raise ValueError('Install ffprobe (FFmpeg) for media checks; macOS can alternatively use Swift')
        require(abs(probe['duration'] - duration) <= .1, 'Video duration mismatch')
        require(abs(probe['audioStart']) < .001, 'Nonzero audio origin: align to the original video timeline before delivery')
        require(max(s['end'] for s in ss.values()) <= probe['audioDuration'], 'Sentence exceeds playable audio')
    return d


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('word', type=Path)
    parser.add_argument('--video', type=Path)
    parser.add_argument('--ffprobe', default='ffprobe')
    parser.add_argument('--app-source', type=Path, help='Optional directory containing the compatible Swift app sources (macOS)')
    a = parser.parse_args()
    try:
        d = validate(a.word, a.video, a.ffprobe)
        print(f"PASS structure: {len(d['paragraphs'])} paragraphs, {len(d['sentences'])} sentences, {len(d['learningPoints'])} learning points")
        print('PASS original media' if a.video else 'NOT CHECKED: original video and real audio timing')
        if a.app_source:
            require(sys.platform == 'darwin', 'App check requires macOS')
            cmd = [sys.executable, str(Path(__file__).with_name('validate_app.py')), str(a.word), '--app-source', str(a.app_source)]
            if a.video:
                cmd += ['--video', str(a.video)]
            subprocess.run(cmd, check=True)
        else:
            print('NOT CHECKED: App import (optional)')
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, ET.ParseError, subprocess.CalledProcessError) as e:
        parser.exit(1, f'FAIL: {e}\n')


if __name__ == '__main__':
    main()
