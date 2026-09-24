# TodoList

面向 Windows 11 与 Android 的轻量 TodoList。当前版本采用本地优先设计：任务数据保存在设备本地 SQLite 数据库中，无需账号或网络即可使用。

当前版本：`1.1.0`

## 当前已实现

- 创建、编辑、完成与移入回收站：任务支持必填标题，以及可选备注和截止日期。
- 应用内回收站：支持恢复、单个或批量永久删除；进入回收站满 30 天自动清除。
- 排序：可按创建时间、标题字典序或截止时间排序；无截止时间的任务在截止时间排序中排在最后。拖动任务会切换为手动排序，顺序在正常退出应用后保存。
- Windows 桌面固定模式：最多显示 5 条任务，可拖动整个窗口、调整大小、临时隐藏本次固定模式中的任务，以及切换始终置顶。
- Windows 系统托盘：关闭窗口时应用隐藏到托盘并从任务栏移除；托盘菜单可重新打开或彻底退出应用。
- Windows 安装包：Inno Setup 7 安装向导支持开始菜单、可选桌面快捷方式、卸载和 Visual C++ 运行库检测。
- Android 交互：点击任务主体编辑，点击勾选框完成，长按任务拖动排序；标题栏适配状态栏安全区并提供回收站入口。

## 暂未实现

- 邮箱注册/登录、MySQL 云端存储、同账号多设备同步。
- 子任务与附件的编辑界面及文件管理。
- 通知、账号间共享、导入导出和应用商店发布。

已确定的后续云端方案为 Node.js + Fastify + Prisma + MySQL，邮件验证使用 Nodemailer + SMTP；详见 [docs/00-待确认决策.md](./docs/00-待确认决策.md)。

## 技术栈

- Flutter + Dart：Windows 与 Android 共用应用代码。
- Drift + SQLite：本地任务、清单与附件元数据。
- window_manager、tray_manager：Windows 窗口、桌面固定和系统托盘。
- fluentui_system_icons：Windows 端固定/取消固定图标。
- Inno Setup 7：Windows x64 安装包。

## 开发启动

开发环境需要 Flutter stable、Android Studio/Android SDK，以及 Visual Studio 的“使用 C++ 的桌面开发”组件。

~~~powershell
flutter doctor -v
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run -d windows
~~~

Android 设备连接或启动模拟器后运行：

~~~powershell
flutter run -d android
~~~

## 构建

### Windows

安装 Inno Setup 7 后，在项目根目录执行：

~~~powershell
.\installer\build-installer.ps1
~~~

生成的安装包位于 `installer/output/`。安装包仅支持 x64 Windows，且会在缺少时下载并安装 Microsoft Visual C++ x64 运行库。详见 [installer/README.md](./installer/README.md)。

### Android

~~~powershell
flutter build apk --release
~~~

APK 输出位置为 `build/app/outputs/flutter-apk/app-release.apk`。首次构建需要 Gradle 下载依赖；网络不稳定时请先确认没有其他 Gradle 或 Java 进程占用同一 Gradle 下载目录。

## 文档目录

- [00-待确认决策](./docs/00-待确认决策.md)：已确认的产品与后续云端决策。
- [01-产品需求与业务流程](./docs/01-产品需求与业务流程.md)：当前 MVP 与业务流程。
- [02-技术架构与工程规范](./docs/02-技术架构与工程规范.md)：已实现架构、后续架构和工程规范。
- [03-数据模型与同步协议](./docs/03-数据模型与同步协议.md)：本地数据模型与后续同步设计。
- [04-接口与安全设计](./docs/04-接口与安全设计.md)：后续云端接口和安全设计。
- [05-开发里程碑与验收标准](./docs/05-开发里程碑与验收标准.md)：完成情况与后续验收。
- [06-开发启动与部署](./docs/06-开发启动与部署.md)：环境、测试和构建流程。

## 许可证

待项目负责人确认。
