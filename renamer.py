#!/usr/bin/env python3
"""On-device semantic renamer for macOS Downloads."""

import argparse
import hashlib
import json
import os
import re
import select
import subprocess
import sys
import time
import uuid
import zipfile
from datetime import datetime, timezone
from html import unescape
from pathlib import Path
from xml.etree import ElementTree

PROJECT = Path(__file__).resolve().parent
HOME = Path.home()
ROOT = Path(os.environ.get("SMART_RENAMER_ROOT", str(HOME / "Downloads"))).resolve()
NAMER = Path(os.environ.get("NAMEDROP_BINARY", str(PROJECT / "bin" / "namedrop-namer")))
TOAST = Path(os.environ.get("NAMEDROP_TOAST", str(PROJECT / "bin" / "namedrop-toast")))
TOAST_ICON = Path(os.environ.get("NAMEDROP_ICON", str(PROJECT / "assets" / "NameDrop.icns")))
STATE_DIR = Path(os.environ.get("NAMEDROP_STATE", str(HOME / "Library/Application Support/NameDrop")))
LEDGER = STATE_DIR / "history.jsonl"
SUPPORTED = {".pdf", ".docx", ".xlsx", ".pptx", ".txt", ".md", ".csv", ".tsv", ".json", ".xml", ".html", ".htm"}
MAX_TEXT = 7_000
MAX_VISIBLE_TOASTS = 4
TOAST_PROCESSES = []


def inside_root(path: Path) -> bool:
    try:
        path.resolve().relative_to(ROOT)
        return True
    except ValueError:
        return False


def xml_text(raw: bytes) -> str:
    try:
        root = ElementTree.fromstring(raw)
        return " ".join(value.strip() for value in root.itertext() if value.strip())
    except ElementTree.ParseError:
        return ""


def extract_zip_document(path: Path) -> str:
    prefixes = ("word/document.xml", "ppt/slides/slide", "xl/sharedStrings.xml", "xl/worksheets/sheet")
    chunks = []
    with zipfile.ZipFile(path) as archive:
        for member in sorted(archive.namelist()):
            if member.startswith(prefixes) and member.endswith(".xml"):
                chunks.append(xml_text(archive.read(member)))
                if sum(map(len, chunks)) >= MAX_TEXT:
                    break
    return "\n".join(chunks)[:MAX_TEXT]


def extract_pdf(path: Path) -> str:
    try:
        from pypdf import PdfReader

        reader = PdfReader(str(path))
        chunks = []
        try:
            fields = reader.get_fields() or {}
            field_values = []
            for key, field in fields.items():
                value = field.get("/V")
                if value not in (None, "", "/Off"):
                    field_values.append(f"{key}: {value}")
            chunks.append("\n".join(field_values))
        except Exception:
            pass
        for page in reader.pages[:8]:
            chunks.append(page.extract_text() or "")
            if sum(map(len, chunks)) >= MAX_TEXT:
                break
        return "\n".join(chunks)[:MAX_TEXT]
    except Exception:
        return ""


