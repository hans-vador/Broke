#!/usr/bin/env python3
"""
Broke mascot rigs, built on the INTACT character art.

Earlier versions composited separate arm/leg PNGs behind a body PNG. That can
never read as attached: the limb and body are different renders, so there is no
continuous surface and no contact shading - the limb just vanishes behind a hard
silhouette edge. Every attempt to fix it by moving joints around treated the
symptom.

So this rig animates `<fruit>_char.png` - the complete sculpted character, limbs
already attached - as a single deformable body, and gets its life from animation
principles instead of from swinging parts:

  * ANCHOR AT THE FEET. Squash and stretch are applied about the ground contact
    point, so squashing presses the character down onto the floor and stretching
    pulls it up off it. Anchoring at the image centre (the obvious choice) makes
    it look like it is being scaled, not moving.
  * SQUASH AND STRETCH with volume roughly preserved - x widens as y shortens.
  * ASYMMETRIC TIMING. Fast out of a squash, slow float at the apex, accelerate
    into the fall, hard fast squash on impact. Even easing everywhere is the
    single biggest reason mascot animation reads as dead.
  * A GROUND SHADOW that shrinks and fades as the character lifts. This is what
    actually sells "grounded" - without it a bob just looks like drifting.

Decode-safe for lottie-ios 4.6.1: top-level image + shape layers only, no
precomps, only the el/sr/fl primitives already proven in this app.
"""

import json
import math
import os

CANVAS = 1024
FR = 60

CHAR_HEIGHT = 740.0     # rendered character height, canvas px
GROUND_Y = 944.0        # where the feet (and the shadow) sit
CENTRE_X = 512.0

# --- easing. Naming is by the shape of the motion, not the Lottie jargon.
SMOOTH = ({"x": [0.42], "y": [0.0]}, {"x": [0.58], "y": [1.0]})   # gentle both ends
FLOAT = ({"x": [0.18], "y": [0.0]}, {"x": [0.36], "y": [1.0]})    # leaves fast, floats in
DROP = ({"x": [0.70], "y": [0.0]}, {"x": [0.90], "y": [1.0]})     # creeps out, accelerates
SNAP = ({"x": [0.20], "y": [0.0]}, {"x": [0.28], "y": [1.0]})     # impact
HOLD = ({"x": [0.60], "y": [0.0]}, {"x": [0.40], "y": [1.0]})     # near-linear settle

EASES = {"smooth": SMOOTH, "float": FLOAT, "drop": DROP, "snap": SNAP, "hold": HOLD}


def static(v):
    return {"a": 0, "k": v}


def kf(points, ease="smooth"):
    """points: [(t, value, [ease])] -> legacy s/e keyframe list.

    A per-keyframe ease is what buys the asymmetric timing; a single ease for a
    whole track is what makes motion look mechanical.
    """
    out = []
    for n, pt in enumerate(points):
        t, v = pt[0], pt[1]
        this_ease = pt[2] if len(pt) > 2 else ease
        v = list(v) if isinstance(v, (list, tuple)) else [v]
        if n == len(points) - 1:
            out.append({"t": t, "s": v})
        else:
            nxt = points[n + 1][1]
            nxt = list(nxt) if isinstance(nxt, (list, tuple)) else [nxt]
            o, i = EASES[this_ease]
            out.append({"t": t, "s": v, "e": nxt, "o": o, "i": i})
    return {"a": 1, "k": out}


def img_layer(ind, name, ref, op, *, anchor, pos, scale, rot=None, opacity=None,
              parent=None):
    layer = {"ddd": 0, "ind": ind, "ty": 2, "nm": name, "refId": ref, "sr": 1,
             "ks": {"o": opacity or static(100), "r": rot or static(0), "p": pos,
                    "a": static([anchor[0], anchor[1], 0]), "s": scale},
             "ao": 0, "ip": 0, "op": op, "st": 0, "bm": 0}
    if parent is not None:
        layer["parent"] = parent
    return layer


def shape_layer(ind, name, shapes, op, *, pos, scale, rot=None, opacity=None,
                parent=None, anchor=(0, 0)):
    layer = {"ddd": 0, "ind": ind, "ty": 4, "nm": name, "sr": 1,
             "ks": {"o": opacity or static(100), "r": rot or static(0), "p": pos,
                    "a": static([anchor[0], anchor[1], 0]), "s": scale},
             "shapes": shapes, "ao": 0, "ip": 0, "op": op, "st": 0, "bm": 0}
    if parent is not None:
        layer["parent"] = parent
    return layer


