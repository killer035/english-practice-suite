import json,zipfile,hashlib
from pathlib import Path
from docx import Document
from docx.shared import Inches,Pt,RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.table import WD_TABLE_ALIGNMENT,WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
import argparse
ap=argparse.ArgumentParser(description="Build a bilingual learning Word with embedded lesson data")
ap.add_argument("data",type=Path);ap.add_argument("output",type=Path)
ap.add_argument("--font", default="Noto Sans CJK SC", help="Installed font with Chinese and IPA coverage")
args=ap.parse_args()
d=json.loads(args.data.read_text(encoding="utf-8"));ss={s['id']:s for s in d['sentences']}
args.output.parent.mkdir(parents=True,exist_ok=True)
doc=Document();sec=doc.sections[0];sec.page_height=Inches(11.69);sec.page_width=Inches(8.27)
sec.top_margin=Inches(.72);sec.bottom_margin=Inches(.65);sec.left_margin=sec.right_margin=Inches(.73)
sec.header_distance=Inches(.28);sec.footer_distance=Inches(.3)
for name in ['Normal','Title','Subtitle','Heading 1','Heading 2','Heading 3']:
 st=doc.styles[name];st.font.name=args.font;st._element.get_or_add_rPr().rFonts.set(qn('w:eastAsia'),args.font);st.font.color.rgb=RGBColor(0,0,0)
 st.paragraph_format.space_after=Pt(7)

for st in doc.styles:
 for el in list(st._element.iter(qn('w:pBdr'))):el.getparent().remove(el)
 for el in list(st._element.iter(qn('w:color'))):
  el.set(qn('w:val'),'000000')
  for key in list(el.attrib):
   if key!=qn('w:val'):del el.attrib[key]
doc.styles['Normal'].font.size=Pt(11);doc.styles['Normal'].paragraph_format.line_spacing=1.18
doc.styles['Title'].font.size=Pt(24);doc.styles['Heading 1'].font.size=Pt(17);doc.styles['Heading 2'].font.size=Pt(13)
header=sec.header.paragraphs[0];header.text='英语学习  ·  视频配套学习材料';header.runs[0].font.size=Pt(9);header.runs[0].font.color.rgb=RGBColor.from_string('000000')
f=sec.footer.paragraphs[0];f.alignment=WD_ALIGN_PARAGRAPH.RIGHT
r=f.add_run();r.font.size=Pt(9);field=OxmlElement('w:fldSimple');field.set(qn('w:instr'),'PAGE');r._r.addnext(field)
def para(text,style=None,bold=False):
 p=doc.add_paragraph(style=style);r=p.add_run(text);r.bold=bold;return p
def ts(t):
 return f'{int(t)//60:02}:{t%60:05.2f}'
def page():doc.add_page_break()
def table(headers,widths):
 t=doc.add_table(rows=1,cols=len(headers));t.alignment=WD_TABLE_ALIGNMENT.CENTER;t.autofit=False
 for col,w in zip(t.columns,widths):col.width=Inches(w)
 for c,w,h in zip(t.rows[0].cells,widths,headers):c.width=Inches(w);c.text=h
 pr=t._tbl.tblPr;borders=OxmlElement('w:tblBorders')
 for edge in ['top','left','bottom','right','insideH','insideV']:
  el=OxmlElement('w:'+edge);el.set(qn('w:val'),'single');el.set(qn('w:sz'),'4');el.set(qn('w:color'),'D9D9D9');borders.append(el)
 pr.append(borders)
 margins=OxmlElement('w:tblCellMar')
 for edge in ['top','bottom','left','right']:
  el=OxmlElement('w:'+edge);el.set(qn('w:w'),'95');el.set(qn('w:type'),'dxa');margins.append(el)
 pr.append(margins)
 rep=OxmlElement('w:tblHeader');t.rows[0]._tr.get_or_add_trPr().append(rep)
 for c in t.rows[0].cells:
  shade=OxmlElement('w:shd');shade.set(qn('w:fill'),'DCE6EE');c._tc.get_or_add_tcPr().append(shade)
  for run in c.paragraphs[0].runs:run.bold=True
 t._widths=widths
 return t
def row(t,values):
 cells=t.add_row().cells
 for c,w,value in zip(cells,t._widths,values):
  c.width=Inches(w);c.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
  c.text=''
  c.paragraphs[0].add_run(value)
  for p in c.paragraphs:
   p.paragraph_format.space_after=Pt(3);p.paragraph_format.line_spacing=1.10
   for r in p.runs:r.font.size=Pt(10)
 cells[0].paragraphs[0].alignment=WD_ALIGN_PARAGRAPH.CENTER
 trpr=cells[0]._tc.getparent().get_or_add_trPr();trpr.append(OxmlElement('w:cantSplit'))
 return cells