def extract_text(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        text = extract_pdf(path)
    elif suffix in {".docx", ".xlsx", ".pptx"}:
        text = extract_zip_document(path)
    else:
        raw = path.read_bytes()[: MAX_TEXT * 4]
        text = raw.decode("utf-8", errors="replace")
        if suffix in {".html", ".htm"}:
            text = re.sub(r"<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>", " ", text, flags=re.I | re.S)
            text = unescape(re.sub(r"<[^>]+>", " ", text))
    return re.sub(r"\s+", " ", text).strip()[:MAX_TEXT]


def extract_signals(text: str) -> str:
    patterns = [
        ("Entity", r"(?:Applicant|Named Insured|Insured Name|Business Name)\s*:\s*(?:DBA\s*:\s*)?([A-Za-z0-9&'.,()\- ]{2,100}?)(?=\s{2,}|\s+\d{1,6}\s|\s+(?:Submission|Policy|Address|Mailing)\b|SSS)"),
        ("Carrier", r"(?:Issuing Company|Insurance Company|Carrier)\s*:\s*([A-Za-z0-9&'.,()\- ]{3,120}?)(?=\s{2,}|SSS|\s+(?:We are|The insurer|Policy)\b)"),
        ("Policy term", r"Policy (?:Period|Term)\s*:\s*(\d{1,2}/\d{1,2}/\d{2,4}).{0,40}?(?:To|-|through)\s*(\d{1,2}/\d{1,2}/\d{2,4})"),
        ("Effective date", r"Effective Date\s*:\s*(\d{1,2}/\d{1,2}/\d{2,4})"),
        ("Identifier", r"\b((?:APP|POL|QTE|INV)[- ]?\d{5,})\b"),
    ]
    facts = []
    for label, pattern in patterns:
        match = re.search(pattern, text, flags=re.I)
        if match:
            value = " to ".join(part.strip(" .,-") for part in match.groups() if part)
            if label == "Entity":
                value = re.sub(r"\s+P\.?O\.?\s+Box$", "", value, flags=re.I).strip()
                tokens = value.split()
                for width in range(1, len(tokens) // 2 + 1):
                    if [token.lower() for token in tokens[:width]] == [token.lower() for token in tokens[width : width * 2]]:
                        value = " ".join(tokens[:width] + tokens[width * 2 :])
                        break
            facts.append(f"{label}: {value}")
    if re.search(r"\b(?:Insurance Proposal|Quote Proposal|Quotation)\b", text, flags=re.I):
        facts.append("Document type: Insurance Quote")
    elif re.search(r"\b(?:Application|ACORD 1(?:25|26|27|30|40))\b", text, flags=re.I):
        facts.append("Document type: Insurance Application")
    elif re.search(r"\b(?:Policy Declaration|Policy Number|Coverage is bound)\b", text, flags=re.I):
        facts.append("Document type: Insurance Policy")
    return "\n".join(facts) or "No high-confidence structured facts found."


def prompt(path: Path, text: str) -> str:
    return f"""Current filename: {path.name}
File type: {path.suffix.lower() or "unknown"}

High-confidence extracted facts (prefer these over boilerplate):
{extract_signals(text)}

Extracted document content:
<document>
{text or "No readable text was extracted. Preserve useful facts from the current filename and improve only obvious generic wording."}
</document>"""


def structured_stem(text: str) -> str:
    facts = {}
    for line in extract_signals(text).splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            facts[key] = value
    entity = facts.get("Entity")
    document_type = facts.get("Document type")
    if not entity or not document_type:
        return ""
    parts = [entity]
    carrier = facts.get("Carrier")
    if carrier:
        carrier = re.sub(
            r"\s+(?:Specialty Insurance Company|Insurance Company|Indemnity Company)$", "", carrier, flags=re.I
        ).strip()
        if carrier and carrier.lower() not in entity.lower():
            parts.append(carrier)
    parts.append(document_type)
    date_source = facts.get("Effective date") or facts.get("Policy term", "")
    date_match = re.search(r"(\d{1,2})/(\d{1,2})/(\d{4})", date_source)
    if date_match:
        month, day, year = date_match.groups()
        parts.append(f"{year}-{int(month):02d}-{int(day):02d}")
    elif facts.get("Identifier"):
        parts.append(facts["Identifier"].upper().replace(" ", ""))
    return " - ".join(parts)


def clean_stem(raw: str) -> str:
    match = re.search(r"(?:^|\n)\s*NAME\s*:\s*(.+)", raw, flags=re.I)
    stem = (match.group(1) if match else raw).strip().strip("`'\"")
    stem = re.sub(r"^(suggested\s+)?file(name)?\s*:\s*", "", stem, flags=re.I)
    stem = re.sub(r"\.[A-Za-z0-9]{1,8}$", "", stem)
    stem = re.sub(r"[/:*?\"<>|\\\x00-\x1f]", " ", stem)
    stem = re.sub(r"\s+", " ", stem).strip(" .-_()")
    stem = re.sub(r"\s+-\s+(LLC|Inc\.?|Corp\.?|Ltd\.?)\b", r" \1", stem, flags=re.I)
    stem = re.sub(
        r"\b(0?[1-9]|1[0-2])[ /-](0?[1-9]|[12]\d|3[01])[ /-]((?:19|20)\d{2})\b",
        lambda match: f"{match.group(3)}-{int(match.group(1)):02d}-{int(match.group(2)):02d}",
        stem,
    )
    return stem[:140].strip()


def current_name_is_useful(path: Path) -> bool:
    stem = re.sub(r"\s*\(\d+\)$", "", path.stem).strip()
    if re.fullmatch(r"(?i)(?:quote|document|download|attachment|file|scan|image)(?:[-_ ]*\d+)?", stem):
        return False
    if re.fullmatch(r"(?i)(?:applicationpacket|quickquote)[-_ ]*\d+", stem):
        return False
    if re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}.*", stem):
        return False
    words = re.findall(r"[A-Za-z]{2,}", stem)
    return bool(
        len(words) >= 3
        or (len(words) >= 2 and re.search(r"(?i)requirements|receipt|license|policy|quote|application|form|supplemental|acord|invoice|\bbor\b", stem))
        or re.search(r"(?i)(policy|receipt|license)$", stem)
    )


def unique_destination(path: Path, stem: str) -> Path:
    original_base = re.sub(r"\s*\(\d+\)$", "", path.stem).strip()
    if re.sub(r"\W+", "", stem).lower() == re.sub(r"\W+", "", original_base).lower():
        return path
    destination = path.with_name(stem + path.suffix.lower())
    if destination == path or not destination.exists():
        return destination
    for number in range(2, 1000):
        destination = path.with_name(f"{stem} ({number}){path.suffix.lower()}")
        if not destination.exists():
            return destination
    raise RuntimeError("No available collision-safe filename")


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class AppleNamer:
    def __init__(self):
        if not NAMER.is_file():
            raise RuntimeError(f"Naming binary is missing: {NAMER}. Run ./install-macos.sh first.")
        self.process = None

    def start(self):
        self.process = subprocess.Popen(
            [str(NAMER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1
        )

    def name(self, request_prompt: str) -> str:
        if self.process is None or self.process.poll() is not None:
            self.start()
        request_id = str(uuid.uuid4())
        self.process.stdin.write(json.dumps({"id": request_id, "prompt": request_prompt}) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            error = self.process.stderr.read().strip()
            raise RuntimeError(error or "On-device model stopped unexpectedly")
        response = json.loads(line)
        if response.get("error"):
            raise RuntimeError(response["error"])
        return clean_stem(response.get("stem", ""))

    def close(self):
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()


def eligible(path: Path) -> bool:
    return path.is_file() and inside_root(path) and not path.name.startswith(".") and path.suffix.lower() in SUPPORTED


def recent_files(days: int):
    cutoff = time.time() - days * 86_400
    return sorted(
        (path for path in ROOT.iterdir() if eligible(path) and path.stat().st_mtime >= cutoff),
        key=lambda path: path.stat().st_mtime,
    )


def write_ledger(record: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LEDGER.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


def show_rename_toast(original_name: str, renamed_name: str) -> None:
    global TOAST_PROCESSES
    if not TOAST.is_file():
        return
    try:
        TOAST_PROCESSES = [(process, slot) for process, slot in TOAST_PROCESSES if process.poll() is None]
        occupied_slots = {slot for _, slot in TOAST_PROCESSES}
        slot = next((candidate for candidate in range(MAX_VISIBLE_TOASTS) if candidate not in occupied_slots), None)
        if slot is None:
            oldest_process, slot = TOAST_PROCESSES.pop(0)
            oldest_process.terminate()
        environment = os.environ.copy()
        environment["NAMEDROP_ICON"] = str(TOAST_ICON)
        process = subprocess.Popen(
            [str(TOAST), original_name, renamed_name, str(slot)],
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        TOAST_PROCESSES.append((process, slot))
    except OSError:
        pass


def process_file(namer: AppleNamer, path: Path, run_id: str, apply: bool, notify: bool = False) -> dict:
    started = time.monotonic()
    text = extract_text(path)
    if current_name_is_useful(path):
        stem = path.stem
    else:
        stem = clean_stem(structured_stem(text)) or namer.name(prompt(path, text))
    if not stem:
        raise RuntimeError("The on-device model returned an empty name")
    destination = unique_destination(path, stem)
    result = {
        "run_id": run_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "original": str(path),
        "renamed": str(destination),
        "sha256": file_digest(path),
        "latency_seconds": round(time.monotonic() - started, 3),
        "applied": apply,
    }
    if apply and destination != path:
        path.rename(destination)
        write_ledger(result)
        if notify:
            show_rename_toast(path.name, destination.name)
    return result


def command_once(args) -> int:
    files = recent_files(args.since_days)
    if args.limit:
        files = files[: args.limit]
    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8]
    namer = AppleNamer()
    failures = 0
    try:
        for index, path in enumerate(files, 1):
            try:
                result = process_file(namer, path, run_id, args.apply)
                marker = "RENAMED" if args.apply else "PREVIEW"
                print(f"[{index}/{len(files)}] {marker}: {path.name} -> {Path(result['renamed']).name} ({result['latency_seconds']}s)", flush=True)
            except Exception as exc:
                failures += 1
                print(f"[{index}/{len(files)}] SKIPPED: {path.name}: {exc}", file=sys.stderr, flush=True)
    finally:
        namer.close()
    print(json.dumps({"run_id": run_id, "files": len(files), "failures": failures, "applied": args.apply}))
    return 1 if failures else 0


def command_watch(args) -> int:
    processed = set()
    for existing in ROOT.iterdir():
        if existing.is_file():
            try:
                stat = existing.stat()
                processed.add((stat.st_dev, stat.st_ino))
            except FileNotFoundError:
                pass
    stable = {}
    retry_after = {}
    namer = AppleNamer()
    directory_fd = os.open(str(ROOT), os.O_RDONLY)
    queue = select.kqueue()
    event = select.kevent(
        directory_fd,
        filter=select.KQ_FILTER_VNODE,
        flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
        fflags=(
            select.KQ_NOTE_WRITE
            | select.KQ_NOTE_EXTEND
            | select.KQ_NOTE_ATTRIB
            | select.KQ_NOTE_RENAME
            | select.KQ_NOTE_DELETE
        ),
    )
    queue.control([event], 0, 0)
    try:
        while True:
            timeout = args.settle_seconds if stable else None
            queue.control(None, 1, timeout)
            present = set()
            for path in ROOT.iterdir():
                if not path.is_file() or path.name.startswith("."):
                    continue
                try:
                    stat = path.stat()
                except FileNotFoundError:
                    continue
                identity = (stat.st_dev, stat.st_ino)
                present.add(identity)
                if identity in processed or not eligible(path):
                    continue
                signature = (stat.st_size, stat.st_mtime_ns)
                previous = stable.get(identity)
                if previous is None or previous[0] != signature:
                    stable[identity] = (signature, time.monotonic())
                    continue
                if time.monotonic() - previous[1] < args.settle_seconds or time.monotonic() < retry_after.get(identity, 0):
                    continue
                run_id = "watch-" + datetime.now().strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8]
                try:
                    result = process_file(namer, path, run_id, True, notify=True)
                    print(f"RENAMED: {path.name} -> {Path(result['renamed']).name}", flush=True)
                    processed.add(identity)
                    stable.pop(identity, None)
                    retry_after.pop(identity, None)
                except Exception as exc:
                    print(f"SKIPPED: {path.name}: {exc}", file=sys.stderr, flush=True)
                    retry_after[identity] = time.monotonic() + args.retry_seconds
            stable = {identity: value for identity, value in stable.items() if identity in present}
            retry_after = {identity: value for identity, value in retry_after.items() if identity in present}
    except KeyboardInterrupt:
        return 0
    finally:
        queue.close()
        os.close(directory_fd)
        namer.close()


def command_undo(args) -> int:
    if not LEDGER.is_file():
        print("No rename history found.")
        return 0
    records = [json.loads(line) for line in LEDGER.read_text(encoding="utf-8").splitlines() if line.strip()]
    run_id = args.run_id or (records[-1]["run_id"] if records else None)
    restored = 0
    for record in reversed([item for item in records if item["run_id"] == run_id]):
        renamed = Path(record["renamed"])
        original = Path(record["original"])
        if renamed.is_file() and not original.exists() and file_digest(renamed) == record["sha256"]:
            renamed.rename(original)
            restored += 1
            print(f"RESTORED: {renamed.name} -> {original.name}")
    print(json.dumps({"run_id": run_id, "restored": restored}))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Rename downloads using Apple's on-device Foundation Model")
    subparsers = parser.add_subparsers(dest="command", required=True)
    once = subparsers.add_parser("once", help="Process a recent cohort")
    once.add_argument("--since-days", type=int, default=7)
    once.add_argument("--limit", type=int)
    once.add_argument("--apply", action="store_true", help="Apply renames; otherwise preview only")
    once.set_defaults(func=command_once)
    watch = subparsers.add_parser("watch", help="Watch for future downloads")
    watch.add_argument("--settle-seconds", type=float, default=3.0)
    watch.add_argument("--retry-seconds", type=float, default=60.0)
    watch.set_defaults(func=command_watch)
    undo = subparsers.add_parser("undo", help="Undo the most recent or specified run")
    undo.add_argument("--run-id")
    undo.set_defaults(func=command_undo)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
