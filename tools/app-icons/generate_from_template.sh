#!/usr/bin/env bash
# Generate all Tracky mood app icons from ONE locked composition template.
# 1) Requires tools/app-icons/higgsfield-output/_template/master.png
# 2) Expression-only variants via gpt_image_2 (template = image 1, mood face = image 2)
# 3) Normalize to 1024×1024 RGB and install into Assets.xcassets
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASSETS="$ROOT/Veloseete/Resources/Assets.xcassets"
OUT="$ROOT/tools/app-icons/higgsfield-output"
TMPL="$OUT/_template/master.png"

if [[ ! -f "$TMPL" ]]; then
  echo "Missing master template: $TMPL" >&2
  exit 1
fi

SWAP='IMAGE REFERENCES: image 1 = LOCKED iOS app-icon COMPOSITION TEMPLATE (use this exact framing, crop, scale, lighting, lime material fill edge-to-edge). image 2 = Tracky mood expression reference (use ONLY the facial expression / eye / mouth shape).
Change ONLY the facial expression to match image 2.
Keep image 1 pixel-faithful for everything else: full-bleed lime face filling the entire square, eye position, mouth position, shading, grit texture style, scale.
NO floating circle, NO avatar disc, NO empty corners, NO rounded mockup, NO text.
Opaque square app icon.'

gen_mood() {
  local mood="$1" label="$2"
  local face="$ASSETS/tracky-${mood}.imageset/tracky-${mood}.png"
  echo "→ $mood ($label)"
  local url
  url=$(higgsfield generate create gpt_image_2 \
    --prompt "$SWAP Mood label: $label." \
    --image "$TMPL" \
    --image "$face" \
    --aspect_ratio 1:1 \
    --resolution 2k \
    --quality high \
    --wait --wait-timeout 12m 2>&1 | tail -1)
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "FAIL $mood: $url" >&2
    return 1
  fi
  curl -fsSL "$url" -o "$OUT/${mood}.png"
  echo "✓ $mood"
}

# chill is the master copy
cp "$TMPL" "$OUT/chill.png"

gen_mood proud "Proud — round open eyes, big confident smile"
gen_mood fueled "Fueled — wide alert eyes, small O mouth"
gen_mood focused "Focused — narrow eyes, straight mouth line"
gen_mood night "Night — sleepy half-closed eyes, tiny smile"
gen_mood dawn "Dawn — bright open eyes, warm morning smile"
gen_mood grit "Grit — determined eyes, diagonal tough mouth"
gen_mood legend "Legend — big sparkling eyes, huge grin"
gen_mood cozy "Cozy — soft relaxed eyes, gentle smile"

echo "Normalizing + installing…"
python3 "$ROOT/tools/app-icons/install_higgsfield_icons.py"
echo "ALL DONE"
