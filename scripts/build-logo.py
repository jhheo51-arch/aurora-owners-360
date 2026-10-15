"""오로라 심볼(docs/design/aurora-symbol.svg)을 앱 로고 PNG로 그린다.

cairosvg 없이 PIL만 써서 SVG와 같은 도형을 4배 크기로 그린 뒤 줄인다.
출력: force-app/main/default/contentassets/AuroraSymbol.asset (PNG 256x256)
실행: python -X utf8 scripts/build-logo.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "force-app/main/default/contentassets/AuroraSymbol.asset"
SIZE, SS = 256, 4
S = SIZE * SS / 64  # SVG 좌표(64) → 큰 캔버스 배율

NAVY = (11, 61, 145)
STOPS = [(0.0, (47, 107, 209)), (0.55, (18, 181, 166)), (1.0, (124, 227, 214))]


def lerp_color(t):
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
    return STOPS[-1][1]


def gradient(n):
    """SVG의 x1=0,y1=1 → x2=1,y2=0 (왼쪽 아래 → 오른쪽 위) 그라데이션."""
    img = Image.new("RGB", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            t = (x / n + (1 - y / n)) / 2
            px[x, y] = lerp_color(t)
    return img


def bezier(p0, p1, p2, p3, steps=200):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        pts.append(tuple(
            (u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * d) * S
            for a, b, c, d in zip(p0, p1, p2, p3)))
    return pts


def main():
    n = SIZE * SS
    canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(canvas).rounded_rectangle([0, 0, n - 1, n - 1], radius=14 * S, fill=NAVY)

    grad = gradient(256).resize((n, n), Image.BILINEAR).convert("RGBA")
    arcs = [  # (시작, 제어1, 제어2, 끝, 두께, 불투명도)
        ((10, 46), (20, 22), (44, 22), (54, 46), 5, 1.0),
        ((17, 46), (25, 31), (39, 31), (47, 46), 4, 0.75),
        ((24, 46), (29, 39), (35, 39), (40, 46), 3, 0.5),
    ]
    for p0, p1, p2, p3, w, op in arcs:
        mask = Image.new("L", (n, n), 0)
        d = ImageDraw.Draw(mask)
        r = w * S / 2
        # 곡선 위에 원을 촘촘히 찍어 매끈한 두께 + 둥근 끝(stroke-linecap="round")
        for x, y in bezier(p0, p1, p2, p3, steps=1500):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        mask = mask.point(lambda v: round(v * op))
        canvas.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(canvas)
    cx, cy, r = 32 * S, 16 * S, 3 * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(OUT, format="PNG", optimize=True)
    print(f"{OUT.relative_to(ROOT)} ({OUT.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