def ellipse(w, h, rgb, name="e", opacity=100):
    return [
        {"ty": "el", "d": 1, "p": static([0, 0]), "s": static([w, h]), "nm": name},
        {"ty": "fl", "c": static([rgb[0], rgb[1], rgb[2], 1]),
         "o": static(opacity), "r": 1, "bm": 0, "nm": name + " fill"},
    ]


def star(outer, inner, points, rgb, name="s"):
    return [
        {"ty": "sr", "d": 1, "sy": 1, "pt": static(points), "p": static([0, 0]),
         "r": static(0), "or": static(outer), "os": static(0),
         "ir": static(inner), "is": static(0), "nm": name},
        {"ty": "fl", "c": static([rgb[0], rgb[1], rgb[2], 1]),
         "o": static(100), "r": 1, "bm": 0, "nm": name + " fill"},
    ]


def rgb01(c):
    return [round(c[0] / 255, 6), round(c[1] / 255, 6), round(c[2] / 255, 6)]


class Char:
    """Placement for one character, anchored at its ground contact point."""

    def __init__(self, geom):
        bx0, by0, bx1, by1 = geom["bbox"]
        self.bbox = geom["bbox"]
        self.eyes = geom["eyes"]
        self.mouth = geom.get("mouth")
        self.colour = rgb01(geom["color"])
        self.w, self.h = bx1 - bx0, by1 - by0
        # Anchor is the FEET, not the image centre: squash must press the
        # character into the floor rather than shrink it in place.
        self.anchor = ((bx0 + bx1) / 2, by1)
        self.scale = CHAR_HEIGHT / self.h * 100
        self.s = self.scale / 100
        self.rw = self.w * self.s
        self.top = GROUND_Y - CHAR_HEIGHT

    def to_canvas(self, x, y):
        return ((x - self.anchor[0]) * self.s + CENTRE_X,
                (y - self.anchor[1]) * self.s + GROUND_Y)


CHAR_IND = 100          # fixed id so eyelids and arms can parent to the torso

# Arms are cut from the SAME render as the torso (see cutarms.swift), so their
# shading matches exactly and at rest they recomposite to the original image.
# They rotate a few degrees about a pivot buried under the torso, which is what
# gives the characters secondary motion without ever exposing a seam.
ARM_DRAG = 6.5          # degrees of trail at peak lift
ARM_SWAY = 2.0          # degrees of idle sway, so calm fruits still have life
ARM_LAG = 7             # frames the arms trail the body by


def body_tracks(char, beats):
    """beats: [(t, dx, dy, sx, sy, rot[, ease])] -> position / scale / rotation.

    dx,dy are canvas px; sx,sy are fractional scale deltas; rot is degrees.
    """
    S = char.scale
    pos, scl, rot = [], [], []
    for b in beats:
        t, dx, dy, sx, sy, r = b[:6]
        ease = b[6] if len(b) > 6 else "smooth"
        pos.append((t, [round(CENTRE_X + dx, 1), round(GROUND_Y + dy, 1), 0], ease))
        scl.append((t, [round(S * (1 + sx), 2), round(S * (1 + sy), 2), 100], ease))
        rot.append((t, [round(r, 2)], ease))
    return pos, scl, rot


def sample_dy(beats, t, loop):
    """Body dy at time t, wrapping around the loop so arm drag stays seamless."""
    t = t % loop
    pts = [(b[0], b[2]) for b in beats]
    if t <= pts[0][0]:
        return pts[0][1]
    for n in range(len(pts) - 1):
        t0, v0 = pts[n]
        t1, v1 = pts[n + 1]
        if t0 <= t <= t1:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return v0 + (v1 - v0) * f
    return pts[-1][1]


