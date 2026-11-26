#!/usr/bin/env bash
set -euo pipefail

# Download, verify, and unpack the D1DE HD sprite and 4X PBR asset packs from GitHub Release assets-v1.
# Usage:
#   ./scripts/download_assets.sh [--core-only] [--keep-archives]

REPO="banyartibi/DiabloDefinitiveEdition"
TAG="assets-v1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${ROOT_DIR}/scratch/asset_downloads_${TAG}"
CORE_ONLY=0
KEEP_ARCHIVES=0

for arg in "$@"; do
  case "$arg" in
    --core-only) CORE_ONLY=1 ;;
    --keep-archives) KEEP_ARCHIVES=1 ;;
    -h|--help)
      echo "Usage: $0 [--core-only] [--keep-archives]"
      echo "  --core-only      Skip hero player sprite packs (~17.7 GiB) and legacy plrgfx (~0.9 GiB)."
      echo "  --keep-archives  Keep downloaded .tar.gz files in scratch/asset_downloads_${TAG}."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

download_file() {
  local fname="$1"
  if command -v gh >/dev/null 2>&1; then
    gh release download "$TAG" --repo "$REPO" --pattern "$fname" --clobber
  else
    local url="https://github.com/${REPO}/releases/download/${TAG}/${fname}"
    curl -fL --retry 3 -o "$fname" "$url"
  fi
}

echo "[1/3] Fetching SHA256SUMS.txt from ${REPO}@${TAG}..."
download_file "SHA256SUMS.txt"

mapfile -t ARCHIVES < <(awk '{print $2}' SHA256SUMS.txt)
if [ "${#ARCHIVES[@]}" -eq 0 ]; then
  echo "No archives listed in SHA256SUMS.txt" >&2
  exit 1
fi

echo "[2/3] Downloading, verifying, and extracting packs into ${ROOT_DIR}..."
for archive in "${ARCHIVES[@]}"; do
  if [ "$CORE_ONLY" -eq 1 ]; then
    case "$archive" in
      d1de-hd-sprites-player-*|d1de-hd-sprites-plrgfx-legacy.tar.gz)
        echo "  [SKIP] $archive (--core-only)"
        continue
        ;;
    esac
  fi

  echo "  [GET]  $archive"
  download_file "$archive"

  echo "  [CHK]  $archive"
  grep -F "  ${archive}" SHA256SUMS.txt | sha256sum -c -

  echo "  [TAR]  $archive -> ${ROOT_DIR}"
  tar -xzf "$archive" -C "$ROOT_DIR"

  if [ "$KEEP_ARCHIVES" -eq 0 ]; then
    rm -f "$archive"
  fi
done

echo "[3/3] Done. Asset packs restored under ${ROOT_DIR}/assets/."
