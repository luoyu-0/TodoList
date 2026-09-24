# Windows 安装包

## 构建前提

1. 已安装 Flutter，并且 flutter、dart 命令可用。
2. 已安装 Inno Setup 7。
3. 当前项目可以通过 flutter analyze 和 flutter test。
4. 构建机器可以访问微软官方 VC++ 运行库下载地址。

## 构建命令

在项目根目录执行：

~~~powershell
.\installer\build-installer.ps1
~~~

脚本会依次执行：

1. 安装 Flutter 依赖。
2. 生成 Drift 数据库代码。
3. 构建 Windows Release。
4. 调用 Inno Setup 生成安装包。

输出目录：

~~~text
installer/output/
~~~

## 安装程序行为

- 安装到 Program Files 下的 TodoList 目录。
- 可选创建桌面快捷方式。
- 自动创建开始菜单快捷方式。
- 安装完成后可直接启动应用。
- 安装前检测 Microsoft Visual C++ v14 x64 运行库。
- 如果缺少运行库，安装程序从微软官方地址下载并静默安装。
- 卸载 TodoList 时不删除用户的应用数据，避免误删本地任务。

## 注意事项

- 当前安装包只支持 x64 Windows。
- VC++ 运行库安装需要管理员权限。
- 当前安装包版本为 1.1.0；发布新版本时应同步修改 `pubspec.yaml`、`installer/build-installer.ps1` 和 `installer/TodoList.iss` 中的版本号。
- TodoList.iss 默认从 build/windows/x64/runner/Release 读取 Flutter 构建产物。
