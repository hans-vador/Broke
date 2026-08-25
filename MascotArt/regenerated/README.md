# Regenerating a character

Blueberry and peach shipped with their legs meeting the body end-on, leaving a
visible gap and a hard corner. Three attempts to correct that in image space all
made things worse (see `../retired_layered_rig/dont_edit_the_art/`). The fix that
worked was regenerating the two renders with Codex image gen.

    codex exec --skip-git-repo-check "$(cat p_bb.txt)" -i blueberry_src.png leg_reference.png

What made it work:

* **Two reference images.** The character being fixed goes first; a character
  whose leg join already looks right (the strawberry) goes second, explicitly
  scoped as "copy this junction, nothing else about it".
* **Enumerate what must NOT change** — body silhouette, colour, texture, the face
  down to the eye highlights, arm angles, leg length and thickness, lighting,
  camera. Then state the single thing to change. Describing only the desired
  change gets you a redesigned character.

## Always gate the result

`evaluate.sh` checks both things that can go wrong, and a failure on either means
keeping the original:

    ./evaluate.sh blueberry peach

* `legcheck.swift` — is the defect actually fixed? (gap at each leg's centre column)
* `identity.swift` — has the character drifted? (bbox, mean colour, area, and
  silhouette IoU against the original)

The accepted results were: blueberry 16px gap -> 0px at 96.7% silhouette IoU;
peach 8/6px -> 1/0px at 99.5%. Colours were unchanged in both. Anything much
below ~95% IoU is a different character and should be rejected.
