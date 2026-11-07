#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pillow==11.3.0",
# ]
# ///
"""Join the iPhone Duo's cover-display and inner-display recordings with the device opening between them.

simctl records one display at a time and the simulator draws no 3D device, so the fold is drawn here: the
cover panel swings open around the hinge like a book page, its face turning from the cover display to the
left half of the inner display, while the view pans from the folded phone to the open one. Every frame,
before, during and after the move, is drawn by the same renderer so the joins don't jump.

    unfold.py --cover cover.mp4 --inner inner.mp4 --inner-start 1.2 --size 1920x886 --output out.mp4
    unfold.py ... --framed --size 1920x1080   # device drawn on the store background (social cut)
    unfold.py ... --stills dir/               # also save frames from the move for review

Writes video only, 30 fps; capture.py adds the silent audio track and checks the result.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageColor, ImageDraw, ImageEnhance, ImageFilter

import generate

HERE = Path(__file__).resolve().parent
FPS = 30
MOVE_SECONDS = 1.3
# App background, matching capture.py's letterbox padding.
PAD = {"dark": "#0B0B0C", "light": "#F6F6F5"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cover", type=Path, required=True, help="Recording of the cover display (LCD)")
    parser.add_argument("--inner", type=Path, required=True, help="Recording of the inner display (LCD-1)")
    parser.add_argument("--cover-seconds", type=float, required=True, help="How long the cover display is shown")
    parser.add_argument("--inner-start", type=float, default=0, help="Seconds into --inner where the move lands")
    parser.add_argument("--inner-seconds", type=float, required=True, help="How much of --inner to show")
    parser.add_argument("--size", default="1920x886", help="Output WIDTHxHEIGHT (landscape)")
    parser.add_argument("--appearance", choices=PAD, default="dark")
    parser.add_argument("--framed", action="store_true", help="Draw the device on the store background")
    parser.add_argument("--stills", type=Path, help="Save PNG stills from the move into this folder")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def probe(path: Path) -> tuple[int, int]:
    """Displayed size: simctl tags the Duo's landscape inner display as a rotated portrait stream."""
    info = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height:stream_side_data=rotation", "-of", "json", str(path)],
        check=True, capture_output=True, text=True).stdout)
    stream = info["streams"][0]
    rotation = next((int(d.get("rotation", 0)) for d in stream.get("side_data_list", []) if "rotation" in d), 0)
    return (stream["height"], stream["width"]) if rotation % 180 else (stream["width"], stream["height"])


def frames(path: Path, size: tuple[int, int], start: float, seconds: float):
    """Decodes `seconds` of a recording from `start` at 30 fps, scaled and centre-cropped to `size`.

    simctl writes a frame only when the screen changes, so a still screen is held with its last frame.
    """
    width, height = size
    process = subprocess.Popen(
        ["ffmpeg", "-loglevel", "error", "-i", str(path), "-vf",
         f"tpad=stop_mode=clone:stop_duration={seconds + 5:.3f},trim=start={start:.3f}:duration={seconds:.3f},"
         f"setpts=PTS-STARTPTS,fps={FPS},scale={width}:{height}:force_original_aspect_ratio=increase:flags=lanczos,"
         f"crop={width}:{height}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE)
    frame_bytes = width * height * 3
    while True:
        data = process.stdout.read(frame_bytes)
        if len(data) < frame_bytes:
            break
        yield Image.frombytes("RGB", size, data)
    process.wait()


def ease(t: float) -> float:
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def perspective_coefficients(output_quad, input_quad) -> list[float]:
    """PIL PERSPECTIVE coefficients that map points of `output_quad` back to `input_quad`."""
    rows, values = [], []
    for (x, y), (u, v) in zip(output_quad, input_quad):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); values.append(u)
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y]); values.append(v)
    # Gaussian elimination with partial pivoting on the 8x8 system.
    n = 8
    matrix = [row + [value] for row, value in zip(rows, values)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(matrix[r][col]))
        matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
        for r in range(n):
            if r != col:
                factor = matrix[r][col] / matrix[col][col]
                matrix[r] = [a - factor * b for a, b in zip(matrix[r], matrix[col])]
    return [matrix[i][n] / matrix[i][i] for i in range(n)]


