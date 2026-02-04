# gh-publish

把“当前目录”一键发布成 GitHub 仓库：自动初始化 `git`、创建首次提交（如需要）、创建远端仓库并推送。

## 依赖

- `git`
- `gh`（GitHub CLI）

脚本会先检查 `gh` 是否已登录；若未登录，会自动触发 `gh auth login`（浏览器授权）。

## 用法

在你要发布的项目目录里执行：

### 交互式（推荐）

```bash
gh-publish
```

按提示输入：

- 仓库名（默认取当前目录名）
- 可见性：`private` / `public`
- 回车确认后自动创建仓库并推送

### 非交互式

```bash
gh-publish --name my-repo --private --yes
# 或
gh-publish --name my-repo --public --yes
```

### 一键快捷模式

按“当前文件夹名”创建仓库，并且不做任何交互与确认：

```bash
gh-publish --ob   # public
gh-publish --op   # private
```

说明：`--ob/--op` 与 `--name`、`--public/--private` 互斥（快捷模式会自动确定仓库名与可见性）。

### 常用参数

- `--name <repo>`：仓库名（也可用 `owner/repo`）
- `--private` / `--public`：可见性
- `--ob`：按当前目录名创建 `public` 仓库（隐含 `--yes`，不再提示输入）
- `--op`：按当前目录名创建 `private` 仓库（隐含 `--yes`，不再提示输入）
- `--remote <name>`：远端名（默认 `origin`）
- `--yes`：跳过最后的确认提示
- `--help`：查看帮助

## 安装为终端命令（加入 PATH）

推荐用户级安装到 `~/.local/bin`（无需 `sudo`）：

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/gh-publish" ~/.local/bin/gh-publish
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

验证：

```bash
command -v gh-publish
gh-publish --help
```

如果你用的是 `bash`，把 `~/.zshrc` 换成 `~/.bashrc`（或 `~/.bash_profile`）即可。

## 测试

```bash
bash tests/test_gh_publish.sh
```
