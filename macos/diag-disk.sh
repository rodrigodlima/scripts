#!/usr/bin/env bash
#
# diag-disk.sh — Diagnóstico de espaço em disco no macOS
# NÃO apaga nada. Apenas inspeciona e reporta os maiores ofensores,
# com foco no que o macOS agrupa como "System Data".
#
# Uso:   chmod +x diag-disk.sh && ./diag-disk.sh
# (alguns blocos pedem sudo; ele só será solicitado se necessário)

set -uo pipefail

bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
hr()    { printf '%.0s─' {1..60}; echo; }
section(){ echo; hr; bold "▶ $1"; hr; }

# ─────────────────────────────────────────────────────────────
section "1. Visão geral do disco"
df -h / | awk 'NR==1 || /\/$/'
echo
echo "Espaço 'purgeable' (que o macOS pode liberar sob pressão):"
diskutil info / | grep -iE 'Free Space|Container Free Space' || true

# ─────────────────────────────────────────────────────────────
section "2. Snapshots locais do Time Machine (APFS)"
echo "Snapshots ocupam espaço e contam como 'System Data'."
snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple')
echo "Quantidade de snapshots locais: ${snaps}"
tmutil listlocalsnapshots / 2>/dev/null || true
echo
echo "Tamanho real dos snapshots por container:"
diskutil apfs listSnapshots / 2>/dev/null | grep -iE 'Snapshot|Disk Used' || \
  echo "  (rode 'sudo diskutil apfs listSnapshots /' para detalhes de tamanho)"

# ─────────────────────────────────────────────────────────────
section "3. Top 20 pastas em ~/Library (Library do usuário)"
echo "Este costuma ser o MAIOR ofensor real do 'System Data'."
du -sh "$HOME/Library/"* 2>/dev/null | sort -hr | head -20

# ─────────────────────────────────────────────────────────────
section "4. Caches e suspeitos comuns do usuário"
for p in \
  "$HOME/Library/Caches" \
  "$HOME/Library/Application Support" \
  "$HOME/Library/Containers" \
  "$HOME/Library/Group Containers" \
  "$HOME/Library/Developer" \
  "$HOME/Library/Developer/Xcode/DerivedData" \
  "$HOME/Library/Developer/CoreSimulator" \
  "$HOME/Library/Application Support/MobileSync" \
  "$HOME/Library/Mail" \
  "$HOME/Library/Messages" \
  "$HOME/Downloads" ; do
  if [ -e "$p" ]; then
    sz=$(du -sh "$p" 2>/dev/null | cut -f1)
    printf "  %-8s %s\n" "$sz" "$p"
  fi
done

# ─────────────────────────────────────────────────────────────
section "5. Containers / VMs (OrbStack, Docker, etc.)"
for p in \
  "$HOME/.orbstack" \
  "$HOME/OrbStack" \
  "$HOME/Library/Containers/com.docker.docker" \
  "$HOME/.docker" \
  "$HOME/Library/Application Support/com.colima" \
  "$HOME/.lima" ; do
  [ -e "$p" ] && printf "  %-8s %s\n" "$(du -sh "$p" 2>/dev/null | cut -f1)" "$p"
done
echo
if command -v docker >/dev/null 2>&1; then
  echo "docker system df:"
  docker system df 2>/dev/null || echo "  (daemon não está rodando)"
fi

# ─────────────────────────────────────────────────────────────
section "6. Swap, sleepimage e cache do sistema (/private/var)"
sudo du -sh /private/var/vm 2>/dev/null         | sed 's/^/  /' || true
sudo du -sh /private/var/folders 2>/dev/null    | sed 's/^/  /' || true
sudo du -sh /private/var/log 2>/dev/null        | sed 's/^/  /' || true
ls -lh /private/var/vm/ 2>/dev/null | sed 's/^/  /' || true

# ─────────────────────────────────────────────────────────────
section "7. Top 25 maiores arquivos do disco inteiro"
echo "(pode demorar 1-2 min — varre arquivos > 500 MB)"
sudo find / -type f -size +500M 2>/dev/null \
  -not -path '/System/Volumes/Data/private/var/vm/*' \
  -exec du -h {} + 2>/dev/null | sort -hr | head -25

echo
hr
bold "✓ Diagnóstico concluído. Nada foi apagado."
echo "Mande a saída de volta que eu te ajudo a interpretar e limpar com segurança."
hr