class Device:
    """The Duo drawn at one size: a fixed right half and a panel that turns around the hinge."""

    def __init__(self, canvas: tuple[int, int], inner_aspect: float, appearance: str, framed: bool):
        self.canvas = canvas
        self.framed = framed
        width, height = canvas
        # Room above and below for the panel's near edge, which grows as it swings toward the viewer.
        self.screen_h = round(height * (0.74 if framed else 0.86))
        self.half_w = round(self.screen_h * inner_aspect / 2)
        self.bezel = round(self.screen_h * 0.024) if framed else 0
        self.radius = round(self.screen_h * 0.06)
        self.cy = height / 2 + (round(height * 0.02) if framed else 0)
        if framed:
            manifest = json.loads((HERE / "manifest.iphone-duo.json").read_text())
            self.palette = manifest["appearances"][appearance]
            sky = generate.add_sky(generate.gradient(canvas, self.palette["background"]), self.palette, "unfold", height / 2007)
            self.background = sky.convert("RGB")
            self.bezel_rgb = generate.color(self.palette["bezel"])
        else:
            self.background = Image.new("RGB", canvas, PAD[appearance])
            self.bezel_rgb = ImageColor.getrgb(PAD[appearance])

    # Panel bodies: the screen with its bezel, square on the hinge side, rounded on the outer side.
    def body(self, screen: Image.Image, hinge_left: bool, spine: bool = False) -> Image.Image:
        bezel, radius = self.bezel, self.radius
        size = (self.half_w + bezel, self.screen_h + 2 * bezel)
        body = Image.new("RGBA", size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(body)
        outline = generate.blend(self.bezel_rgb, (255, 255, 255), 0.28)
        draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius + bezel, fill=(*self.bezel_rgb, 255))
        hinge_x = (0, radius + bezel) if hinge_left else (size[0] - radius - bezel, size[0])
        draw.rectangle((hinge_x[0], 0, hinge_x[1], size[1] - 1), fill=(*self.bezel_rgb, 255))
        if self.framed:
            draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius + bezel, outline=(*outline, 255),
                                   width=2)
            draw.rectangle((hinge_x[0], 2, hinge_x[1], size[1] - 3), fill=(*self.bezel_rgb, 255))
            for y in (0, size[1] - 2):  # Edge highlight continues straight across the hinge side.
                draw.line((hinge_x[0], y, hinge_x[1], y), fill=(*outline, 255), width=2)
        mask = Image.new("L", screen.size, 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.rounded_rectangle((0, 0, screen.width - 1, screen.height - 1), radius=radius, fill=255)
        square = (0, radius) if hinge_left else (screen.width - radius, screen.width)
        mask_draw.rectangle((square[0], 0, square[1], screen.height - 1), fill=255)
        body.paste(screen, (0 if hinge_left else bezel, bezel), mask)
        if spine and self.framed:
            depth = max(4, round(bezel * 0.7))
            draw.rounded_rectangle((0, radius, depth, size[1] - radius), radius=depth // 2,
                                   fill=(*generate.blend(self.bezel_rgb, (255, 255, 255), 0.4), 255))
        return body

    def frame(self, phi: float, pan: float, cover: Image.Image, left: Image.Image, right: Image.Image) -> Image.Image:
        """One frame with the panel at `phi` degrees from flat (180 is folded) and the hinge `pan` px left of centre."""
        width, height = self.canvas
        hinge = width / 2 - pan
        top = self.cy - self.screen_h / 2 - self.bezel
        bottom = self.cy + self.screen_h / 2 + self.bezel
        canvas = self.background.convert("RGBA")
        span = self.half_w + self.bezel
        angle = math.radians(phi)
        focal = 3.2 * span
        scale = focal / (focal - span * math.sin(angle) * 0.55)
        far_x = hinge - math.cos(angle) * span * scale
        far_half = (bottom - top) / 2 * scale
        if self.framed:
            shadow = Image.new("RGBA", self.canvas, (0, 0, 0, 0))
            left_edge = min(hinge, far_x) if phi < 90 else hinge
            right_edge = max(hinge + span, far_x)
            ImageDraw.Draw(shadow).rounded_rectangle(
                (left_edge + 10, top + 30, right_edge + 10, bottom + 30), radius=self.radius, fill=(0, 0, 0, 150))
            canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(height * 0.03)))
        right_body = self.body(right, hinge_left=True)
        canvas.alpha_composite(right_body, (round(hinge), round(top)))
        if phi < 0.5:
            face = self.body(left, hinge_left=False)
            canvas.alpha_composite(face, (round(hinge - span), round(top)))
        elif phi > 179.5:
            face = self.body(cover, hinge_left=True, spine=True)
            canvas.alpha_composite(face, (round(hinge), round(top)))
        else:
            back = phi > 90  # Past upright the viewer sees the panel's back: the cover display.
            face = self.body(cover, hinge_left=True, spine=True) if back else self.body(left, hinge_left=False)
            light = 0.45 + 0.55 * abs(math.cos(angle))
            rgb = ImageEnhance.Brightness(face.convert("RGB")).enhance(light)
            face = Image.merge("RGBA", (*rgb.split(), face.getchannel("A")))
            near = [(hinge, top), (hinge, bottom)]
            far = [(far_x, self.cy - far_half), (far_x, self.cy + far_half)]
            if back:  # Hinge on the face's left edge.
                quad = [near[0], far[0], far[1], near[1]]
            else:  # Hinge on the face's right edge.
                quad = [far[0], near[0], near[1], far[1]]
            source = [(0, 0), (face.width, 0), (face.width, face.height), (0, face.height)]
            coefficients = perspective_coefficients(quad, source)
            warped = face.transform(self.canvas, Image.Transform.PERSPECTIVE, coefficients,
                                    Image.Resampling.BICUBIC, fillcolor=(0, 0, 0, 0))
            canvas = Image.alpha_composite(canvas, warped)
        if self.framed and phi < 0.5:
            overlay = Image.new("RGBA", self.canvas, (0, 0, 0, 0))
            ImageDraw.Draw(overlay).line((hinge, top + self.bezel, hinge, bottom - self.bezel), fill=(255, 255, 255, 14),
                                         width=3)
            canvas = Image.alpha_composite(canvas, overlay)
        return canvas.convert("RGB")


