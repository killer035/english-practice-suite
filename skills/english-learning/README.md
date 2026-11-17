# English Learning · 英语视频学习稿

一个面向 Codex 的英语学习 skill：将用户提供的视频整理为中英分段原稿、完整原句时间索引、核心单词 / 词组 / 句式，并输出 Word 学习稿。

这是一套由 AI 助手执行的制作流程及辅助脚本，**不是单条命令即可自动完成翻译、校对与对齐的独立应用**。原声时间由音频识别提供依据，仍需检查；Word 本身不含视频，也不会自动播放原声。

## 输出内容

- 按语义对应的英文原话与中文译文。
- 核心单词的音标、词性和释义；词组、句式及其释义。
- 每项学习要点所在的**完整原句**和译文。
- 段落、句子的原声起止时间和原视频指纹。
- 原话中的非标准用法与规范建议分开列示。
- 可选对接“英语随身练”的内嵌数据。此 skill 目录不包含 App；整套分享包中的 App 位于 ../../app。

## 安装为 skill

下载或克隆此仓库，将包含 `SKILL.md` 的整个目录命名为 `english-learning`，放进你的 Codex skills 目录（通常为 `~/.codex/skills/english-learning`；配置了 `CODEX_HOME` 时使用对应目录）。若已有同名 skill，先比较或备份，不直接覆盖。

在新会话中调用：

> 请调用 $english-learning，处理我提供的英语视频。生成中英学习稿、核心要点和完整原句时间，保存到我指定的输出目录。

也可使用中文“调用英语学习”。提供本机可访问的视频路径或附件。首次运行由助手检查依赖、模型与输出位置。

## 环境与依赖

建议 Python 3.10 或以上，使用独立虚拟环境。以下命令在仓库根目录执行：

```bash
python -m venv .venv
# macOS / Linux
source .venv/bin/activate
# Windows PowerShell 则使用 .venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
# 需要本地语音识别时：
python -m pip install -r requirements-asr.txt
```

| 功能 | 依赖与限制 |
| --- | --- |
| Word 生成、结构检查 | Python + python-docx；无需 App |
| 本地逐词识别 | faster-whisper；首次使用模型名称会下载模型，或用已下载的本地模型路径；CPU int8 默认，无需 API 密钥 |
| 视频指纹与音轨检查 | FFmpeg 的 ffprobe；macOS 可回退到 Swift / AVFoundation |
| 烧录字幕 OCR | 附带脚本仅支持 macOS Vision + Swift；Windows / Linux 需自行提供 OCR 工具或可用字幕 |
| 全页预览 | LibreOffice + Poppler（pdftoppm）；也可指定已有 Documents render_docx.py |
| 中文及音标字体 | 默认 Noto Sans CJK SC；自行安装字体，或 `--font` 改用本机字体，检查 IPA 是否缺字 |
| 实际 App 导入校验（可选） | macOS + Swift 编译工具、兼容的 App 源文件 |

Swift 可由 Xcode Command Line Tools 提供。工具可安装到任意位置；通过 PATH 或参数指定。模型、字体、LibreOffice、FFmpeg 和 Poppler 不随本仓库分发，各自遵循其许可证。

**验证范围：本地 macOS 实测；Windows / Linux 的 Python 路径已做可移植设计，但尚未端到端实测。** 不把 macOS OCR 或 App 检查宣称为跨平台能力。

## 不用视频也能试运行

`examples/demo-lesson.json` 是原创的两句英语示例。所有时间和指纹都是演示值，不对应真实录音。用它检查安装、版式和数据结构：

```bash
python scripts/build_word.py examples/demo-lesson.json output/demo.docx
python scripts/validate_package.py output/demo.docx
python scripts/render_word.py output/demo.docx output/preview
```

结构检查成功会明确显示“原视频未检查”和“App 未检查”。不要把演示稿作为真实原声配套稿。

如字体或工具不在默认位置：

```bash
python scripts/build_word.py examples/demo-lesson.json output/demo.docx --font "YOUR_INSTALLED_FONT"
python scripts/render_word.py output/demo.docx output/preview-new --soffice /path/to/soffice --pdftoppm /path/to/pdftoppm
# 或使用自己已有的 Documents 渲染器：
python scripts/render_word.py output/demo.docx output/preview-documents --renderer /path/to/render_docx.py
```

预览目录须为空，以免旧页混入新结果。

## 处理真实视频

1. 助手读取 `SKILL.md` 及引用文档，确认视频、缓存及工具。
2. 本地识别音频，提取字幕，核对差异，翻译并按完整语义组织句子。
3. 使用真实逐词时间对齐，生成一份权威 `lesson.json`；所有要点引用该文件中的完整句子。
4. 生成 Word，检查结构和媒体，再渲染每页检查版式，最后交付。

辅助命令示例（路径自行替换）：

```bash
python scripts/transcribe.py input.mp4 work/asr.json --model small.en --model-cache models
# macOS 烧录字幕 OCR：
swift scripts/ocr_video.swift input.mp4 work/ocr.json
python scripts/build_word.py work/lesson.json output/lesson.docx
python scripts/validate_package.py output/lesson.docx --video input.mp4
```

先创建 `work` 目录。`transcribe.py` 不覆盖现有识别文件；复用缓存时核对视频指纹。语音识别输出不会自动成为最终 lesson.json，仍由助手完成校对、翻译、要点提炼与时间对齐。现有音轨探测若不能取得可靠时长，校验会停止；不要通过删检查来冒充通过。

### 可选：英语随身练兼容校验

默认不用提供 App。若拥有兼容源代码：

```bash
python scripts/validate_package.py output/lesson.docx --video input.mp4 --app-source /path/to/EnglishPractice
```

该目录须包含 `Models.swift`、`OriginalModels.swift`、`WordImport.swift`，接口需匹配英语随身练 0.6.0；新版本可能需适配。此模式检查实际导入与完整原句出题，受 App 的20分钟、600 MB等限制。通用 Word 模式不套用这些 App 限制。该操作不会安装或修改 App。

## 隐私与内容范围

- 默认在本地处理视频，不需要云端转写密钥。首次模型下载需要联网，但本地识别不上传视频。
- 如改用外部服务，先向用户说明上传内容并获得授权。
- 不提交个人视频、转写缓存、生成稿、模型、环境文件及密钥；`.gitignore` 仅作辅助，不替代提交前检查。
- 本目录不含私人学习记录、真实视频样稿、专有字体或模型权重。
- 仅分享有权公开的素材。示例句为本项目原创，时间明确标为演示值。

## 验证与贡献

```bash
python -m unittest discover -s tests -v
```

详见 [本次本地验证记录](VALIDATION.md)。修复时优先保持原句、时间、可见 Word 与内嵌 JSON 一致；新平台支持请注明实际测试环境。

## 许可证

本地发布准备版采用 MIT 许可证，见 [LICENSE](LICENSE)。发布前由仓库所有者最终确认。第三方依赖、用户视频及其他素材不因使用此工具自动改为 MIT 授权。

## 整套分享包的 App

配套源码见 [app 目录](../../app)，面向新手的操作见 [整套使用说明](../../README.md)。在本 skill 目录运行兼容性检查时，App 源码参数可使用 `--app-source ../../app/EnglishPractice`。
