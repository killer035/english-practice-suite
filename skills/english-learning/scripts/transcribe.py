"""Local English ASR with word timestamps; retain JSON for targeted rechecks."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('video');p.add_argument('output',type=Path)
p.add_argument('--model',default='small.en');p.add_argument('--model-cache',required=True)
a=p.parse_args()
if a.output.exists():p.error('Output exists; reuse the verified cache or choose a new output path')
from faster_whisper import WhisperModel
model=WhisperModel(a.model,device='cpu',compute_type='int8',download_root=a.model_cache,cpu_threads=6)
segments,info=model.transcribe(a.video,language='en',beam_size=5,word_timestamps=True,vad_filter=True)
result=[]
for s in segments:
 result.append(dict(start=s.start,end=s.end,text=s.text,words=[dict(text=w.word,start=w.start,end=w.end,probability=w.probability) for w in s.words or []]))
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
print(f'Saved {len(result)} ASR segments; compare with subtitles and review uncertain boundaries.')
