"""App Store marketing screenshots for Lumora.

Each slide: a night-sky background in Lumora's palette (deep space, violet and
pink nebulae, stars), a serif-italic headline and a short line under it, then
the real app screen inside a phone frame that runs off the bottom edge.

    python3 Marketing/Screenshots/compose.py                      # everything, every language
    python3 Marketing/Screenshots/compose.py --lang de --device iphone

iPhone: raw screens from AppStore/screenshots/<lang>/ (1320x2868, iPhone 17 Pro
Max simulator); output AppStore/marketing/<lang>/6.9/ (1320x2868) and
AppStore/marketing/<lang>/6.3/ (1206x2622).
iPad 13" and iPhone Duo: raw screens from AppStore/screenshots/<lang>/<device>/;
output AppStore/marketing/<lang>/<device>/ (2064x2752 and 1398x2034, the Duo's
cover screen). Apple Watch: plain screens from AppStore/screenshots/<lang>/watch/
with the clock set to 9:41, to AppStore/marketing/<lang>/watch/ (416x496).

English and Turkish copy is drawn with Pillow; the other languages (copy.py)
with Core Text through text.swift, which shapes Arabic, Thai and CJK.
A slide is left out of a language that has no copy or no raw screen for it.
"""
import argparse
import math
import random
import subprocess
import tempfile
from pathlib import Path

from copy_text import COPY

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "AppStore" / "screenshots"
OUT = ROOT / "AppStore" / "marketing"
W, H = 1320, 2868

SERIF = "/System/Library/Fonts/NewYorkItalic.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

DEEP = (9, 11, 31)
INDIGO = (21, 25, 54)
VIOLET = (139, 124, 255)
PINK = (255, 143, 184)
CYAN = (112, 225, 245)
GOLD = (255, 213, 138)
WHITE = (247, 247, 255)
LAVENDER = (185, 188, 227)

# (raw file, glow colour, nebula colours, headline, subheadline) per language;
# a slide without a language is left out of that language's set.
# The iPad and Duo sets reuse these, with their own raw names, minus the arrival.
SLIDES = [
    ("01-home.png", VIOLET, (VIOLET, PINK), {
        "en": ("Every focus lights a star", "Pomodoro sessions that grow a universe of your own."),
        "tr": ("Her odak bir yıldız yakar", "Pomodoro seansların kendi evrenini büyütsün."),
    }),
    ("02-focus.png", GOLD, (VIOLET, CYAN), {
        "en": ("Calm, beautiful focus", "A gentle timer and soft soundscapes. Nothing else."),
        "tr": ("Sakin, güzel bir odak", "Nazik bir zamanlayıcı ve yumuşak sesler. Başka hiçbir şey."),
    }),
    # English only.
    ("11-together.png", CYAN, (CYAN, VIOLET), {
        "en": ("Focus with your friends", "Up to eight of you, each at a desk in one shared galaxy."),
    }),
    ("03-completion.png", GOLD, (PINK, VIOLET), {
        "en": ("Watch your star be born", "Finish a session and see it take its place in your sky."),
        "tr": ("Yıldızının doğuşunu izle", "Seansı bitir, yıldızın gökyüzünde yerini alsın."),
    }),
    ("08-universe.png", CYAN, (VIOLET, PINK), {
        "en": ("A universe made of your attention", "Constellations, planets and galaxies, all from your sessions."),
        "tr": ("Dikkatinden doğan bir evren", "Takımyıldızlar, gezegenler, galaksiler; hepsi senin seanslarından."),
    }),
    ("04-odyssey.png", VIOLET, (CYAN, VIOLET), {
        "en": ("Fly to new worlds", "Your focus fuels the ship. Every world waits to be discovered."),
        "tr": ("Yeni dünyalara uç", "Gemini odağın uçurur. Her dünya keşfedilmeyi bekliyor."),
    }),
    ("06-arrival.png", CYAN, (CYAN, PINK), {
        "en": ("Every world has a story", "Land, meet strange lifeforms and terraform as you focus."),
        "tr": ("Her dünyanın bir hikâyesi var", "Odaklandıkça in, yaşam formlarını keşfet, dünyanı dönüştür."),
    }),
    ("10-insights.png", VIOLET, (VIOLET, CYAN), {
        "en": ("See your rhythm grow", "Gentle insights that celebrate steady focus, rest days included."),
        "tr": ("Ritminin büyüdüğünü gör", "Dinlenme günlerini de sayan, istikrarı kutlayan içgörüler."),
    }),
]


