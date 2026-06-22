"""Generate the Dhanam Store app icon and splash logo."""
from PIL import Image, ImageDraw
import math

OUT_ICON = "../../assets/branding/app_icon.png"
OUT_FG = "../../assets/branding/app_icon_foreground.png"
OUT_SPLASH = "../../assets/branding/splash_logo.png"

PRIMARY = (27, 94, 32)      # #1B5E20
PRIMARY_LT = (76, 175, 80)  # #4CAF50
ACCENT = (255, 109, 0)      # #FF6D00
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_bg(size, c1, c2):
    img = Image.new("RGB", (size, size), c1)
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            px[x, y] = lerp(c1, c2, t)
    return img


def draw_storefront(draw, cx, cy, w, color, awning_color, door_color=PRIMARY):
    """Draw a simple storefront: awning + building + door + window."""
    half = w // 2
    left = cx - half
    right = cx + half
    top = cy - half
    bottom = cy + half

    # Building body (white)
    body_top = top + int(w * 0.34)
    draw.rounded_rectangle([left, body_top, right, bottom], radius=int(w * 0.06), fill=color)

    # Awning (scalloped) — orange
    awning_h = int(w * 0.16)
    awning_top = top + int(w * 0.20)
    n = 5
    seg = w / n
    for i in range(n):
        x0 = left + i * seg
        x1 = left + (i + 1) * seg
        draw.rectangle([x0, awning_top, x1, awning_top + awning_h], fill=awning_color)
    # scallop circles along the bottom edge of awning
    r = seg / 2
    for i in range(n):
        xc = left + i * seg + r
        yc = awning_top + awning_h
        draw.ellipse([xc - r, yc - r, xc + r, yc + r], fill=awning_color)

    # Door (colored, on the left)
    door_w = int(w * 0.22)
    door_h = int(w * 0.30)
    dl = cx - int(w * 0.20)
    dr = dl + door_w
    dt = bottom - door_h
    draw.rounded_rectangle([dl, dt, dr, bottom], radius=int(door_w * 0.14), fill=door_color)
    # door handle
    hy = (dt + bottom) // 2
    draw.ellipse([dr - int(door_w * 0.28), hy - 7, dr - int(door_w * 0.28) + 14, hy + 7], fill=WHITE)

    # Window (colored square, on the right)
    win = int(w * 0.22)
    wl = cx + int(w * 0.02)
    wt = body_top + int(w * 0.07)
    draw.rounded_rectangle([wl, wt, wl + win, wt + win], radius=int(win * 0.12), fill=door_color)
    # window cross
    midx = wl + win // 2
    midy = wt + win // 2
    lw = max(4, int(w * 0.012))
    draw.line([midx, wt, midx, wt + win], fill=WHITE, width=lw)
    draw.line([wl, midy, wl + win, midy], fill=WHITE, width=lw)


def make_icon(size, with_bg=True, pad_ratio=0.0):
    if with_bg:
        img = gradient_bg(size, PRIMARY_LT, PRIMARY).convert("RGBA")
    else:
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    inset = int(size * pad_ratio)
    sf_w = int((size - 2 * inset) * 0.56)
    draw_storefront(draw, size // 2, int(size * 0.52), sf_w, WHITE, ACCENT)
    return img


# Full icon (with gradient background)
icon = make_icon(1024, with_bg=True)
icon.convert("RGB").save(OUT_ICON)

# Adaptive foreground (transparent bg, extra padding for safe zone)
fg = make_icon(1024, with_bg=False, pad_ratio=0.18)
fg.save(OUT_FG)

# Splash logo (transparent, storefront in green for white/colored bg)
splash = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
d = ImageDraw.Draw(splash)
draw_storefront(d, 512, 512, 560, WHITE, ACCENT)
splash.save(OUT_SPLASH)

print("Icons generated.")
