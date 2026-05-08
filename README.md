# Remove 360 Software

一个用于 Windows 的 360/Qihoo 系列软件卸载与清理脚本。它会优先调用系统注册表里的官方卸载命令，然后清理匹配到的 360 相关进程、服务、启动项、计划任务、快捷方式和残留文件夹。

> 重要提醒：请只在你自己拥有或被授权维护的电脑上运行。本工具需要管理员权限。运行前建议关闭正在使用的软件，并在运行结束后重启 Windows。

## 文件说明

- `卸载360软件.cmd`：双击运行的启动器，会自动请求管理员权限。
- `Remove-360-Software.ps1`：实际执行卸载和清理的 PowerShell 脚本。

这两个文件必须放在同一个文件夹里。

## 支持清理的内容

- 360 安全卫士、360 杀毒、360 浏览器、360 极速浏览器、360 压缩、360 软件管家等 360/Qihoo 系列软件。
- 相关运行进程。
- 相关 Windows 服务。
- 相关开机启动项。
- 相关计划任务。
- 相关桌面、开始菜单、启动文件夹快捷方式。
- 常见安装目录和用户目录中的 360/Qihoo 残留文件夹。

脚本会尽量避开常见误伤对象，例如 Norton 360、Autodesk Fusion 360、Xbox 360、Insta360 等不是 360/Qihoo 公司的软件。

## 使用方法

1. 下载本项目。
2. 解压后进入文件夹。
3. 双击 `卸载360软件.cmd`。
4. 如果 Windows 弹出“用户账户控制”提示，点击“是”。
5. 等待脚本运行完成。
6. 按窗口提示查看结果，然后重启电脑。

运行时会在当前用户桌面生成一个日志文件，文件名类似：

```text
Remove360_Log_20260508_132614.txt
```

## 关于“360下载的软件”

脚本默认会识别安装来源疑似来自 360 下载目录或缓存目录的软件，并写入日志，但不会自动卸载这些看起来像第三方的软件。这样做是为了避免误删正常程序。

如果你确认要连这些疑似由 360 下载的软件也一起尝试卸载，可以用管理员 PowerShell 在本项目目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-360-Software.ps1 -Run -Remove360DownloadedApps
```

## 高级参数

跳过系统还原点创建：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-360-Software.ps1 -Run -SkipRestorePoint
```

同时卸载疑似由 360 下载的软件，并跳过系统还原点：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-360-Software.ps1 -Run -Remove360DownloadedApps -SkipRestorePoint
```

## 常见问题

### Windows 提示不能运行脚本怎么办？

优先双击 `卸载360软件.cmd`，它已经使用 `ExecutionPolicy Bypass` 调用 PowerShell，一般不需要手动修改系统执行策略。

### 为什么有些 360 文件删不掉？

可能是文件正在被占用，或服务/驱动仍在运行。先重启电脑，然后再次运行 `卸载360软件.cmd`。

### 为什么没有自动卸载所有“360下载的软件”？

第三方软件的名称、厂商和用途可能与 360 无关，只是安装包曾经被 360 下载过。默认只记录到日志，避免误删。确认后可以使用 `-Remove360DownloadedApps` 参数。

## 上传到 GitHub

### 方法一：网页上传

1. 登录 GitHub。
2. 点击右上角 `+`，选择 `New repository`。
3. Repository name 填写：

```text
remove-360-software
```

4. 选择 `Public` 或 `Private`。
5. 不要勾选 `Add a README file`，因为本项目已经有 README。
6. 创建仓库后，点击 `uploading an existing file`。
7. 把本文件夹里的所有文件拖进去。
8. 点击 `Commit changes`。

### 方法二：Git 命令上传

先在 GitHub 创建一个空仓库，例如：

```text
https://github.com/你的用户名/remove-360-software
```

然后在本项目文件夹打开命令行，运行：

```bat
git init
git add .
git commit -m "Initial release"
git branch -M main
git remote add origin https://github.com/你的用户名/remove-360-software.git
git push -u origin main
```

把命令里的 `你的用户名` 换成你的 GitHub 用户名。

## 免责声明

本工具会修改系统软件、服务、启动项和文件。请在运行前确认重要数据已经备份。作者不对误操作、第三方卸载器行为或系统环境差异造成的问题承担责任。
