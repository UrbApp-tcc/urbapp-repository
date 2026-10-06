#!/usr/bin/env bash
# Envia as fotos de demonstração ao bucket `post-images` do Supabase local.
# Rode depois de `supabase db reset`:  bash supabase/seed-media.sh
set -euo pipefail

cd "$(dirname "$0")"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_urbapp-repository}"
API="${SUPABASE_API_URL:-http://127.0.0.1:54321}"
KEY="${SERVICE_ROLE_KEY:-$(npx --yes supabase status -o env 2>/dev/null | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p')}"
[ -n "$KEY" ] || { echo "SERVICE_ROLE_KEY não encontrada (rode 'supabase start')." >&2; exit 1; }

pick_image() { # $1 = título da ocorrência, $2 = ordem
  local title index="$2"
  title="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  local flood=(alagamento-urbano evidencia-alagamento-02 evidencia-alagamento-03 evidencia-alagamento-04)
  local all=(alagamento-urbano asfalto-molhado iluminacao-publica residuos-calcada evidencia-alagamento-02 evidencia-alagamento-03 evidencia-alagamento-04)
  case "$title" in
    *alagamento*|*vazamento*|*bueiro*) echo "${flood[$((index % 4))]}" ;;
    *buraco*|*cal*ada*|*piso*|*rampa*|*afundada*) echo "asfalto-molhado" ;;
    *poste*|*l*mpada*|*sem*foro*|*ilumina*) echo "iluminacao-publica" ;;
    *lixo*|*entulho*|*res*duo*|*descarte*|*galho*|*rvore*) echo "residuos-calcada" ;;
    *) echo "${all[$((index % 7))]}" ;;
  esac
}

count=0
while IFS='|' read -r post_id title; do
  image="$(pick_image "$title" "$post_id")"
  curl -fsS -X POST "$API/storage/v1/object/post-images/reports/$post_id/evidencia-$post_id.jpg" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: image/jpeg" -H "x-upsert: true" \
    --data-binary "@seed-media/$image.jpg" >/dev/null
  count=$((count + 1))
done < <(docker exec "$DB_CONTAINER" psql -U postgres -d postgres -At -F '|' -c \
  "select image.post_id, coalesce(occurrence.title, '') from public.post_images image join public.posts post on post.id = image.post_id left join public.occurrences occurrence on occurrence.id = post.occurrence_id where image.storage_path like 'reports/%' and image.storage_path not like 'reports/pending/%' order by image.post_id")

echo "$count fotos enviadas."