for _raw, *_rest in SLIDES:
    _rest[-1].update(COPY.get(_raw, {}))

LANGS = ["en", "tr", "ar", "de", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "th", "zh-Hans"]

# iPad and Duo raw names, by the iPhone raw name of the same slide.
OTHER_RAWS = {"01-home.png": "01-home.png", "02-focus.png": "02-focus.png", "03-completion.png": "03-completion.png",
              "08-universe.png": "04-universe.png", "04-odyssey.png": "05-odyssey.png", "10-insights.png": "06-insights.png"}

# Canvas size, device frame width and corner radius (as a share of that width), Dynamic Island.
DEVICES = {
    "iphone": dict(size=(W, H), frame=1000, radius=0.135, island=True),
    "ipad-13": dict(size=(2064, 2752), frame=1440, radius=0.045, island=False, text=1.45),
    "iphone-duo": dict(size=(1398, 2034), frame=1000, radius=0.11, island=False, text=0.95),
}


def font(path, size, variation):
    f = ImageFont.truetype(path, size)
    f.set_variation_by_name(variation)
    return f


def blob(color, center, radius, alpha, blur, size=(W, H)):
    layer = Image.new("RGB", size, (0, 0, 0))
    x, y = center
    ImageDraw.Draw(layer).ellipse([x - radius, y - radius, x + radius, y + radius],
                                  fill=tuple(int(c * alpha) for c in color))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def background(nebulae, seed, W=W, H=H):
    rng = random.Random(seed)
    # Vertical deep-space gradient, lighter where the text sits.
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        top, mid, bot = (26, 24, 62), INDIGO, DEEP
        a, b, u = (top, mid, t / 0.45) if t < 0.45 else (mid, bot, (t - 0.45) / 0.55)
        grad.putpixel((0, y), tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)))
    img = grad.resize((W, H), Image.BICUBIC)
    # Two nebula washes, placed differently on every slide.
    small = Image.new("RGB", (W // 4, H // 4), (0, 0, 0))
    for color, (cx, cy), r, a in [
        (nebulae[0], (rng.uniform(0.0, 0.3), rng.uniform(0.12, 0.32)), 240, 0.30),
        (nebulae[1], (rng.uniform(0.7, 1.0), rng.uniform(0.4, 0.7)), 220, 0.26),
    ]:
        small = ImageChops.add(small, blob(color, (cx * W / 4, cy * H / 4), r, a, 90, small.size))
    img = ImageChops.add(img, small.resize((W, H), Image.BICUBIC))
    # Stars: many faint, a few bright with a soft halo.
    stars = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(stars)
    for _ in range(int(260 * W * H / (1320 * 2868))):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.choice([1.4, 1.8, 2.2, 2.6, 3.4])
        col = rng.choice([WHITE, WHITE, WHITE, LAVENDER, GOLD, CYAN])
        k = rng.uniform(0.35, 0.95)
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * k) for c in col))
    img = ImageChops.add(img, stars.filter(ImageFilter.GaussianBlur(0.6)))
    img = ImageChops.add(img, stars.filter(ImageFilter.GaussianBlur(6)))
    return img


def wrap(draw, text, fnt, width):
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = f"{line} {w}".strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def balanced(draw, text, fnt, width):
    """Wrap, then even out the lines so no line is a lonely word."""
    lines = wrap(draw, text, fnt, width)
    if len(lines) < 2:
        return lines
    target = draw.textlength(text, font=fnt) / len(lines) * 1.08
    even = wrap(draw, text, fnt, min(width, target))
    return even if len(even) == len(lines) else lines


