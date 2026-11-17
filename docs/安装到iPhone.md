# 用自己的 Xcode 安装到 iPhone

按顺序操作即可，无需改动 App 功能代码。你需要一台能运行 Xcode 的 Mac、一部 iOS 17 或以上的 iPhone、数据线和自己的 Apple 账号；仅有 iPhone 无法完成下面的安装。

## 1. 准备 Xcode

在 Mac 上安装 Xcode，首次启动时按提示完成组件安装，并安装 iOS 平台支持。Xcode 需要支持你手机当前的 iOS 版本；若设备显示“不支持”，先按提示更新 Xcode 或下载相应组件。

将分享包完整解压到一个普通文件夹。不要在 ZIP 内直接打开工程，也不要只复制一个 `.xcodeproj` 文件；旁边的 `EnglishPractice` 源码目录要保留。

## 2. 打开工程

进入解压后的 `app` 文件夹，双击 **EnglishPractice.xcodeproj**。

看到左侧文件列表后，点击最上面的蓝色 **EnglishPractice** 工程图标。中间找到 **TARGETS**，选择 **EnglishPractice**，不要选 `EnglishPracticeUITests`。

## 3. 登录自己的账号并选择签名

1. Mac 顶部菜单打开 **Xcode → Settings → Apple Accounts**（旧版本可能显示 Accounts）。
2. 点“＋”添加自己的 Apple 账号；密码和验证码只在 Apple 界面输入。
3. 回到工程的 **EnglishPractice target → Signing & Capabilities**。
4. 勾选 **Automatically manage signing**。
5. 在 **Team** 中选择自己的账号或 Personal Team。分享工程的 Team 留空是正常的，需要你自己选。
6. 把 **Bundle Identifier** 的 `org.example.englishpractice` 改成你自己的唯一标识，例如 `com.lily.englishpractice2026`。用英文字母、数字和点，不用中文或空格；示例若已被占用，换一个。
7. 等待 Xcode 完成签名准备。若要求注册设备，按提示操作。

第一次选好之后记住 Team 和 Bundle Identifier，今后更新尽量保持一致，便于覆盖安装并保留已有数据。自动签名和个人 Team 的操作可参阅 [Apple 签名说明](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html)。

## 4. 连接手机

用数据线连接 Mac 和 iPhone，解锁手机；出现“信任此电脑？”时，点击信任并输入手机解锁密码。

在 Xcode 顶部选择运行方案 **EnglishPractice**，旁边设备选自己的 **iPhone 名称**，不要选模拟器或 `Any iOS Device`。

如果提示需要开发者模式，在 iPhone 打开 **设置 → 隐私与安全性 → 开发者模式**，打开后按提示重启并确认。若暂时找不到该选项，先完成与 Xcode 的设备连接，再查看。参阅 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

## 5. 点击运行

点击 Xcode 左上角三角形 **Run**，或按 **Command + R**。首次编译可能需要等待，保持手机解锁并连接。

成功后 Xcode 会把 App 安装到手机并尝试启动。首页应出现“每日英语练习”。若设备不可用，先看 Xcode 对该设备给出的具体原因。[Apple 真机运行说明](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)

## 6. 如果提示开发者不受信任

只有出现此提示时才需要操作：

1. 在 iPhone 打开 **设置 → 通用 → VPN 与设备管理**。
2. 找到“开发者 App”下与你刚才签名账号对应的项目。
3. 点击“信任”，按系统提示确认；验证时保持联网。
4. 返回桌面打开“英语随身练”；或回 Xcode 再按一次 Run。

不要信任来历不明的配置。这一步信任的是你刚才用自己的账号安装的 App。菜单名称可能随系统版本略有差异。

## 7. 第一次试用

- 打开“每日英语练习”，进入“原文阅读”，查看中文与英文。
- 录制一句自己的英语；允许麦克风后停止录音，在“我的录音与回听”确认能播放。
- 打开“随机抽题”，检查三个核心要点与两道完整原句题。
- 入门示例未附视频，原声按钮会提示缺少原声；这不代表安装失败。添加自己的课程后才有对应视频原声。

## 以后突然打不开怎么办

个人签名存在有效期和设备/能力限制，可能需要重新运行。实际限制以 Xcode 及 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 为准。

1. 先备份，**不要先删除手机里的 App**。
2. 用同一台 Mac 打开这份工程，连接手机。
3. 确认仍用原来的 Team 和 Bundle Identifier。
4. 选自己的 iPhone，再按 Run，覆盖安装。
5. 若明确提示证书未信任，按第6节操作。
6. 打开后核对旧文稿和录音是否仍在。

## 常见问题

| 提示或现象 | 处理 |
| --- | --- |
| Signing requires a development team | 在 App target 的 Signing & Capabilities 里选择 Team |
| Bundle Identifier 不可用 | 换成自己唯一的英文标识；已有安装更新时先确认原标识，别随意换 |
| 看不到手机 | 解锁、检查数据线、信任电脑，再看 Xcode 的设备窗口 |
| Developer Mode disabled | 按第4节开启开发者模式 |
| Developer App Certificate is not trusted | 按第6节在手机信任对应开发者 |
| 系统版本不受支持 | 更新到支持手机系统的 Xcode，并安装所需 iOS 组件 |
| 无法录音 | 在 iPhone 设置中找到 App，检查麦克风权限 |
| 检测到旧数据但无法读取 | 先完整备份，不删除文件或反复覆盖，记录错误后排查 |

安装 App 的普通用户只需选择 EnglishPractice 方案；EnglishPracticeChecks 用于开发测试，不是安装必选步骤。
