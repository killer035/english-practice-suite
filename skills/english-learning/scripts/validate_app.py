"""Check real Word using the app parser and (optionally) the original video."""
import argparse,hashlib,json,subprocess,tempfile,zipfile,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('word',type=Path);p.add_argument('--video',type=Path)
p.add_argument('--app-source',type=Path,required=True)
a=p.parse_args()
with zipfile.ZipFile(a.word) as z:
 root=ET.fromstring(z.read('customXml/english-practice.xml'))
 assert root.tag=='{urn:english-practice:lesson:v1}lesson' and root.attrib.get('version')=='1'
 d=json.loads(root.text)
ss={s['id']:s for s in d['sentences']}
for point in d['learningPoints']:
 s=ss[point['sentenceID']]
 assert point['start']==s['start'] and point['end']==s['end'],'Learning point time mismatch'
 if point['category']=='核心单词':assert point['ipa'] and point['pos'],'Missing IPA/POS'
if a.video:
 h=hashlib.sha256()
 with a.video.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 assert h.hexdigest()==d['videoSHA256'].lower(),'Wrong original video fingerprint'
 assert a.video.stat().st_size<=600*1024*1024,'Video exceeds app limit'
 probe=json.loads(subprocess.check_output(['swift','-module-cache-path',str(Path(tempfile.gettempdir())/'english-skill-swift-cache'),str(Path(__file__).with_name('media_probe.swift')),str(a.video)],text=True))
 assert abs(probe['duration']-d['videoDuration'])<=.1,'Video duration mismatch'
 assert probe['audioStart']==0,'Nonzero audio origin: verify extraction timeline before delivery'
 assert max(s['end'] for s in d['sentences'])<=probe['audioDuration'],'Sentence exceeds playable audio'
with tempfile.TemporaryDirectory(prefix='english-skill-check-') as tmp:
 tmp=Path(tmp)
 (tmp/'main.swift').write_text('''import Foundation
let r = try WordImport.read(URL(fileURLWithPath: CommandLine.arguments[1]))
guard let p = r.preparedLesson else { fatalError("Missing prepared data") }
let lesson = try p.makeLesson(title: r.title, chinese: r.chinese, english: r.english)
let source = try lesson.preparedAudio!.apply(to: OriginalSource(file: "check", name: "check", duration: p.videoDuration))
for seg in lesson.segments { precondition(OriginalMatching.clip(in: source, text: seg.en, preferredID: "read:" + seg.id) != nil) }
let questions = Exercises.make(lesson, mode: .draw)
for q in questions {
 let clip = OriginalMatching.clip(in: source, text: q.english)!
 let s = p.sentences.first { $0.en == q.english && $0.zh == q.chinese }!
 precondition(clip.start == s.start && clip.end == s.end)
}
print("PASS app import: \\(p.paragraphs.count) paragraphs, \\(p.sentences.count) sentences, \\(p.learningPoints.count) learning points, \\(questions.count) exact full-sentence questions")
''')
 subprocess.run(['swiftc','-module-cache-path',str(Path(tempfile.gettempdir())/'english-skill-swift-cache'),*[str(a.app_source/n) for n in ['Models.swift','OriginalModels.swift','WordImport.swift']],str(tmp/'main.swift'),'-o',str(tmp/'check')],check=True)
 subprocess.run([str(tmp/'check'),str(a.word.resolve())],check=True)
print('PASS embedded data'+(' and original video checks' if a.video else '; original video not checked'))
