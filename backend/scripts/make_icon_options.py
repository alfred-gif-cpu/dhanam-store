"""Generate multiple Dhanam Store 'D' icon options in blue, plus a contact sheet."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = "../../assets/branding/options"
os.makedirs(OUT_DIR, exist_ok=True)

# Blue palette
NAVY = (13, 71, 161)      # #0D47A1
BLUE = (25, 118, 210)     # #1976D2
SKY = (33, 150, 243)      # #2196F3
CYAN = (0, 188, 212)      # #00BCD4
AMBER = (255, 167, 38)    # #FFA726
WHITE = (255, 255, 255)
INK = (15, 30, 60)

FONTS = "C:/Windows/Fonts/"
def font(name, size):
    return ImageFont.truetype(FONTS + name, size)

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def grad(size, c1, c2, diagonal=True):
    img = Image.new("RGB", (size, size), c1)
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size) if diagonal else y / size
            px[x, y] = lerp(c1, c2, t)
    return img.convert("RGBA")


def centered(draw, text, fnt, cx, cy, fill):
    box = draw.textbbox((0, 0), text, font=fnt)
    w = box[2] - box[0]
    h = box[3] - box[1]
    draw.text((cx - w / 2 - box[0], cy - h / 2 - box[1]), text, font=fnt, fill=fill)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size, size], radius=radius, fill=255)
    return m


# ---- Option builders (each returns a 1024 RGBA image) ----

def opt1():  # Bold D on blue diagonal gradient
    img = grad(S, SKY, NAVY)
    d = ImageDraw.Draw(img)
    centered(d, "D", font("ariblk.ttf", 720), S/2, S/2, WHITE)
    return img

def opt2():  # White rounded card with blue D
    img = grad(S, BLUE, NAVY)
    card = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    pad = int(S * 0.16)
    cd.rounded_rectangle([pad, pad, S-pad, S-pad], radius=int(S*0.12), fill=WHITE)
    img.alpha_composite(card)
    d = ImageDraw.Draw(img)
    centered(d, "D", font("ariblk.ttf", 560), S/2, S/2, NAVY)
    return img

def opt3():  # D in a circle badge
    img = grad(S, SKY, BLUE)
    d = ImageDraw.Draw(img)
    r = int(S * 0.34)
    d.ellipse([S/2-r, S/2-r, S/2+r, S/2+r], outline=WHITE, width=int(S*0.04))
    centered(d, "D", font("segoeuib.ttf", 520), S/2, S/2, WHITE)
    return img

def opt4():  # "Dhanam" wordmark stacked
    img = grad(S, BLUE, NAVY)
    d = ImageDraw.Draw(img)
    centered(d, "D", font("ariblk.ttf", 420), S/2, S*0.40, WHITE)
    centered(d, "DHANAM", font("arialbd.ttf", 120), S/2, S*0.72, AMBER)
    return img

def opt5():  # D with shopping bag accent (amber)
    img = grad(S, NAVY, BLUE, diagonal=False)
    d = ImageDraw.Draw(img)
    centered(d, "D", font("ariblk.ttf", 640), S*0.46, S/2, WHITE)
    # small amber bag dot
    r = int(S*0.08)
    d.ellipse([S*0.66, S*0.30, S*0.66+2*r, S*0.30+2*r], fill=AMBER)
    return img

def opt6():  # Flat blue rounded square + thin D
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = grad(S, SKY, BLUE)
    img = Image.composite(bg, img, rounded_mask(S, int(S*0.22)))
    d = ImageDraw.Draw(img)
    centered(d, "D", font("calibrib.ttf", 640), S/2, S/2, WHITE)
    return img

def opt7():  # Cyan->navy with D + underline
    img = grad(S, CYAN, NAVY)
    d = ImageDraw.Draw(img)
    centered(d, "D", font("seguibli.ttf", 600), S/2, S*0.46, WHITE)
    d.rounded_rectangle([S*0.34, S*0.74, S*0.66, S*0.78], radius=8, fill=AMBER)
    return img

def opt8():  # Monogram D inside rounded square, white on blue with shadow
    img = grad(S, BLUE, NAVY)
    d = ImageDraw.Draw(img)
    # subtle inner square
    pad = int(S*0.22)
    d.rounded_rectangle([pad, pad, S-pad, S-pad], radius=int(S*0.10), outline=WHITE, width=int(S*0.03))
    centered(d, "D", font("ariblk.ttf", 460), S/2, S/2, WHITE)
    return img

builders = [opt1, opt2, opt3, opt4, opt5, opt6, opt7, opt8]

# Save each option
for i, b in enumerate(builders, 1):
    b().convert("RGB").save(f"{OUT_DIR}/option_{i}.png")

# Build a contact sheet (4 cols x 2 rows), each cell with number label
THUMB = 320
GAP = 28
LABEL = 46
cols, rows = 4, 2
sheet_w = cols * THUMB + (cols + 1) * GAP
sheet_h = rows * (THUMB + LABEL) + (rows + 1) * GAP
sheet = Image.new("RGB", (sheet_w, sheet_h), (245, 247, 250))
sd = ImageDraw.Draw(sheet)
lbl_font = font("arialbd.ttf", 32)

for idx, b in enumerate(builders):
    r, c = divmod(idx, cols)
    x = GAP + c * (THUMB + GAP)
    y = GAP + r * (THUMB + LABEL + GAP)
    thumb = b().convert("RGB").resize((THUMB, THUMB))
    # rounded corners on thumb
    mask = rounded_mask(THUMB, 36)
    sheet.paste(thumb, (x, y), mask)
    sd.text((x + 6, y + THUMB + 4), f"Option {idx+1}", font=lbl_font, fill=(30, 40, 60))

sheet.save(f"{OUT_DIR}/_contact_sheet.png")
print("Generated 8 options + contact sheet")
