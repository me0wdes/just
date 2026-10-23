#!/usr/bin/env bash
# Mirrors Just/ from claude-work HEAD into the public repo me0wdes/just.
# Personal reference images (docs/references/REF-*.jpg) never leave the private repo.
# Usage: tools/publish-public.sh "message" [vX.Y.Z]
# A tag starts .github/workflows/release.yml, which builds Windows and macOS
# and attaches the zips to the release.
set -euo pipefail
msg=${1:?commit message}
tag=${2:-}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gh repo clone me0wdes/just "$work/repo" -- -q
find "$work/repo" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git -C "$root" archive HEAD:Just | tar -x -C "$work/repo"
rm -f "$work/repo"/docs/references/REF-*.jpg
# Releases already out, newest first, for the download list in README.
releases=$(gh release list -R me0wdes/just --limit 5 --json tagName -q '.[].tagName' | tr '\n' ' ')
python3 - "$work/repo" "$tag" "$releases" <<'EOF'
import pathlib, re, sys
d, tag, out = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3].split()
r = d / 'docs/references/README.md'
r.write_text(re.sub(r'\[(REF-\d+)\]\(REF-[^)]+\.jpg\)', r'\1', r.read_text())
  + '\n\nСами изображения референсов взяты из личной библиотеки и в публичный репозиторий не входят.\n')
# Current version with direct downloads, then the three before it.
tags = ([tag] if tag else []) + [t for t in out if t != tag]
base = 'https://github.com/me0wdes/just/releases'
lines = []
if tags:
    v = tags[0].lstrip('v')
    get = f'{base}/download/{tags[0]}'
    lines.append(f'**Текущая версия {v}:** [Windows]({get}/Just-Setup-{v}.exe) · [macOS]({get}/Just-{v}.dmg) · [Android]({get}/Just-{v}-Android.apk)')
    if tags[1:4]:
        lines.append('\nПрошлые версии: ' + ' · '.join(f'[{t.lstrip("v")}]({base}/tag/{t})' for t in tags[1:4]) + f' · [все релизы]({base})')
p = d / 'README.md'
p.write_text(re.sub(r'<!-- releases -->.*?<!-- /releases -->', '<!-- releases -->\n' + '\n'.join(lines) + '\n<!-- /releases -->', p.read_text(), flags=re.S))
EOF

cd "$work/repo"
# Same author as the private repo.
git config user.name "$(git -C "$root" config user.name)"
git config user.email "$(git -C "$root" config user.email)"
git add -A
if git diff --cached --quiet; then echo "Нет изменений для публикации"; else
  git commit -q -m "$msg"
  git push -q origin main
  echo "Исходники обновлены: https://github.com/me0wdes/just"
fi

if [[ -n $tag ]]; then
  git tag -a "$tag" -m "Just ${tag#v}"
  git push -q origin "$tag"
  echo "Релиз собирается: https://github.com/me0wdes/just/actions"
fi