def phone(shot, width, corner=0.135, island=True):
    """The screen with rounded corners inside a thin dark bezel and a hairline rim."""
    scale = width / shot.width
    screen = shot.convert("RGB").resize((width, round(shot.height * scale)), Image.LANCZOS)
    bezel = round(width * (0.028 if island else 0.022))
    radius = round(width * corner)
    fw, fh = screen.width + 2 * bezel, screen.height + 2 * bezel
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([0, 0, fw - 1, fh - 1], radius=radius + bezel, fill=(14, 15, 26, 255))
    d.rounded_rectangle([1, 1, fw - 2, fh - 2], radius=radius + bezel, outline=(96, 96, 128, 255), width=3)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen.width - 1, screen.height - 1], radius=radius, fill=255)
    frame.paste(screen, (bezel, bezel), mask)
    if not island:
        return frame
    # The Dynamic Island: simulator captures leave it out, so every screen gets one.
    iw, ih = round(screen.width * 0.285), round(screen.width * 0.084)
    ix, iy = bezel + (screen.width - iw) // 2, bezel + round(screen.width * 0.026)
    d.rounded_rectangle([ix, iy, ix + iw, iy + ih], radius=ih // 2, fill=(0, 0, 0, 255))
    return frame


_renderer = None


def core_text(kind, size, color, width, text):
    """Renders copy with Core Text (text.swift); returns (RGBA image, line count)."""
    global _renderer
    if _renderer is None:
        _renderer = Path(tempfile.gettempdir()) / "lumora-compose-text"
        source = Path(__file__).with_name("text.swift")
        if not _renderer.exists() or _renderer.stat().st_mtime < source.stat().st_mtime:
            subprocess.run(["swiftc", "-O", str(source), "-o", str(_renderer)], check=True, capture_output=True)
    with tempfile.NamedTemporaryFile(suffix=".png") as out:
        lines = subprocess.run([str(_renderer), kind, str(size), "%02X%02X%02X" % color, str(width), out.name, text],
                               check=True, capture_output=True, text=True).stdout
        return Image.open(out.name).convert("RGBA"), int(lines)


def compose(raw, glow, nebulae, headline, sub, seed, device="iphone", lang="en"):
    spec = DEVICES[device]
    W, H = spec["size"]
    k = spec.get("text", W / 1320)
    img = background(nebulae, seed, W, H).convert("RGBA")
    draw = ImageDraw.Draw(img)

    y = round(250 * k) if device == "iphone" else round(H * 0.07)
    if lang not in ("en", "tr"):
        size = round(132 * k)
        while True:
            head, count = core_text("serif", size, WHITE, W - round(160 * k), headline)
            if count <= 2 or size <= round(84 * k):
                break
            size -= 6
        pad = round(size * 0.35)
        img.alpha_composite(head, ((W - head.width) // 2, y - pad))
        y += head.height - 2 * pad + round(size * 0.12)
        line, _ = core_text("sans", round(56 * k), (214, 216, 245), W - round(220 * k), sub)
        y += round(34 * k)
        img.alpha_composite(line, ((W - line.width) // 2, y - round(56 * k * 0.35)))
        y += line.height - 2 * round(56 * k * 0.35)
        return place(img, raw, glow, spec, y, k, device)

    # Headline: up to two lines, shrinking until it fits.
    size = round(132 * k)
    while True:
        hf = font(SERIF, size, b"Medium Italic")
        lines = balanced(draw, headline, hf, W - round(160 * k))
        if len(lines) <= 2 or size <= round(96 * k):
            break
        size -= 6
    sf = font(SANS, round(56 * k), b"Medium")
    sub_lines = balanced(draw, sub, sf, W - round(220 * k))

    for line in lines:
        tw = draw.textlength(line, font=hf)
        draw.text(((W - tw) / 2, y), line, font=hf, fill=WHITE)
        y += round(size * 1.12)
    y += round(34 * k)
    for line in sub_lines:
        tw = draw.textlength(line, font=sf)
        draw.text(((W - tw) / 2, y), line, font=sf, fill=(214, 216, 245))
        y += round(74 * k)

    return place(img, raw, glow, spec, y, k, device)


def place(img, raw, glow, spec, y, k, device):
    """The device, running off the bottom edge, on a soft glow and shadow."""
    W, H = spec["size"]
    frame = phone(Image.open(raw), spec["frame"], spec["radius"], spec["island"])
    top = y + round(90 * k) if device != "iphone" else max(y + 90, 860)
    left = (W - frame.width) // 2
    img = ImageChops.add(img.convert("RGB"), blob(glow, (W / 2, top + 650 * k), 560 * k, 0.40, 170 * k, (W, H))).convert("RGBA")
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([left + 20, top + 50, left + frame.width - 20, top + frame.height],
                                             radius=round(160 * k), fill=(0, 0, 0, 170))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(50 * k)))
    img.alpha_composite(frame, (left, top))
    return img.convert("RGB")


def watch(raw, out):
    """A plain Watch screen with the clock set to 9:41, like the iPhone status bar."""
    img = Image.open(raw).convert("RGB")
    d = ImageDraw.Draw(img)
    d.rectangle([250, 28, 404, 80], fill=img.getpixel((240, 54)))
    f = font(SANS, 34, b"Semibold")
    d.text((385 - d.textlength("9:41", font=f), 30), "9:41", font=f, fill=(255, 255, 255))
    img.save(out, optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", choices=LANGS, action="append")
    parser.add_argument("--device", choices=["iphone", "ipad-13", "iphone-duo", "watch"], action="append")
    args = parser.parse_args()
    for lang in args.lang or LANGS:
        for device in args.device or ["iphone", "ipad-13", "iphone-duo", "watch"]:
            if device == "watch":
                raws = sorted((RAW / lang / "watch").glob("*.png"))
                if raws:
                    (OUT / lang / "watch").mkdir(parents=True, exist_ok=True)
                for path in raws:
                    watch(path, OUT / lang / "watch" / path.name)
                print(lang, device, len(raws))
                continue
            # Start clean, so a slide that moved leaves no file behind under its old number.
            for folder in (("6.9", "6.3") if device == "iphone" else (device,)):
                for stale in (OUT / lang / folder).glob("*.png"):
                    stale.unlink()
            if device == "iphone":
                slides = [s for s in SLIDES if lang in s[3] and (RAW / lang / s[0]).exists()]
                for folder in ("6.9", "6.3"):
                    (OUT / lang / folder).mkdir(parents=True, exist_ok=True)
            else:
                slides = [s for s in SLIDES if s[0] in OTHER_RAWS and (RAW / lang / device / OTHER_RAWS[s[0]]).exists()]
                if slides:
                    (OUT / lang / device).mkdir(parents=True, exist_ok=True)
            for i, (raw, glow, nebulae, copy) in enumerate(slides, start=1):
                headline, sub = copy[lang]
                if device == "iphone":
                    img = compose(RAW / lang / raw, glow, nebulae, headline, sub, seed=i * 7, lang=lang)
                    name = f"{i:02d}-{Path(raw).stem.split('-', 1)[1]}.png"
                    img.save(OUT / lang / "6.9" / name, optimize=True)
                    img.resize((1206, 2622), Image.LANCZOS).save(OUT / lang / "6.3" / name, optimize=True)
                else:
                    other = OTHER_RAWS[raw]
                    img = compose(RAW / lang / device / other, glow, nebulae, headline, sub, seed=i * 7,
                                  device=device, lang=lang)
                    img.save(OUT / lang / device / other, optimize=True)
            print(lang, device, len(slides))


if __name__ == "__main__":
    main()
