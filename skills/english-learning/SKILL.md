---
name: english-learning
description: 将英语视频整理为中英分段原稿、逐句原声时间、核心单词词组句式，并生成 Word 学习稿。用户调用英语学习或要求视频配套双语学习材料时使用；可选对接英语随身练 App。
---

# 英语学习

把用户提供的视频制作成可阅读、可练习、可定位完整原句的 Word。默认本地处理，不克隆声音、不修改或安装 App。

## 流程

1. 阅读 [制作要求](references/workflow.md) 和 [数据协议](references/app-format.md)。确认视频可访问；按视频 SHA256 建立输出目录，缓存识别结果，保留原视频。工具安装见 README.md，不假设任何特定电脑路径或附加技能存在。
2. 读取内嵌字幕或对烧录字幕做 OCR，并用本地逐词音频识别交叉核对。英文以实际说话为准，保留原话；规范表达另列。中文有字幕时核对字幕，否则忠实翻译并说明来源。
3. 按语义分段，再拆为完整练习单元。用逐词音频时间对齐首尾，不能以字幕显示时间或字数估算冒充发声时间。复核重复、低置信、否定、数字及识别差异，保留证据。
4. 提炼有价值且确实出现的单词、词组、句式，每项绑定完整中英原句及时间；单词附音标和词性。数量随内容决定，不照搬示例。
5. 以一份 lesson.json 驱动所有内容。运行 `python scripts/build_word.py lesson.json output.docx`；可通过 `--font` 指定本机支持中英和音标的字体。examples/demo-lesson.json 是原创结构示例，时间仅用于演示，不可挪作真实视频时间。
6. 运行 `python scripts/validate_package.py output.docx --video INPUT_VIDEO`。默认检查数据一致性、可见正文、视频指纹及实际音轨范围，不需要 App。仅在用户要求 App 兼容性且提供源代码时，加 `--app-source APP_SOURCE_DIR`，在 macOS 上调用实际导入器。未运行时不得声称已通过 App 导入。
7. 渲染并检查全部页面。可用 `python scripts/render_word.py output.docx preview`（LibreOffice + pdftoppm），或通过 `--renderer PATH` 指定可用 Documents 渲染器。不依赖专有模板或额外技能；有 Documents 技能时可使用其排版检查流程。修改后重建并复验。
8. 交付最终 Word 链接、内容数量和实际检查范围。明确区分自动检查、局部复听与完整人工听音；不承诺100%准确。需要原声播放时提示配合同一原视频。缓存留在输出目录。

## 资源

- `references/workflow.md`：版式、识别、对齐和交付标准。
- `references/app-format.md`：通用学习数据和可选 App 兼容限制。
- `scripts/transcribe.py`：faster-whisper 本地逐词识别。
- `scripts/ocr_video.swift`：macOS Vision 帧 OCR；其他系统使用可用 OCR 并保留时间和置信度。
- `scripts/build_word.py`：生成正文、学习要点、时间索引和内嵌数据。
- `scripts/validate_package.py`：通用校验；可选调用 `validate_app.py`。
- `scripts/render_word.py`：生成逐页预览。

复用指纹匹配的缓存，只重新识别受影响区间；不省略完整原句、音标、翻译、时间依据和全页检查。缺少依赖或证据时说明缺口，不编造结果。若需要把用户视频上传外部服务，先明确告知并取得授权。
