<h1 align="center">NameDrop</h1>

<p align="center">
  A tiny, invisible macOS agent that reads completed downloads and gives them useful filenames with Apple Intelligence—entirely on-device.
</p>

<p align="center"><em>A weekend-sized quest against <code>Quote (64).pdf</code>.</em></p>

## What it does

```text
New file appears in ~/Downloads
              ↓
Wait until the file is complete
              ↓
Extract text and structured document fields locally
              ↓
Use reliable facts immediately; ask Apple's on-device model only when needed
              ↓
Rename safely and append a hash-verified undo record
```

- No browser extension, API key, cloud model, account, or visible window.
- Starts at login and automatically restarts after a crash.
- Sleeps on macOS file events, so idle CPU usage is effectively zero.
- Never overwrites an existing file; duplicates receive `(2)`, `(3)`, and so on.
- Treats document content as untrusted data and sanitizes model output before renaming.

## Requirements

- Apple-silicon Mac with Apple Intelligence support
- macOS 26 or newer
- Apple Intelligence enabled in System Settings
- Apple Command Line Tools: `xcode-select --install`

## Install

```sh
git clone https://github.com/prrranavv/namedrop.git
cd namedrop
./install-macos.sh
```

The installer creates a private Python environment, compiles the two small Swift helpers, installs a hidden app in `~/Applications`, and registers a per-user LaunchAgent.

On first launch, allow **NameDrop → Downloads Folder** under **System Settings → Privacy & Security → Files & Folders**. Full Disk Access is not required.

Check it at any time:

```sh
./status.sh
```

## Supported files

PDF, DOCX, XLSX, PPTX, TXT, Markdown, CSV, TSV, JSON, XML, and HTML.

Installers, archives, hidden files, and incomplete browser downloads such as `.crdownload` and `.part` files are ignored.

## Process existing downloads

Preview the last seven days without changing anything:

```sh
./renamer.py once --since-days 7
```

Apply the previewed cohort:

```sh
./renamer.py once --since-days 7 --apply
```

## Undo

Every applied rename is recorded in:

```text
~/Library/Application Support/NameDrop/history.jsonl
```

Undo the latest run:

```sh
./renamer.py undo
```

Or undo a run by the ID printed after processing:

```sh
./renamer.py undo --run-id RUN_ID
```

Undo verifies the file's SHA-256 digest and refuses to overwrite an existing original path.

## Performance

An 80-file real-world POC completed in 26.7 seconds:

| Path | Files | Average latency |
|---|---:|---:|
| Structured fast path | 31 | 26 ms |
| Apple model fallback | 6 | 2.04 s |
| Files already named well | 43 | Preserved |

Actual results depend on hardware, file size, format, and Apple Intelligence availability.

## Privacy

Document extraction, inference, filename generation, and rename history stay on the Mac. The installer uses the network only to install the open-source `pypdf` dependency into its private environment.

The hidden helper receives access to `~/Downloads` only. It does not request Full Disk Access or read other folders.

## Remove

```sh
./uninstall-macos.sh
```

The app and LaunchAgent are moved to Trash. Rename history and the private environment are preserved so undo remains available.

## License

MIT
