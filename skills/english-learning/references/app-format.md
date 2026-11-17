# 学习数据协议与可选 App 兼容

原创最小示例见 `examples/demo-lesson.json`。示例时间为虚构演示值，不对应真实视频。通用 Word 使用相同结构，App 专用限制仅在兼容模式应用。

DOCX ZIP 必须含 `customXml/english-practice.xml`：根元素 `{urn:english-practice:lesson:v1}lesson`，属性 `version="1"`，文本为完整 JSON（XML转义，不嵌套JSON元素）。脚本创建对应 relationship。只有可见时间表不够。

JSON字段：
- title、sourceVideo、videoSHA256（原始视频64位十六进制SHA256）、videoDuration（视频秒数）。
- paragraphs：id、title、sentenceIDs、en、zh、start、end。
- sentences：id、paragraph（所属段落ID）、en、zh、start、end。按视频顺序。
- learningPoints：id、category（核心单词/核心词组/核心句式）、number、term、ipa、pos、meaning、sentenceID、sentenceEn、sentenceZh、start、end。词组/句式的 ipa 和 pos 为 ""，不可缺字段。
- languageNotes：可空数组；条目含 sentenceID、original、suggestion、explanation。
- alignmentMethod：如实记录时间依据。可增加 timingStatus、sourceDifferences 等证据字段。
- pageBreakBeforeParagraphs：可选，1起始段落序号数组，仅排版使用。

ID各组唯一稳定，建议P01/S001/W01/F01/T01。全部正文句子必须被段落按顺序恰好覆盖一次；段落英文为子句用空格拼接、中文为子句拼接，忽略空白后须一致。段落开始=首句开始，结束=末句结束；段落不重叠；句子开始时间递增且完全落在所属段落。

每项学习要点的英文/中文例句与引用句完全一致（忽略空白），起止时间也直接复制。不要把例句并入 meaning。以“字母单词、统一小写、去标点”规范化后相同的英文若位于不同时间，当前导入器拒绝；应基于连续真实上下文重新组织练习单元，不编造。

所有时间为相对于原视频起点的秒数，必须有限、0<=start<end，结束不超过视频和实际音轨时长。App限制20分钟、600MB，最多200段、2000句、1000要点。超限先向用户解释，不静默裁剪视频后套用原指纹。

可见表格显示时间 MM:SS.ss，区间分隔为 en dash（–）；段落行依次ID/主题/时间，句子行依次ID/时间/英文。App校验可见文本与内嵌数据，因此时间格式及字段必须由同一个数据对象生成。若视频重编码/剪辑/照片导出改变字节，指纹会不同；交付时提醒使用同一原文件。

此 skill 可独立使用；整套分享包提供 app/EnglishPractice 源码。可用 `scripts/validate_package.py WORD --video VIDEO --app-source DIR` 在 macOS 上校验；目录须包含 Models.swift、OriginalModels.swift、WordImport.swift，接口匹配英语随身练 0.6.0。其他版本可能需要适配，不能将未运行或接口不兼容表述为通过。