def arm_layers(char, ind, op, beats, pivots, drag=ARM_DRAG, sway=ARM_SWAY):
    """Left/right arm layers with drag.

    The arms trail the body: when it rises they hang back, when it lands they
    swing through. That lag is what reads as "natural" - arms moving in lockstep
    with the body look glued on.
    """
    # Normalise against the largest excursion in EITHER direction. Using only
    # the lift (-b[2]) breaks any pose that never leaves the ground: on duty is
    # a sway with dy of 4,4,0,4,4, so max(-dy) is 0, peak clamps to 1.0, and the
    # division stops normalising — rot becomes drag x dy-in-pixels (26 degrees)
    # instead of drag x fraction (6.5). At 26 degrees held continuously the arm
    # swings clear of the torso and exposes the stub the cut left behind, so the
    # locked screen showed two pairs of arms.
    peak = max(1.0, max(abs(b[2]) for b in beats))
    times = sorted({b[0] for b in beats} |
                   {(beats[i][0] + beats[i + 1][0]) // 2 for i in range(len(beats) - 1)})
    if times[-1] != op:
        times.append(op)
    layers = []
    for side, key, sign in (("L", "L", -1.0), ("R", "R", 1.0)):
        pv = pivots[key]
        pts = []
        for t in times:
            lift = -sample_dy(beats, t - ARM_LAG, op)
            rot = sign * drag * (lift / peak)
            rot += sign * sway * math.sin(2 * math.pi * t / op)
            pts.append((t, [round(rot, 2)]))
        layers.append(img_layer(
            ind, f"arm{side}", f"arm{side}", op,
            anchor=(pv[0], pv[1]), pos=static([pv[0], pv[1], 0]),
            scale=static([100, 100, 100]), rot=kf(pts), parent=CHAR_IND))
        ind += 1
    return layers, ind


def shadow_layers(char, ind, op, beats):
    """A soft contact shadow that shrinks and fades as the character lifts.

    Without this a bob reads as the character drifting in space rather than
    pushing off a floor.
    """
    w = char.rw * 0.62
    lifts = [-b[2] for b in beats]
    peak = max(max(lifts), 1.0)
    scl, opa = [], []
    for b in beats:
        t = b[0]
        lift = max(0.0, -b[2])
        squash = -b[4]                      # squashing spreads the contact patch
        k = 1.0 - 0.42 * (lift / peak) + 0.5 * squash
        ease = b[6] if len(b) > 6 else "smooth"
        scl.append((t, [round(k * 100, 1), round(k * 100, 1), 100], ease))
        opa.append((t, [round(max(6, 30 - 17 * (lift / peak)), 1)], ease))
    layers = []
    # two stacked ellipses fake a soft edge (no blur available in Lottie here)
    for n, (mul, alpha) in enumerate(((1.0, 46), (0.62, 62))):
        layers.append(shape_layer(
            ind, f"shadow{n}",
            ellipse(round(w * mul, 1), round(w * mul * 0.26, 1), [0.16, 0.10, 0.12],
                    f"contact shadow {n}", opacity=alpha),
            op, pos=static([CENTRE_X, GROUND_Y + 6, 0]),
            scale=kf(scl), opacity=kf(opa)))
        ind += 1
    return layers, ind


def eyelid_layers(char, ind, op, closes, squint=0.0, wink_right_only=False):
    """Body-coloured lids that shut the eyes.

    Parented to the character so they inherit every bit of squash, stretch and
    lean automatically - baking their transform separately makes them slide off
    the face the moment the body deforms.
    """
    e = char.eyes
    ew, eh = e["w"] * 1.04, max(e["h"], 30) * 1.12
    layers = []
    for side, (ex, ey) in (("L", (e["lx"], e["ly"])), ("R", (e["rx"], e["ry"]))):
        pts = [(0, [100, squint * 100, 100])]
        for c in closes:
            t0, t1 = (c if isinstance(c, (tuple, list)) else (c, c + 5))
            if wink_right_only and side == "L":
                continue
            pts += [(max(1, t0 - 4), [100, squint * 100, 100], "snap"),
                    (t0, [100, 100, 100], "snap"),
                    (t1, [100, 100, 100], "smooth"),
                    (t1 + 7, [100, squint * 100, 100], "smooth")]
        pts.append((op, [100, squint * 100, 100]))
        seen = {}
        for p in pts:
            seen[p[0]] = p
        pts = sorted(seen.values(), key=lambda p: p[0])
        layers.append(shape_layer(
            ind, f"blink{side}",
            ellipse(round(ew, 1), round(eh, 1), char.colour, f"{side} eyelid"),
            op, pos=static([ex, ey, 0]), scale=kf(pts), parent=CHAR_IND))
        ind += 1
    return layers, ind


def sparkles(char, ind, op, times, colour=(1, 0.86, 0.26), count=5):
    bx0, by0, bx1, by1 = char.bbox
    spots = [(bx0 - 30, by0 + char.h * 0.22), (bx1 + 30, by0 + char.h * 0.34),
             (bx0 + char.w * 0.16, by0 - 34), (bx1 + 12, by0 + char.h * 0.08),
             (bx0 - 46, by0 + char.h * 0.52), (bx1 + 44, by0 + char.h * 0.62)]
    layers = []
    for n in range(min(count, len(spots))):
        sx, sy = char.to_canvas(*spots[n])
        t0 = times[n % len(times)] + n * 4
        pts = [(0, [0, 0, 100]), (t0, [0, 0, 100], "snap"),
               (t0 + 6, [124, 124, 100], "snap"), (t0 + 13, [88, 88, 100]),
               (t0 + 24, [0, 0, 100]), (op, [0, 0, 100])]
        seen = {}
        for p in pts:
            seen[p[0]] = p
        pts = sorted(seen.values(), key=lambda p: p[0])
        layers.append(shape_layer(
            ind, f"sparkle{n}", star(17, 7, 5, list(colour), f"sparkle {n}"), op,
            pos=static([round(sx, 1), round(sy, 1), 0]), scale=kf(pts),
            rot=kf([(0, [0]), (op, [150])])))
        ind += 1
    return layers, ind


def blush(char, ind, op, window):
    e = char.eyes
    t0, t1 = window
    layers = []
    for side, ex in (("L", e["lx"] - e["w"] * 0.72), ("R", e["rx"] + e["w"] * 0.72)):
        ey = e["ly"] + e["h"] * 0.92
        pts = [(0, [0, 0, 100]), (t0, [0, 0, 100]), (t0 + 14, [100, 100, 100]),
               (t1, [100, 100, 100]), (t1 + 16, [0, 0, 100]), (op, [0, 0, 100])]
        opa = [(0, [0]), (t0, [0]), (t0 + 14, [62]), (t1, [62]),
               (t1 + 16, [0]), (op, [0])]
        seen = {}
        for p in pts:
            seen[p[0]] = p
        pts = sorted(seen.values(), key=lambda p: p[0])
        seen = {}
        for p in opa:
            seen[p[0]] = p
        opa = sorted(seen.values(), key=lambda p: p[0])
        layers.append(shape_layer(
            ind, f"blush{side}",
            ellipse(round(e["w"] * 0.96, 1), round(e["h"] * 0.54, 1),
                    [0.97, 0.38, 0.42], f"{side} blush"),
            op, pos=static([ex, ey, 0]), scale=kf(pts), opacity=kf(opa),
            parent=CHAR_IND))
        ind += 1
    return layers, ind


def tongue(char, ind, op, window):
    # Anchor to the DETECTED mouth. Deriving this from eye spacing and height
    # put the lemon's tongue well below its mouth - the faces aren't all
    # proportioned the same way.
    m = char.mouth
    e = char.eyes
    if m:
        cx = m["cx"]
        cy = m["bottom"] - m["h"] * 0.15
        w = m["w"] * 0.62
    else:
        cx = (e["lx"] + e["rx"]) / 2
        cy = e["ly"] + e["h"] * 1.5
        w = e["w"] * 0.7
    t0, t1 = window
    pts = [(0, [0, 0, 100]), (t0, [0, 0, 100], "snap"), (t0 + 5, [116, 120, 100], "snap"),
           (t0 + 11, [100, 100, 100]), (t1, [100, 100, 100]), (t1 + 8, [0, 0, 100]),
           (op, [0, 0, 100])]
    seen = {}
    for p in pts:
        seen[p[0]] = p
    pts = sorted(seen.values(), key=lambda p: p[0])
    return [shape_layer(ind, "sillyTongue",
                        ellipse(round(w, 1), round(w * 0.72, 1), [0.95, 0.34, 0.45], "tongue"),
                        op, pos=static([cx, cy, 0]), scale=kf(pts), parent=CHAR_IND)], ind + 1


def zzz(char, ind, op, start, end):
    bx0, by0, bx1, by1 = char.bbox
    layers = []
    for n, (size, dx, dy, delay) in enumerate(((46, 0, 0, 0), (34, 54, -70, 30),
                                               (25, 96, -132, 60))):
        sx, sy = char.to_canvas(bx1 - 40 + dx, by0 + char.h * 0.16 + dy)
        t0 = start + delay
        t1 = min(end, t0 + 130)
        pts = [(0, [0, 0, 100]), (t0, [0, 0, 100]), (t0 + 16, [100, 100, 100]),
               (t1 - 18, [100, 100, 100]), (t1, [0, 0, 100]), (op, [0, 0, 100])]
        pos = [(0, [round(sx, 1), round(sy, 1), 0]), (t0, [round(sx, 1), round(sy, 1), 0]),
               (t1, [round(sx + 26, 1), round(sy - 62, 1), 0]),
               (op, [round(sx + 26, 1), round(sy - 62, 1), 0])]
        opa = [(0, [0]), (t0, [0]), (t0 + 16, [88]), (t1 - 20, [88]), (t1, [0]), (op, [0])]
        for arr in (pts, pos, opa):
            seen = {}
            for p in arr:
                seen[p[0]] = p
            arr[:] = sorted(seen.values(), key=lambda p: p[0])
        layers.append(shape_layer(ind, f"Zzz {n}",
                                  ellipse(size, size * 1.18, [0.35, 0.39, 0.62], f"Zzz {n}"),
                                  op, pos=kf(pos), scale=kf(pts), opacity=kf(opa),
                                  rot=kf([(0, [-13]), (op, [15])])))
        ind += 1
    return layers, ind


def comp(name, op, fruit, layers):
    return {"v": "5.12.2", "fr": FR, "ip": 0, "op": op, "w": CANVAS, "h": CANVAS,
            "nm": name, "ddd": 0,
            "assets": [
                {"id": "char", "w": CANVAS, "h": CANVAS, "u": "",
                 "p": f"{fruit}_torso.png", "e": 0},
                {"id": "armL", "w": CANVAS, "h": CANVAS, "u": "",
                 "p": f"{fruit}_armL.png", "e": 0},
                {"id": "armR", "w": CANVAS, "h": CANVAS, "u": "",
                 "p": f"{fruit}_armR.png", "e": 0},
            ],
            "layers": layers}


# ---------------------------------------------------------------- personality
# beats: (t, dx, dy, scaleX delta, scaleY delta, rotation[, ease])
# Because the anchor is at the feet, a positive scaleY grows the character
# UPWARD - so peak height is dy plus the stretch. main() asserts the headroom.

PERSONA = {
    # friendly: a bouncy double-hop, then settles and breathes
    "strawberry": dict(loop=200, blinks=[(150, 156)], sig=None, beats=[
        (0, 0, 0, 0, 0, 0), (16, 0, 0, .05, -.07, 0, "snap"),
        (30, 0, -84, -.05, .07, 0, "float"), (44, 0, -102, -.02, .03, 0, "drop"),
        (58, 0, 0, .08, -.11, 0, "snap"), (68, 0, -38, -.03, .04, 0, "float"),
        (80, 0, 0, .05, -.07, 0, "snap"), (90, 0, -11, -.02, .02, 0),
        (100, 0, 0, .01, -.02, 0), (130, 0, -8, -.01, .02, -1.2),
        (165, 0, 0, .015, -.02, 1.0), (200, 0, 0, 0, 0, 0)]),

    # unbothered: slow wide sway, lets a glint do the talking
    "orange": dict(loop=220, blinks=[(190, 196)], sig="sparkle", beats=[
        (0, 0, 0, 0, 0, 0), (55, -14, -10, -.02, .03, -2.8),
        (110, 14, 0, .03, -.03, 0), (165, 14, -10, -.02, .03, 2.8),
        (220, 0, 0, 0, 0, 0)]),

    # can't sit still: fast twitchy jitters, tongue out
    "lemon": dict(loop=150, blinks=[(120, 125)], sig="tongue", beats=[
        (0, 0, 0, 0, 0, 0), (10, -6, -18, -.03, .04, -3, "snap"),
        (20, 6, 0, .04, -.05, 2.4, "snap"), (30, -4, -14, -.02, .03, -2, "snap"),
        (42, 5, 0, .035, -.045, 2.6, "snap"), (54, -7, -22, -.035, .05, -3.4, "snap"),
        (66, 6, 0, .045, -.055, 2.2, "snap"), (78, -3, -10, -.015, .02, -1.4, "snap"),
        (90, 4, 0, .03, -.04, 1.8, "snap"), (110, 0, -6, -.01, .015, 0),
        (150, 0, 0, 0, 0, 0)]),

    # all hips, permanently mid-dance
    "pear": dict(loop=180, blinks=[(160, 166)], sig=None, beats=[
        (0, 0, 0, 0, 0, 0), (30, -22, -6, -.02, .03, -6),
        (60, 22, 0, .035, -.035, 5.4), (90, -24, -8, -.025, .035, -6.6),
        (120, 23, 0, .035, -.035, 5.8), (150, -10, -4, -.01, .015, -3),
        (180, 0, 0, 0, 0, 0)]),

    # shy: leans away, blushes, blinks a lot
    "apple": dict(loop=200, blinks=[(70, 76), (175, 181)], sig="blush", beats=[
        (0, 0, 0, 0, 0, 0), (40, -8, -10, -.02, .025, 4.2),
        (80, 6, 0, .025, -.025, -1.4), (120, -9, -8, -.015, .02, 4.8),
        (160, 5, 0, .02, -.02, -1.0), (200, 0, 0, 0, 0, 0)]),

    # perky: snappy double bounce, then a wink
    "blueberry": dict(loop=180, blinks=[(120, 128)], sig="wink", beats=[
        (0, 0, 0, 0, 0, 0), (14, 0, 0, .06, -.08, 0, "snap"),
        (26, 0, -92, -.06, .07, 0, "float"), (38, 0, -104, -.02, .03, 0, "drop"),
        (50, 0, 0, .09, -.12, 0, "snap"), (60, 0, -40, -.03, .04, 0, "float"),
        (72, 0, 0, .06, -.08, 0, "snap"), (84, 0, -13, -.02, .02, 0),
        (96, 0, 0, .01, -.015, 0), (180, 0, 0, 0, 0, 0)]),

    # heavy: commits to one big hop and lands with a thud
    "watermelon": dict(loop=210, blinks=[(180, 186)], sig="dust", beats=[
        (0, 0, 0, 0, 0, 0), (24, 0, 0, .08, -.11, 0, "snap"),
        (44, 0, -100, -.07, .07, 0, "float"), (60, 0, -116, -.03, .04, 0, "drop"),
        (76, 0, 0, .12, -.15, 0, "snap"), (88, 0, -24, -.04, .05, 0, "float"),
        (100, 0, 0, .06, -.08, 0, "snap"), (112, 0, -8, -.02, .02, 0),
        (126, 0, 0, .01, -.01, 0), (210, 0, 0, 0, 0, 0)]),

    # dozes off, sleeps with drifting Zzz, then jolts awake
    "peach": dict(loop=360, blinks=[(100, 302)], sig="sleep", beats=[
        (0, 0, 0, 0, 0, 0), (40, 4, 0, .01, -.015, 1.6),
        (90, 8, 6, .03, -.04, 3.6), (140, 10, 10, .04, -.05, 4.6),
        (200, 6, 2, -.02, .03, 4.2), (260, 10, 12, .045, -.055, 4.8),
        (300, 7, 4, -.015, .025, 4.2),
        (310, -6, -58, -.07, .07, -4, "snap"), (322, 3, 0, .08, -.10, 1.6, "snap"),
        (334, -2, -14, -.02, .03, -.8), (348, 1, 0, .01, -.015, .4),
        (360, 0, 0, 0, 0, 0)]),
}

# Locked: planted, low, watchful. Weight forward, minimal float, narrowed eyes.
DUTY_BEATS = [
    (0, 0, 4, .035, -.045, 0),
    (48, -5, 4, .03, -.04, -2.2),
    (96, 0, 0, .045, -.055, 0),
    (144, 5, 4, .03, -.04, 2.2),
    (190, 0, 4, .035, -.045, 0),
]

# One-shot celebration: deep anticipation, big air, hard landing, settle.
CELEBRATE_BEATS = [
    (0, 0, 0, 0, 0, 0),
    (12, 0, 6, .09, -.12, 0, "snap"),
    (30, 0, -96, -.07, .07, -4, "float"),
    (44, 0, -112, -.03, .03, 2, "drop"),
    (58, 0, 0, .14, -.17, 0, "snap"),
    (70, 0, -44, -.05, .06, 0, "float"),
    (82, 0, 0, .08, -.10, 0, "snap"),
    (92, 0, -14, -.02, .03, 0),
    (104, 0, 0, .02, -.03, 0),
    (116, 0, 0, 0, 0, 0),
]


def build(fruit, char, kind):
    p = PERSONA[fruit]
    if kind == "idle":
        op, beats, blinks, sig = p["loop"], p["beats"], p["blinks"], p["sig"]
        squint = 0.0
    elif kind == "onDuty":
        op, beats, blinks, sig = 190, DUTY_BEATS, [(150, 156)], None
        squint = 0.46
    else:
        op, beats, blinks, sig = 116, CELEBRATE_BEATS, [(96, 101)], "celebrate"
        squint = 0.0

    ind = 1
    front = []
    if sig == "sparkle":
        front, ind = sparkles(char, ind, op, [30, 120])
    elif sig == "dust":
        front, ind = sparkles(char, ind, op, [78, 82], colour=(1, .58, .42), count=4)
    elif sig == "celebrate":
        front, ind = sparkles(char, ind, op, [34, 40, 46], colour=(1, .84, .34), count=6)
    elif sig == "blush":
        front, ind = blush(char, ind, op, (50, 150))
    elif sig == "tongue":
        front, ind = tongue(char, ind, op, (40, 100))
    elif sig == "sleep":
        front, ind = zzz(char, ind, op, 150, 300)

    lids, ind = eyelid_layers(char, ind, op, blinks, squint=squint,
                              wink_right_only=(sig == "wink"))
    pos, scl, rot = body_tracks(char, beats)
    body = img_layer(CHAR_IND, "torso", "char", op, anchor=char.anchor,
                     pos=kf(pos), scale=kf(scl), rot=kf(rot))
    arms, ind = arm_layers(char, ind, op, beats, PIVOTS[fruit],
                           drag=ARM_DRAG * (1.5 if kind == "celebrate" else 1.0))
    shadow, ind = shadow_layers(char, ind, op, beats)

    name = {"idle": "idle", "onDuty": "on duty", "celebrate": "celebrate"}[kind]
    # arms sit behind the torso so their cut edge stays buried
    return comp(f"{fruit} {name}", op, fruit, front + lids + [body] + arms + shadow)


def headroom(char, beats):
    """Lowest point the character's top reaches. Stretch grows it upward from
    the feet anchor, so peak height is dy PLUS the stretch, not just dy."""
    return min(GROUND_Y + b[2] - CHAR_HEIGHT * (1 + b[4]) for b in beats)


PIVOTS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     "cutarms_pivots.json")))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    geom = json.load(open(os.path.join(here, "chars.json")))
    # Derived from this file's location rather than hardcoded: the absolute
    # path this used to carry pointed at ~/Desktop/Broke, so re-running the
    # generator from the repo's current home failed outright.
    out_dir = os.path.normpath(os.path.join(here, "..", "..", "Broke", "MascotLottie"))
    worst = 1e9
    for fruit in PERSONA:
        char = Char(geom[f"{fruit}_char"])
        for kind in ("idle", "onDuty", "celebrate"):
            clip = build(fruit, char, kind)
            with open(os.path.join(out_dir, f"{fruit}_{kind}.json"), "w") as f:
                json.dump(clip, f, separators=(",", ":"))
        hr = min(headroom(char, PERSONA[fruit]["beats"]),
                 headroom(char, CELEBRATE_BEATS))
        worst = min(worst, hr)
        flag = "  <-- CLIPS" if hr < 0 else ""
        print(f"  {fruit:11s} loop={PERSONA[fruit]['loop']:3d}f  headroom={hr:6.1f}px{flag}")
    print(f"done (tightest headroom {worst:.1f}px of {CANVAS})")
