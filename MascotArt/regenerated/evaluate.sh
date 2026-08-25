#!/bin/zsh
# Evaluate regenerated character art before accepting it.
# Two gates: the leg join must actually be fixed, and the character must not
# have drifted off-model. Failing either means we keep the original.
ART=/Users/hans_vador/.claude/jobs/2489a722/tmp/art
L=/Users/hans_vador/.claude/jobs/2489a722/tmp/legfix
A=/Users/hans_vador/Desktop/Broke/Broke/Assets.xcassets

for f in "$@"; do
  new="$L/${f}_fixed.png"
  old="$(ls $A/clay_$f.imageset/*.png | head -1)"
  [ -f "$new" ] || { echo "$f: NOT GENERATED"; continue; }
  echo "=== $f ==="
  echo -n "  legs  old: "; "$ART/legcheck" "$old" | sed 's/^[^:]*: //'
  echo -n "  legs  new: "; "$ART/legcheck" "$new" | sed 's/^[^:]*: //'
  echo -n "  drift    : "; "$ART/identity" "$old" "$new"
done
