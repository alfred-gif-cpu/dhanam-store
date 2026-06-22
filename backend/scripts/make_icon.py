"""Generate the Dhanam Stores app icon (blue basket + wordmark)."""
from PIL import Image, ImageDraw, ImageFont

OUT_ICON = "../../assets/branding/app_icon.png"
OUT_FG = "../../assets/branding/app_icon_foreground.png"
OUT_SPLASH = "../../assets/branding/splash_logo.png"

SKY = (33, 150, 243)      # #2196F3
BLUE = (21, 101, 192)     # #1565C0
NAVY = (13, 71, 161)      # #0D47A1
WHITE = (255, 255, 255)

FONTS = "C:/Windows/Fonts/"
def font(name, size):
    return ImageFont.truetype(FONTS + name, size)

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def grad(size, c1, c2):
    img = Image.new("RGB", (size, size), c1)
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            px[x, y] = lerp(c1, c2, t)
    return img.convert("RGBA")


def centered(draw, text, fnt, cx, cy, fill):
    box = draw.textbbox((0, 0), text, font=fnt)
    w = box[2] - box[0]
    h = box[3] - box[1]
    draw.text((cx - w / 2 - box[0], cy - h / 2 - box[1]), text, font=fnt, fill=fill)


def draw_basket(draw, cx, cy, w, basket_color, line_color):
    """Draw a shopping basket: handle + trapezoid body + slats."""
    half = w / 2
    top_y = cy - w * 0.42
    bot_y = cy + w * 0.40
    # handle (squared)
    hw = w * 0.30
    hh = w * 0.30
    lw = max(6, int(w * 0.075))
    draw.line(
        [(cx - hw / 2, top_y), (cx - hw / 2, top_y - hh),
         (cx + hw / 2, top_y - hh), (cx + hw / 2, top_y)],
        fill=basket_color, width=lw, joint="curve",
    )
    # body trapezoid
    top_l, top_r = cx - half, cx + half
    bot_l, bot_r = cx - half * 0.72, cx + half * 0.72
    draw.polygon(
        [(top_l, top_y), (top_r, top_y), (bot_r, bot_y), (bot_l, bot_y)],
        fill=basket_color,
    )
    # vertical slats
    slat_w = max(5, int(w * 0.06))
    for fx in (-0.22, 0.0, 0.22):
        x = cx + half * fx
        draw.line([(x, top_y + w * 0.10), (x + (bot_y - top_y) * 0 , bot_y - w * 0.06)],
                  fill=line_color, width=slat_w)


def compose(bg, basket_color, line_color, text_color, with_bg=True, scale=1.0):
    if with_bg:
        img = grad(S, SKY, BLUE)
    else:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bw = int(S * 0.34 * scale)
    cx = S / 2
    cy = S * 0.40
    draw_basket(d, cx, cy, bw, basket_color, line_color)
    centered(d, "Dhanam", font("arialbd.ttf", int(S * 0.115 * scale)), cx, S * 0.66, text_color)
    centered(d, "STORES", font("arialbd.ttf", int(S * 0.066 * scale)), cx, S * 0.775, text_color)
    return img


# Full icon: blue gradient bg, white basket + white text
icon = compose(None, WHITE, SKY, WHITE, with_bg=True)
icon.convert("RGB").save(OUT_ICON)

# Adaptive foreground: transparent bg, slightly smaller for safe zone
fg = compose(None, WHITE, SKY, WHITE, with_bg=False, scale=0.82)
fg.save(OUT_FG)

# Splash logo: white basket + white text on transparent (shown on blue splash)
splash = compose(None, WHITE, (33, 150, 243, 0), WHITE, with_bg=False)
splash.save(OUT_SPLASH)

print("Dhanam Stores icon generated.")
