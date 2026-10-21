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
python3 - "$work/repo" <<'EOF'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1])
r = d / 'docs/references/README.md'
r.write_text(re.sub(r'\[(REF-\d+)\]\(REF-[^)]+\.jpg\)', r'\1', r.read_text())
  + '\n\nСами изображения референсов взяты из личной библиотеки и в публичный репозиторий не входят.\n')
p = d / 'README.md'
p.write_text(p.read_text().replace('# Just\n', '# Just\n\n**Скачать для Windows:** [последняя версия](https://github.com/me0wdes/just/releases/latest). Распакуйте архив целиком и запустите `day_planner.exe`.\n', 1))
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
