"""Зеркало страниц «Экспресс-расписания» для веб-версии.

Сайты колледжей не отдают CORS, поэтому веб-версия читает их копию из ветки
`mirror` через raw.githubusercontent.com (см. GitHubProjectUrls.mirrorRaw).
Файлы кладутся как <out>/<host><path>, например out/www.chtotib.ru/schedule_gl/cg.htm.

Запуск: python tool/mirror_schedule.py <out> <stamp_prev> <base_url>...
  stamp_prev — прошлый штамп (Last-Modified страниц групп); если сайт не менялся,
  скрипт ничего не качает и завершается с кодом 3.
"""

import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlsplit

ENTRY_PAGES = ["index.htm", "cg.htm", "bg.htm", "hg.htm", "vg.htm", "cp.htm", "ca.htm"]
# Только страницы расписания из того же каталога: cg13.htm, vp7.htm, ca59.htm…
# Журналы j*.htm (больше половины сайта) приложение не открывает — пропускаем.
LINK = re.compile(r'href="((?!j)[a-z]+\d*\.htm)"', re.I)
UA = {"User-Agent": "Mozilla/5.0 (Raspisanie mirror)"}


def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def stamp(bases):
    parts = []
    for base in bases:
        req = urllib.request.Request(base + "cg.htm", headers=UA, method="HEAD")
        with urllib.request.urlopen(req, timeout=20) as r:
            parts.append(f"{base} {r.headers.get('Last-Modified', '')}")
    return "\n".join(parts) + "\n"


def mirror(out, base):
    split = urlsplit(base)
    target = out / (split.hostname + split.path)
    seen, queue = set(), list(ENTRY_PAGES)

    def grab(name):
        for attempt in range(2):
            try:
                return name, fetch(base + name)
            except Exception as e:  # битая ссылка на сайте — не повод валить всё зеркало
                error = e
        print(f"skip {name}: {error}", file=sys.stderr)
        return name, None

    # Сервер колледжа рвёт соединения уже при 8 потоках — держим 4.
    with ThreadPoolExecutor(4) as pool:
        while queue:
            batch = [n for n in dict.fromkeys(queue) if n not in seen]
            seen.update(batch)
            queue = []
            for name, body in pool.map(grab, batch):
                if body is None:
                    continue
                (target / name).parent.mkdir(parents=True, exist_ok=True)
                (target / name).write_bytes(body)
                queue += LINK.findall(body.decode("utf-8", "ignore"))
    return len(seen)


def main():
    out, prev, bases = Path(sys.argv[1]), sys.argv[2], sys.argv[3:]
    current = stamp(bases)
    if current.strip() == prev.strip():
        print("no changes")
        sys.exit(3)
    for base in bases:
        print(f"{base}: {mirror(out, base)} pages")
    (out / ".stamp").write_text(current)


if __name__ == "__main__":
    main()
