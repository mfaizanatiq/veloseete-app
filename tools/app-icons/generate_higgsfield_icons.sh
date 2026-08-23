#!/usr/bin/env bash
# Generate Tracky mood app icons via Higgsfield GPT Image 2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
ASSETS="$ROOT/Veloseete/Resources/Assets.xcassets"
OUT="$ROOT/tools/app-icons/higgsfield-output"
mkdir -p "$OUT"

BASE="iOS app icon, 1024x1024 square, Apple Human Interface Guidelines compliant. Veloseete mascot Tracky: soft matte 3D lime-green sphere face centered on solid flat background filling entire image edge-to-edge. Black eyes and mouth with subtle gritty texture on features. Centered face ~75% of canvas with safe margins for iOS squircle mask. No text, no border, no rounded corners, no transparency. Match reference character style exactly."

generate_one() {
  local mood="$1"
  local bg="$2"
  local expr="$3"
  local ref="$ASSETS/tracky-${mood}.imageset/tracky-${mood}.png"
  local prompt="${BASE} Background color: ${bg}. Mood: ${expr}."
  echo "→ Generating $mood..."
  local url
  url=$(higgsfield generate create gpt_image_2 \
    --prompt "$prompt" \
    --image "$ref" \
    --aspect_ratio 1:1 \
    --resolution 2k \
    --quality high \
    --wait --wait-timeout 10m 2>&1 | tail -1)
  if [[ "$url" =~ ^https?:// ]]; then
    curl -fsSL "$url" -o "$OUT/${mood}.png"
    echo "✓ $mood → $OUT/${mood}.png"
  else
    echo "✗ $mood failed: $url" >&2
    return 1
  fi
}

# chill already generated separately
generate_one proud "#D9FC55 electric lime" "proud confident big smile, happy wide eyes"
generate_one fueled "#CFF84A bright lime" "fueled energized O-shaped open mouth, alert wide eyes"
generate_one focused "#181C18 dark charcoal" "focused determined straight-line mouth, intense narrow eyes"
generate_one night "#12160E near-black" "night sleepy half-closed small eyes, gentle slight smile"
generate_one dawn "#E4FA98 soft morning lime" "dawn bright big morning smile, cheerful open eyes"
generate_one grit "#222822 dark gray-green" "grit tough diagonal slanted mouth, slightly uneven determined eyes"
generate_one legend "#E0FF62 vivid lime" "legend epic huge grin, sparkling happy big eyes"
generate_one cozy "#C6EAB6 soft mint green" "cozy warm soft gentle smile, relaxed content eyes"

echo "All done."