para(d['title'],'Title')
# Body contains only aligned English/Chinese paragraph pairs; indexes follow learning points.
for n,g in enumerate(d['paragraphs'],1):
 if n in d.get("pageBreakBeforeParagraphs", []):page()
 p=para(f'{n:02}','Heading 2');p.paragraph_format.keep_with_next=True
 en=' '.join(ss[x]['en'] for x in g['sentenceIDs']);zh=''.join(ss[x]['zh'] for x in g['sentenceIDs'])
 para(en);para(zh)
page();para('核心学习要点','Heading 1')
para('核心单词','Heading 2')
t=table(['编号','单词 音标 词性','中文释义','原文例句与译文'],[.48,1.55,1.0,3.78])
for p in d['learningPoints']:
 if p['category']!='核心单词':continue
 row(t,[str(p['number']),f"{p['term']}\n{p['ipa']}\n{p['pos']}",p['meaning'],f"原文：{p['sentenceEn']}\n翻译：{p['sentenceZh']}"])
page();para('核心词组','Heading 2')
t=table(['编号','英文词组','中文释义','原文例句与译文'],[.48,1.55,1.0,3.78])
for p in d['learningPoints']:
 if p['category']=='核心词组':row(t,[str(p['number']),p['term'],p['meaning'],f"原文：{p['sentenceEn']}\n翻译：{p['sentenceZh']}"])
page();para('核心句式','Heading 2')
for p in d['learningPoints']:
 if p['category']!='核心句式':continue
 h=para(f"{p['number']}. {p['term']}",'Heading 3');h.paragraph_format.keep_with_next=True
 para('中文：'+p['meaning']).paragraph_format.keep_with_next=True
 para('原文：'+p['sentenceEn']).paragraph_format.keep_with_next=True
 para('翻译：'+p['sentenceZh'])
page();para('原文表达提示','Heading 1')
para('英文保留视频中的口语表达，仅整理大小写和标点。中文与英文按语义对应整理。下面列出学习时值得注意的用法；规范表达与视频原话分开呈现。')
for item in d.get('languageNotes',[]):
 para(item['original'],'Heading 2');para('说明或建议：'+item['suggestion']);para(item['explanation'])
para('音标说明','Heading 2');para('单词采用美式英语宽式音标。单词以词典原形列出，原文例句保留复数、动词变化等实际词形。')
page();para('音频时间索引','Heading 1')
para('对应视频：'+d['sourceVideo'])
para('请使用同一份未经重新剪辑的视频。各项时间相对于视频起点，正文段落与学习例句均有对应记录。'+('时间依据：'+d.get('alignmentMethod', '未提供，不能视为已校验发声时间。')+'；切点建议试听确认。'))
para('段落索引','Heading 2')
t=table(['段落','主题','起止时间'],[.6,3.91,2.3])
for g in d['paragraphs']:
 first=ss[g['sentenceIDs'][0]];last=ss[g['sentenceIDs'][-1]]
 row(t,[g['id'],g['title'],ts(first['start'])+'–'+ts(last['end'])])
para('句子索引','Heading 2')
t=table(['编号','起止时间','对应英文'],[.55,1.4,4.86])
for s in d['sentences']:
 row(t,[s['id'],ts(s['start'])+'–'+ts(s['end']),s['en']])
file=args.output;doc.save(file)
# Embed a versioned complete lesson payload for future deterministic app import.
payload=json.dumps(d,ensure_ascii=False,separators=(',',':'))
import xml.etree.ElementTree as ET
ns='urn:english-practice:lesson:v1';el=ET.Element('{'+ns+'}lesson',{'version':'1'});el.text=payload
with zipfile.ZipFile(file,'r') as z:parts={n:z.read(n) for n in z.namelist()}
relNS='http://schemas.openxmlformats.org/package/2006/relationships'
ET.register_namespace('',relNS)
rels=ET.fromstring(parts['word/_rels/document.xml.rels'])
ET.SubElement(rels,'{'+relNS+'}Relationship',{'Id':'rIdEnglishPractice','Type':'http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml','Target':'../customXml/english-practice.xml'})
parts['word/_rels/document.xml.rels']=ET.tostring(rels,encoding='utf-8',xml_declaration=True)
parts['customXml/english-practice.xml']=ET.tostring(el,encoding='utf-8',xml_declaration=True)
with zipfile.ZipFile(file,'w',zipfile.ZIP_DEFLATED) as z:
 for name,body in parts.items():z.writestr(name,body)
print(file)
