#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pillow==11.3.0",
# ]
# ///
"""Create App Store marketing screenshots and creative artwork from raw sleepypod captures.

A manifest with `screenshots` renders the portrait store sets; one with `artwork`
renders the landscape product-page header, search-results and universal images
that App Store Connect calls creative assets.
All paths in the manifest are resolved relative to the manifest itself.
`{appearance}` in an input or output path expands to the selected appearance
(dark or light), so one manifest renders both sets with matching captions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import tempfile
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from PIL import Image, ImageColor, ImageDraw, ImageFilter, ImageFont, ImageOps

DEFAULT_SIZE = (1320, 2868)  # Apple's 6.9-inch portrait screenshot size.
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_MANIFEST = SCRIPT_DIR / "manifest.example.json"
APPEARANCE_KEYS = ("accent", "text", "muted", "background", "glow", "bezel")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compose App Store screenshots: caption, app icon and framed capture on a night-sky gradient."
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="JSON manifest (default: manifest.example.json beside this script)",
    )
    parser.add_argument(
        "--appearance",
        action="append",
        help="Render only this appearance (repeatable; default: every appearance in the manifest)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Override the manifest output directory ({appearance} expands)",
    )
    parser.add_argument(
        "--size",
        default=f"{DEFAULT_SIZE[0]}x{DEFAULT_SIZE[1]}",
        help="Output size as WIDTHxHEIGHT (default: 1320x2868)",
    )
    parser.add_argument('--only', action='append', help='Render only this output stem (repeatable)')
    parser.add_argument(
        "--guides",
        action="store_true",
        help="Artwork manifests only: outline the safe area in red for proofing (never upload these)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check-config",
        action="store_true",
        help="Validate the manifest, app icon and caption fit without reading raw screenshots",
    )
    mode.add_argument(
        "--self-test",
        action="store_true",
        help="Render a temporary sample per appearance and verify dimensions and RGB mode",
    )
    return parser.parse_args()


def parse_size(value: str) -> tuple[int, int]:
    try:
        width_text, height_text = value.lower().split("x", maxsplit=1)
        width, height = int(width_text), int(height_text)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"Invalid size {value!r}; expected WIDTHxHEIGHT") from exc
    if width <= 0 or height <= 0 or width >= height:
        raise ValueError("Screenshot size must be positive and portrait-oriented")
    return width, height


def load_manifest(path: Path) -> tuple[dict[str, Any], Path]:
    path = path.expanduser().resolve()
    with path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("format") != 1:
        raise ValueError("Manifest must declare format: 1")
    for key in ("app_name", "icon", "appearances"):
        if key not in manifest:
            raise ValueError(f"Manifest is missing {key!r}")
    if manifest["app_name"] != manifest["app_name"].lower():
        raise ValueError("The brand is always lowercase: app_name must be 'sleepypod'")
    for name, palette in manifest["appearances"].items():
        for key in APPEARANCE_KEYS:
            if key not in palette:
                raise ValueError(f"appearances.{name} is missing {key!r}")
        if len(palette["background"]) < 2:
            raise ValueError(f"appearances.{name}.background must contain at least two colors")
        for value in [palette[key] for key in APPEARANCE_KEYS if key != "background"] + palette["background"]:
            ImageColor.getrgb(value)
    if ("screenshots" in manifest) == ("artwork" in manifest):
        raise ValueError("Manifest must contain exactly one of 'screenshots' or 'artwork'")
    kind = manifest_kind(manifest)
    if not manifest[kind]:
        raise ValueError(f"Manifest has no {kind}")
    for index, item in enumerate(manifest[kind]):
        for key in ("input", "output", "caption"):
            if key not in item:
                raise ValueError(f"{kind}[{index}] is missing {key!r}")
        if kind == "artwork":
            validate_artwork_item(index, item)
    return manifest, path.parent


def manifest_kind(manifest: dict[str, Any]) -> str:
    """'screenshots' for the portrait store sets, 'artwork' for header/search creative."""
    return "artwork" if "artwork" in manifest else "screenshots"


# Apple's creative asset specifications (reviewed October 21, 2026):
# https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
# header: 21:9, exactly 3840x1646, JPEG or PNG. search: 3:2, 1920x1280 to 3840x2560, JPEG or PNG.
# universal: 16:9, exactly 5244x2950, PNG only, accepted in both placements. No alpha anywhere.
ARTWORK_PLACEMENTS: dict[str, dict[str, Any]] = {
    "header": {"ratio": (21, 9), "min": (3840, 1646), "max": (3840, 1646)},
    "search": {"ratio": (3, 2), "min": (1920, 1280), "max": (3840, 2560)},
    "universal": {"ratio": (16, 9), "min": (5244, 2950), "max": (5244, 2950)},
}
# Apple's asset guidance forbids pricing, URLs, copyright marks and unverified claims;
# App Store Review Guideline 2.3 covers the rest. Keep the brand plain and the copy descriptive.
ARTWORK_PHONE_WIDTH = 800  # Phone screen width in layout units; widest the text column must allow for.
ARTWORK_FORBIDDEN_WORDS = ("free", "discount", "sale", "award", "best", "editor", "apple", "http", "www", "©", "™", "®")


def validate_artwork_item(index: int, item: dict[str, Any]) -> None:
    placement = item.get("placement")
    if placement not in ARTWORK_PLACEMENTS:
        raise ValueError(f"artwork[{index}].placement must be one of {sorted(ARTWORK_PLACEMENTS)}")
    spec = ARTWORK_PLACEMENTS[placement]
    width, height = parse_artwork_size(str(item.get("size", "")))
    ratio_w, ratio_h = spec["ratio"]
    if abs(width / height - ratio_w / ratio_h) > 0.005:
        raise ValueError(f"artwork[{index}] {placement} must be {ratio_w}:{ratio_h}; got {width}x{height}")
    if not (spec["min"][0] <= width <= spec["max"][0] and spec["min"][1] <= height <= spec["max"][1]):
        raise ValueError(
            f"artwork[{index}] {placement} must be between {spec['min'][0]}x{spec['min'][1]} and "
            f"{spec['max'][0]}x{spec['max'][1]}; got {width}x{height}"
        )
    safe = item.get("safe_area", [0.08, 0.08])
    if len(safe) != 2 or not all(0 <= float(value) < 0.45 for value in safe):
        raise ValueError(f"artwork[{index}].safe_area must be two fractions below 0.45, e.g. [0.09, 0.08]")
    if not str(item["output"]).lower().endswith(".png"):
        raise ValueError(f"artwork[{index}].output must be a .png (the universal asset is PNG-only)")


def parse_artwork_size(value: str) -> tuple[int, int]:
    try:
        width_text, height_text = value.lower().split("x", maxsplit=1)
        width, height = int(width_text), int(height_text)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"Invalid artwork size {value!r}; expected WIDTHxHEIGHT") from exc
    if width <= height:
        raise ValueError("Artwork must be landscape-oriented")
    return width, height


def appearances(manifest: dict[str, Any], requested: list[str] | None) -> list[str]:
    names = requested or list(manifest["appearances"])
    for name in names:
        if name not in manifest["appearances"]:
            raise ValueError(f"Appearance {name!r} is not in the manifest")
    return names


def resolve_path(base: Path, value: str | Path, appearance: str = "dark") -> Path:
    path = Path(str(value).replace("{appearance}", appearance)).expanduser()
    return path.resolve() if path.is_absolute() else (base / path).resolve()


def pixel_sha256(image: Image.Image) -> str:
    rgb = image.convert("RGB")
    digest = hashlib.sha256()
    digest.update(f"{rgb.width}x{rgb.height}:RGB\n".encode())
    digest.update(rgb.tobytes())
    return digest.hexdigest()


def validate_icon(manifest: dict[str, Any], base: Path) -> tuple[Path, Image.Image]:
    icon = manifest["icon"]
    path = resolve_path(base, icon["path"])
    if not path.is_file():
        raise FileNotFoundError(f"App icon not found: {path}")
    with Image.open(path) as source:
        source.load()
        image = source.convert("RGB")
    if image.width != image.height:
        raise ValueError(f"App icon must be square; got {image.size}")
    expected = icon.get("pixel_sha256")
    actual = pixel_sha256(image)
    if expected and actual != expected:
        raise ValueError(
            f"App icon pixels changed ({actual} != {expected}); review the icon, then update pixel_sha256"
        )
    return path, image


def color(value: str) -> tuple[int, int, int]:
    return ImageColor.getrgb(value)[:3]  # type: ignore[return-value]


def blend(first: tuple[int, int, int], second: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a + (b - a) * t) for a, b in zip(first, second))  # type: ignore[return-value]


def gradient(size: tuple[int, int], stops: Iterable[str]) -> Image.Image:
    width, height = size
    colors = [color(item) for item in stops]
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    segment_count = len(colors) - 1
    for y in range(height):
        position = y / max(height - 1, 1) * segment_count
        segment = min(int(position), segment_count - 1)
        draw.line(
            (0, y, width, y),
            fill=blend(colors[segment], colors[segment + 1], position - segment),
        )
    return image


def find_font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    names = (
        [
            "/System/Library/Fonts/SFNSRounded.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ]
        if bold
        else [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    )
    for name in names:
        if Path(name).is_file():
            try:
                font = ImageFont.truetype(name, size=size)
                if bold and hasattr(font, "set_variation_by_name"):
                    try:
                        font.set_variation_by_name("Bold")
                    except (OSError, ValueError):
                        pass
                return font
            except OSError:
                pass
    return ImageFont.load_default(size=size)


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_width: int) -> str:
    """Greedy word wrap; a literal newline in the text forces a break (used to avoid orphans)."""
    lines: list[str] = []
    for paragraph in text.split("\n"):
        current = ""
        for word in paragraph.split():
            candidate = word if not current else f"{current} {word}"
            if draw.textbbox((0, 0), candidate, font=font)[2] <= max_width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
    return "\n".join(lines)


def fit_caption(
    draw: ImageDraw.ImageDraw, text: str, max_width: int, max_height: int, scale: float
) -> tuple[str, ImageFont.ImageFont, int]:
    for raw_size in range(104, 55, -2):
        font = find_font(max(24, round(raw_size * scale)), bold=True)
        spacing = max(8, round(18 * scale))
        wrapped = wrap_text(draw, text, font, max_width)
        if wrapped.count("\n") > 2:
            continue
        box = draw.multiline_textbbox((0, 0), wrapped, font=font, spacing=spacing)
        if box[2] - box[0] <= max_width and box[3] - box[1] <= max_height:
            return wrapped, font, spacing
    raise ValueError(f"Caption is too long for the template: {text!r}")


def rounded_paste(canvas: Image.Image, source: Image.Image, box: tuple[int, int, int, int], radius: int) -> None:
    width, height = box[2] - box[0], box[3] - box[1]
    fitted = ImageOps.fit(source.convert("RGB"), (width, height), method=Image.Resampling.LANCZOS)
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width, height), radius=radius, fill=255)
    canvas.paste(fitted, box[:2], mask)


def add_sky(canvas: Image.Image, palette: dict[str, Any], seed_text: str, scale: float) -> Image.Image:
    """Soft moon glow plus a scatter of stars, seeded so every render matches."""
    width, height = canvas.size
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_rgb = color(palette["glow"])
    cx, cy, r = round(width * 0.82), round(250 * scale), round(430 * scale)
    glow_draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*glow_rgb, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(round(190 * scale)))
    result = Image.alpha_composite(canvas.convert("RGBA"), glow)

    stars = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(stars)
    rng = random.Random(int.from_bytes(hashlib.sha256(seed_text.encode()).digest()[:8], "big"))
    star_rgb = color(palette["text"])
    for _ in range(70):
        radius = max(1, round(rng.choice((1.5, 2, 2.5, 3, 4)) * scale))
        x = rng.randrange(0, width)
        y = rng.randrange(0, max(1, round(height * 0.32)))
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*star_rgb, rng.randrange(25, 95)))
    return Image.alpha_composite(result, stars)


def render_one(
    manifest: dict[str, Any],
    palette: dict[str, Any],
    base: Path,
    item: dict[str, Any],
    input_path: Path,
    output_path: Path,
    size: tuple[int, int],
    icon_image: Image.Image,
) -> None:
    width, height = size
    scale = width / DEFAULT_SIZE[0]
    canvas = add_sky(gradient(size, palette["background"]), palette, manifest["app_name"] + item["output"], scale)
    draw = ImageDraw.Draw(canvas)
    accent, text_rgb, muted = color(palette["accent"]), color(palette["text"]), color(palette["muted"])

    margin = round(96 * scale)
    icon_size = round(104 * scale)
    icon_top = round(92 * scale)
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (margin, icon_top + round(10 * scale), margin + icon_size, icon_top + icon_size + round(10 * scale)),
        radius=round(icon_size * 0.225), fill=(0, 0, 0, 90),
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(round(12 * scale))))
    rgb = canvas.convert("RGB")
    rounded_paste(rgb, icon_image, (margin, icon_top, margin + icon_size, icon_top + icon_size), round(icon_size * 0.225))
    canvas = rgb.convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    name_font = find_font(round(52 * scale), bold=True)
    name_x = margin + icon_size + round(30 * scale)
    name_box = draw.textbbox((0, 0), manifest["app_name"], font=name_font)
    draw.text(
        (name_x, icon_top + (icon_size - (name_box[3] - name_box[1])) / 2 - name_box[1]),
        manifest["app_name"], font=name_font, fill=text_rgb,
    )

    eyebrow = str(item.get("eyebrow", "")).upper()
    eyebrow_top = round(262 * scale)
    if eyebrow:
        eyebrow_font = find_font(round(34 * scale), bold=True)
        x = margin
        for character in eyebrow:  # Letter-spaced, like the app's Eyebrow style.
            draw.text((x, eyebrow_top), character, font=eyebrow_font, fill=accent)
            x += draw.textlength(character, font=eyebrow_font) + round(5 * scale)

    caption, caption_font, spacing = fit_caption(
        draw, str(item["caption"]), width - 2 * margin, round(330 * scale), scale
    )
    draw.multiline_text((margin, round(330 * scale)), caption, font=caption_font, spacing=spacing, fill=text_rgb)
    subtitle = item.get("subtitle")
    if subtitle:
        caption_box = draw.multiline_textbbox(
            (margin, round(330 * scale)), caption, font=caption_font, spacing=spacing
        )
        draw.text(
            (margin, caption_box[3] + round(26 * scale)), subtitle,
            font=find_font(round(38 * scale)), fill=muted,
        )

    if not input_path.is_file():
        raise FileNotFoundError(f"Raw screenshot not found: {input_path}")
    with Image.open(input_path) as raw:
        raw.load()
        if raw.width >= raw.height:
            raise ValueError(f"Raw screenshot must be portrait-oriented: {input_path}")
        screenshot = raw.convert("RGB")

    # Phone: the full capture inside a dark bezel, centred under the caption.
    bezel = round(24 * scale)
    phone_top = round(760 * scale)
    available = height - phone_top - round(70 * scale) - 2 * bezel
    screen_height = available
    screen_width = round(screen_height * screenshot.width / screenshot.height)
    screen_left = (width - screen_width) // 2
    screen_top = phone_top + bezel
    corner = round(screen_width * 0.135)
    outer = (screen_left - bezel, phone_top, screen_left + screen_width + bezel, screen_top + screen_height + bezel)

    phone_shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(phone_shadow).rounded_rectangle(
        (outer[0] + round(10 * scale), outer[1] + round(34 * scale), outer[2] + round(10 * scale), outer[3] + round(34 * scale)),
        radius=corner + bezel, fill=(0, 0, 0, 150),
    )
    canvas = Image.alpha_composite(canvas, phone_shadow.filter(ImageFilter.GaussianBlur(round(36 * scale))))
    draw = ImageDraw.Draw(canvas)
    bezel_rgb = color(palette["bezel"])
    draw.rounded_rectangle(outer, radius=corner + bezel, fill=bezel_rgb)
    draw.rounded_rectangle(
        outer, radius=corner + bezel,
        outline=blend(bezel_rgb, (255, 255, 255), 0.28), width=max(2, round(4 * scale)),
    )
    rgb = canvas.convert("RGB")
    rounded_paste(
        rgb,
        screenshot.resize((screen_width, screen_height), Image.Resampling.LANCZOS),
        (screen_left, screen_top, screen_left + screen_width, screen_top + screen_height),
        radius=corner,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    rgb.save(output_path, format="PNG", optimize=True)
    with Image.open(output_path) as result:
        if result.size != size or result.mode != "RGB":
            raise RuntimeError(f"Output verification failed for {output_path}: {result.size}, {result.mode}")


def draw_phone(
    canvas: Image.Image,
    palette: dict[str, Any],
    screenshot: Image.Image,
    screen_box: tuple[int, int, int, int],
    scale: float,
) -> Image.Image:
    """The full capture inside a dark bezel with a soft drop shadow; shared by both layouts."""
    screen_left, screen_top, screen_right, screen_bottom = screen_box
    screen_width, screen_height = screen_right - screen_left, screen_bottom - screen_top
    bezel = round(24 * scale)
    corner = round(screen_width * 0.135)
    outer = (screen_left - bezel, screen_top - bezel, screen_right + bezel, screen_bottom + bezel)

    phone_shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(phone_shadow).rounded_rectangle(
        (outer[0] + round(10 * scale), outer[1] + round(34 * scale), outer[2] + round(10 * scale), outer[3] + round(34 * scale)),
        radius=corner + bezel, fill=(0, 0, 0, 150),
    )
    canvas = Image.alpha_composite(canvas.convert("RGBA"), phone_shadow.filter(ImageFilter.GaussianBlur(round(36 * scale))))
    draw = ImageDraw.Draw(canvas)
    bezel_rgb = color(palette["bezel"])
    draw.rounded_rectangle(outer, radius=corner + bezel, fill=bezel_rgb)
    draw.rounded_rectangle(
        outer, radius=corner + bezel,
        outline=blend(bezel_rgb, (255, 255, 255), 0.28), width=max(2, round(4 * scale)),
    )
    rgb = canvas.convert("RGB")
    rounded_paste(rgb, screenshot.resize((screen_width, screen_height), Image.Resampling.LANCZOS), screen_box, radius=corner)
    return rgb


def artwork_layout(item: dict[str, Any]) -> tuple[tuple[int, int], tuple[int, int, int, int], float]:
    """Canvas size, safe-area box and layout scale for one artwork placement.

    Everything that must survive Apple's device crops (icon, wordmark, caption, the
    phone's screen) is laid out inside the safe area; only the phone's lower body may
    bleed past it. The scale is pinned so the header and search images share one type size.
    """
    width, height = parse_artwork_size(str(item["size"]))
    inset_x, inset_y = (float(value) for value in item.get("safe_area", [0.08, 0.08]))
    safe = (round(width * inset_x), round(height * inset_y), round(width * (1 - inset_x)), round(height * (1 - inset_y)))
    safe_width, safe_height = safe[2] - safe[0], safe[3] - safe[1]
    scale = min(safe_width / 3150, safe_height / 1400)
    return (width, height), safe, scale


def artwork_column_width(safe: tuple[int, int, int, int], scale: float) -> int:
    """Width the caption may use: the safe area minus the widest phone and the gap, capped for measure."""
    phone = round(ARTWORK_PHONE_WIDTH * scale * 1.25) + 2 * round(24 * scale)
    return min(safe[2] - safe[0] - phone - round(140 * scale), round(2100 * scale))


def render_artwork(
    manifest: dict[str, Any],
    palette: dict[str, Any],
    item: dict[str, Any],
    input_path: Path,
    output_path: Path,
    icon_image: Image.Image,
    *,
    guides: bool = False,
) -> None:
    size, safe, scale = artwork_layout(item)
    width, height = size
    sky_scale = height / 1646  # Glow and stars track the canvas, not the type.
    canvas = add_sky(gradient(size, palette["background"]), palette, manifest["app_name"] + item["output"], sky_scale)
    accent, text_rgb, muted = color(palette["accent"]), color(palette["text"]), color(palette["muted"])

    if not input_path.is_file():
        raise FileNotFoundError(f"Raw screenshot not found: {input_path}")
    with Image.open(input_path) as raw:
        raw.load()
        if raw.width >= raw.height:
            raise ValueError(f"Raw screenshot must be portrait-oriented: {input_path}")
        screenshot = raw.convert("RGB")

    # Phone on the right: its screen's top two thirds (the part with the control) stay in the
    # safe area; a taller canvas shows the whole phone, a header lets the body run off the bottom.
    gap = round(140 * scale)
    bezel = round(24 * scale)
    safe_height = safe[3] - safe[1]
    screen_width = round(ARTWORK_PHONE_WIDTH * scale)
    screen_height = round(screen_width * screenshot.height / screenshot.width)
    if screen_height + 2 * bezel <= safe_height:
        # Whole phone fits (3:2 search): let it grow a little to fill the safe height.
        screen_height = min(safe_height - 2 * bezel - round(80 * scale), round(screen_height * 1.25))
        screen_width = round(screen_height * screenshot.width / screenshot.height)
        screen_top = safe[1] + (safe_height - screen_height) // 2
    else:
        # Header: the body runs off the bottom edge, never stopping just short of it.
        screen_top = safe[1] + bezel + round(40 * scale)
        screen_height = max(screen_height, height - screen_top + round(120 * scale))
        screen_width = round(screen_height * screenshot.width / screenshot.height)
    screen_left = safe[2] - bezel - screen_width
    screen_box = (screen_left, screen_top, screen_left + screen_width, screen_top + screen_height)

    # Text column on the left, vertically centred in the safe area.
    column_left = safe[0]
    column_width = min(screen_left - bezel - gap - column_left, artwork_column_width(safe, scale))
    icon_size = round(150 * scale)
    name_font = find_font(round(78 * scale), bold=True)
    eyebrow_font = find_font(round(40 * scale), bold=True)
    subtitle_font = find_font(round(54 * scale))
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    caption, caption_font, spacing = fit_artwork_caption(probe, str(item["caption"]), column_width, scale)
    caption_box = probe.multiline_textbbox((0, 0), caption, font=caption_font, spacing=spacing)
    caption_height = caption_box[3] - caption_box[1]
    eyebrow = str(item.get("eyebrow", "")).upper()
    subtitle = str(item.get("subtitle", ""))
    block_height = icon_size + round(90 * scale)
    if eyebrow:
        block_height += round(40 * scale) + round(34 * scale)
    block_height += caption_height
    if subtitle:
        block_height += round(44 * scale) + round(54 * scale)
    y = safe[1] + (safe_height - block_height) // 2

    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (column_left, y + round(10 * scale), column_left + icon_size, y + icon_size + round(10 * scale)),
        radius=round(icon_size * 0.225), fill=(0, 0, 0, 90),
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(round(12 * scale))))
    rgb = canvas.convert("RGB")
    rounded_paste(rgb, icon_image, (column_left, y, column_left + icon_size, y + icon_size), round(icon_size * 0.225))
    canvas = rgb.convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    name_x = column_left + icon_size + round(40 * scale)
    name_box = draw.textbbox((0, 0), manifest["app_name"], font=name_font)
    draw.text(
        (name_x, y + (icon_size - (name_box[3] - name_box[1])) / 2 - name_box[1]),
        manifest["app_name"], font=name_font, fill=text_rgb,
    )
    y += icon_size + round(90 * scale)

    if eyebrow:
        x = column_left
        for character in eyebrow:  # Letter-spaced, like the app's Eyebrow style.
            draw.text((x, y), character, font=eyebrow_font, fill=accent)
            x += draw.textlength(character, font=eyebrow_font) + round(6 * scale)
        y += round(40 * scale) + round(34 * scale)

    draw.multiline_text((column_left, y - caption_box[1]), caption, font=caption_font, spacing=spacing, fill=text_rgb)
    y += caption_height
    if subtitle:
        y += round(44 * scale)
        subtitle_text = wrap_text(draw, subtitle, subtitle_font, column_width)
        draw.multiline_text((column_left, y), subtitle_text, font=subtitle_font, spacing=round(12 * scale), fill=muted)

    rgb = draw_phone(canvas, palette, screenshot, screen_box, scale)
    if guides:
        ImageDraw.Draw(rgb).rectangle(safe, outline=(255, 64, 64), width=max(3, round(6 * scale)))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    rgb.save(output_path, format="PNG", optimize=True)
    with Image.open(output_path) as result:
        if result.size != size or result.mode != "RGB":
            raise RuntimeError(f"Output verification failed for {output_path}: {result.size}, {result.mode}")


def fit_artwork_caption(
    draw: ImageDraw.ImageDraw, text: str, max_width: int, scale: float
) -> tuple[str, ImageFont.ImageFont, int]:
    for raw_size in range(150, 89, -4):
        font = find_font(max(24, round(raw_size * scale)), bold=True)
        spacing = max(8, round(20 * scale))
        wrapped = wrap_text(draw, text, font, max_width)
        if wrapped.count("\n") > 2:
            continue
        box = draw.multiline_textbbox((0, 0), wrapped, font=font, spacing=spacing)
        if box[2] - box[0] <= max_width and box[3] - box[1] <= round(560 * scale):
            return wrapped, font, spacing
    raise ValueError(f"Caption is too long for the artwork template: {text!r}")


def output_dir_for(manifest: dict[str, Any], base: Path, override: Path | None, appearance: str) -> Path:
    if override:
        return resolve_path(Path.cwd(), override, appearance)
    return resolve_path(base, manifest.get("output_dir", "output/{appearance}"), appearance)


def render_manifest(
    manifest: dict[str, Any], base: Path, names: list[str], override: Path | None, size: tuple[int, int],
    *, guides: bool = False,
) -> list[Path]:
    _, icon = validate_icon(manifest, base)
    outputs: list[Path] = []
    kind = manifest_kind(manifest)
    for appearance in names:
        palette = manifest["appearances"][appearance]
        output_dir = output_dir_for(manifest, base, override, appearance)
        for item in manifest[kind]:
            destination = output_dir / item["output"]
            input_path = resolve_path(base, item["input"], appearance)
            if kind == "artwork":
                render_artwork(manifest, palette, item, input_path, destination, icon, guides=guides)
            else:
                render_one(manifest, palette, base, item, input_path, destination, size, icon)
            outputs.append(destination)
    return outputs


def check_caption_copy(item: dict[str, Any], *, artwork: bool = False) -> None:
    for key in ("eyebrow", "caption", "subtitle"):
        text = str(item.get(key, ""))
        if "sleepypod" in text.lower() and "sleepypod" not in text:
            raise ValueError(f"The brand is lowercase: {text!r}")
        if not artwork:
            continue
        lowered = text.lower()
        if any(symbol in text for symbol in "$€£%"):
            raise ValueError(f"Artwork copy must not mention pricing: {text!r}")
        words = {word.strip(".,!?'\"") for word in lowered.split()}
        hit = sorted(word for word in ARTWORK_FORBIDDEN_WORDS if word in words or (len(word) == 1 and word in text))
        if hit:
            raise ValueError(f"Artwork copy must not contain {hit} (Apple asset guidance): {text!r}")


def check_config(manifest: dict[str, Any], base: Path, size: tuple[int, int]) -> str:
    path, icon = validate_icon(manifest, base)
    kind = manifest_kind(manifest)
    outputs = [item["output"] for item in manifest[kind]]
    if len(set(outputs)) != len(outputs):
        raise ValueError(f"Two {kind} entries share an output filename")
    if kind == "artwork":
        probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
        placements = []
        for item in manifest["artwork"]:
            check_caption_copy(item, artwork=True)
            item_size, safe, scale = artwork_layout(item)
            column_width = artwork_column_width(safe, scale)
            fit_artwork_caption(probe, str(item["caption"]), column_width, scale)
            placements.append(f"{item['placement']} {item_size[0]}x{item_size[1]}")
        return (
            f"PASS {manifest['app_name']}: {len(outputs)} artwork x {len(manifest['appearances'])} appearances "
            f"({', '.join(manifest['appearances'])}); icon {path.name} {icon.width}x{icon.height}; "
            f"{', '.join(placements)}"
        )
    scale = size[0] / DEFAULT_SIZE[0]
    draw = ImageDraw.Draw(Image.new("RGB", size))
    margin = round(96 * scale)
    for item in manifest["screenshots"]:
        fit_caption(draw, str(item["caption"]), size[0] - 2 * margin, round(330 * scale), scale)
        check_caption_copy(item)
    return (
        f"PASS {manifest['app_name']}: {len(outputs)} screenshots x {len(manifest['appearances'])} appearances "
        f"({', '.join(manifest['appearances'])}); icon {path.name} {icon.width}x{icon.height}; captions fit {size[0]}x{size[1]}"
    )


def run_self_test(manifest: dict[str, Any], base: Path, names: list[str], size: tuple[int, int]) -> str:
    _, icon = validate_icon(manifest, base)
    kind = manifest_kind(manifest)
    with tempfile.TemporaryDirectory(prefix="sleepypod-asc-") as temporary:
        temporary_path = Path(temporary)
        raw_path = temporary_path / "raw.png"
        mock = gradient(DEFAULT_SIZE, ["#0B0B0C", "#17171A"])
        mock_draw = ImageDraw.Draw(mock)
        mock_draw.rounded_rectangle((60, 300, 1260, 1300), radius=60, fill="#0F0F11", outline="#26262A", width=3)
        mock_draw.rounded_rectangle((60, 1360, 1260, 2600), radius=60, fill="#0F0F11", outline="#26262A", width=3)
        mock_draw.text((140, 380), "RAW APP SCREENSHOT", font=find_font(62, bold=True), fill="#ECECEC")
        mock.save(raw_path, format="PNG")
        if kind == "artwork":
            sizes = []
            for template in manifest["artwork"]:
                item = {**template, "input": str(raw_path), "eyebrow": "Pipeline check",
                        "caption": "Real captures, framed for the App Store."}
                expected, _, _ = artwork_layout(item)
                for appearance in names:
                    output_path = temporary_path / f"self-test-{template['placement']}-{appearance}.png"
                    render_artwork(manifest, manifest["appearances"][appearance], item, raw_path, output_path, icon)
                    with Image.open(output_path) as result:
                        assert result.size == expected
                        assert result.mode == "RGB"
                        assert "A" not in result.getbands()
                sizes.append(f"{expected[0]}x{expected[1]}")
            return f"PASS {', '.join(sizes)} RGB/no alpha for {', '.join(names)}"
        item = {"input": str(raw_path), "output": "self-test.png", "eyebrow": "Pipeline check",
                "caption": "Real captures, framed for the App Store."}
        for appearance in names:
            output_path = temporary_path / f"self-test-{appearance}.png"
            render_one(manifest, manifest["appearances"][appearance], base, item, raw_path, output_path, size, icon)
            with Image.open(output_path) as result:
                assert result.size == size
                assert result.mode == "RGB"
                assert "A" not in result.getbands()
    return f"PASS {size[0]}x{size[1]} RGB/no alpha for {', '.join(names)}"


def main() -> None:
    args = parse_args()
    size = parse_size(args.size)
    manifest, base = load_manifest(args.manifest)
    names = appearances(manifest, args.appearance)
    kind = manifest_kind(manifest)
    if args.only:
        available = {Path(item['output']).stem for item in manifest[kind]}
        unknown = set(args.only) - available
        if unknown:
            raise ValueError(f'Unknown {kind} names: {sorted(unknown)}')
        manifest[kind] = [item for item in manifest[kind] if Path(item['output']).stem in args.only]
    if args.check_config:
        print(check_config(manifest, base, size))
        return
    if args.self_test:
        print(run_self_test(manifest, base, names, size))
        return
    for path in render_manifest(manifest, base, names, args.output_dir, size, guides=args.guides):
        print(path)


if __name__ == "__main__":
    main()