def main() -> None:
    args = parse_args()
    width, height = map(int, args.size.lower().split("x"))
    inner_w, inner_h = probe(args.inner)
    device = Device((width, height), inner_w / inner_h, args.appearance, args.framed)
    half, screen_h = device.half_w, device.screen_h
    cover_size, inner_size = (half, screen_h), (2 * half, screen_h)

    encoder = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}",
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-r", str(FPS),
         str(args.output)], stdin=subprocess.PIPE)
    blank = Image.new("RGB", (half, screen_h), PAD[args.appearance])
    folded_pan = half / 2  # Folded, the remaining half sits centred.
    last_cover = None
    for cover in frames(args.cover, cover_size, 0, args.cover_seconds):
        last_cover = cover
        encoder.stdin.write(device.frame(180, folded_pan, cover, blank, blank).tobytes())
    inner_frames = frames(args.inner, inner_size, args.inner_start, args.inner_seconds)
    first_inner = next(inner_frames)
    left, right = first_inner.crop((0, 0, half, screen_h)), first_inner.crop((half, 0, 2 * half, screen_h))
    steps = round(MOVE_SECONDS * FPS)
    if args.stills:
        args.stills.mkdir(parents=True, exist_ok=True)
    for step in range(steps + 1):
        progress = ease(step / steps)
        image = device.frame(180 * (1 - progress), folded_pan * (1 - progress), last_cover, left, right)
        encoder.stdin.write(image.tobytes())
        if args.stills and step % 6 == 0:
            image.save(args.stills / f"unfold-{step:02d}.png")
    for inner in inner_frames:
        image = device.frame(0, 0, last_cover, inner.crop((0, 0, half, screen_h)), inner.crop((half, 0, 2 * half, screen_h)))
        encoder.stdin.write(image.tobytes())
    encoder.stdin.close()
    if encoder.wait():
        raise RuntimeError("ffmpeg failed to encode the unfold clip")
    print(f"{args.output} cover {args.cover_seconds:.1f}s + move {MOVE_SECONDS}s + inner {args.inner_seconds:.1f}s")


if __name__ == "__main__":
    main()
