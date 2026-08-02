#!/usr/bin/env python3
"""Build aligned transparent quota sprites from the generated master sheet."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "Assets/Sprites/source/sprite-master-chroma.png"
FRAME_DIR = ROOT / "Assets/Sprites/frames"
PREVIEW_DIR = ROOT / "Assets/Sprites/previews"
STATES = [100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0]
FRAME_COUNT = 6
CANVAS_SIZE = (384, 272)
ANCHOR = (192, 136)
TARGET_CORE_SIZE = 90
FRAME_DURATION_MS = 140
BOTTOM_ROW_TOP_BLEED = 64


def keyed_cell(master: Image.Image, index: int) -> Image.Image:
    cell_width = master.width // 4
    cell_height = master.height // 3
    column = index % 4
    row = index // 4
    top = row * cell_height
    if row == 2:
        top -= BOTTOM_ROW_TOP_BLEED
    cell = np.array(
        master.crop(
            (
                column * cell_width,
                top,
                (column + 1) * cell_width,
                (row + 1) * cell_height,
            )
        ).convert("RGB")
    )
    red, green, blue = [cell[:, :, channel].astype(np.int16) for channel in range(3)]
    key = (green > 145) & (green > red + 24) & (green > blue + 24)
    alpha = np.where(key, 0, 255).astype(np.uint8)
    rgba = np.dstack((cell, alpha))
    rgba[alpha == 0, :3] = 0
    sprite = Image.fromarray(rgba, "RGBA")
    bounds = sprite.getchannel("A").getbbox()
    if bounds is None or bounds[1] == 0:
        raise RuntimeError(f"Sprite source is empty or clips its top edge: {bounds}")
    return sprite


def core_box(sprite: Image.Image) -> tuple[int, int, int, int]:
    pixels = np.array(sprite)
    height, width = pixels.shape[:2]
    opaque = pixels[:, :, 3] > 0
    dark = pixels[:, :, :3].max(axis=2) < 45
    yy, xx = np.indices((height, width))
    central = (
        (xx > width * 0.24)
        & (xx < width * 0.76)
        & (yy > height * 0.18)
        & (yy < height * 0.82)
    )
    y, x = np.where(opaque & dark & central)
    if not len(x):
        raise RuntimeError("Black core not found")
    return int(x.min()), int(y.min()), int(x.max() + 1), int(y.max() + 1)


def aligned_sprite(cell: Image.Image) -> Image.Image:
    subject_box = cell.getchannel("A").getbbox()
    if subject_box is None:
        raise RuntimeError("Empty sprite cell")

    core = core_box(cell)
    core_center = ((core[0] + core[2]) / 2, (core[1] + core[3]) / 2)
    core_size = ((core[2] - core[0]) + (core[3] - core[1])) / 2
    scale = TARGET_CORE_SIZE / core_size

    subject = cell.crop(subject_box)
    resized_size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(resized_size, Image.Resampling.NEAREST)
    subject_core = (
        (core_center[0] - subject_box[0]) * scale,
        (core_center[1] - subject_box[1]) * scale,
    )
    origin = (
        round(ANCHOR[0] - subject_core[0]),
        round(ANCHOR[1] - subject_core[1]),
    )

    canvas = Image.new("RGBA", CANVAS_SIZE)
    canvas.alpha_composite(subject, origin)
    bounds = canvas.getchannel("A").getbbox()
    if bounds is None or bounds[0] == 0 or bounds[1] == 0 or bounds[2] == canvas.width or bounds[3] == canvas.height:
        raise RuntimeError(f"Sprite clips the common canvas: {bounds}")
    return canvas


def animated_frame(base: Image.Image, frame_index: int) -> Image.Image:
    pixels = np.array(base).astype(np.float32)
    red, green, blue, alpha = [pixels[:, :, channel] for channel in range(4)]
    opaque = alpha > 0
    core = opaque & (pixels[:, :, :3].max(axis=2) < 48)
    purple = opaque & ~core & (blue > green * 1.15) & (blue > red * 0.82) & (blue > 60)
    orange = opaque & ~core & ~purple & (red > green * 1.18) & (green < 190) & (blue < 130)
    gold = opaque & ~core & ~purple & ~orange

    yy, xx = np.indices((base.height, base.width))
    angle = np.arctan2(yy - ANCHOR[1], xx - ANCHOR[0])
    radius = np.hypot(xx - ANCHOR[0], yy - ANCHOR[1])
    phase = frame_index * math.tau / FRAME_COUNT

    factor = np.ones((base.height, base.width), dtype=np.float32)
    factor[gold] = 0.94 + 0.10 * (
        0.5 + 0.5 * np.sin(angle[gold] * 6 + radius[gold] * 0.10 + phase)
    )
    factor[orange] = 0.92 + 0.14 * (
        0.5 + 0.5 * np.sin(angle[orange] * 5 + radius[orange] * 0.08 - phase)
    )
    factor[purple] = 0.90 + 0.18 * (
        0.5 + 0.5 * np.sin(angle[purple] * 4 + radius[purple] * 0.07 + phase * 2)
    )

    pixels[:, :, :3] *= factor[:, :, None]
    pixels[:, :, :3] = np.round(pixels[:, :, :3] / 8) * 8
    pixels[:, :, :3] = np.clip(pixels[:, :, :3], 0, 255)
    pixels[~opaque, :3] = 0
    return Image.fromarray(pixels.astype(np.uint8), "RGBA")


def save_previews(frames_by_state: dict[int, list[Image.Image]]) -> None:
    atlas = Image.new("RGBA", (CANVAS_SIZE[0] * FRAME_COUNT, CANVAS_SIZE[1] * len(STATES)))
    for row, percent in enumerate(STATES):
        for column, frame in enumerate(frames_by_state[percent]):
            atlas.alpha_composite(frame, (column * CANVAS_SIZE[0], row * CANVAS_SIZE[1]))
    atlas.save(PREVIEW_DIR / "all-sprites-atlas.png", optimize=True)

    thumb_size = (CANVAS_SIZE[0] // 2, CANVAS_SIZE[1] // 2)
    label_width = 72
    header_height = 36
    contact = Image.new(
        "RGB",
        (
            label_width + thumb_size[0] * FRAME_COUNT,
            header_height + thumb_size[1] * len(STATES),
        ),
        (5, 8, 24),
    )
    draw = ImageDraw.Draw(contact)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
    except OSError:
        font = ImageFont.load_default()

    for column in range(FRAME_COUNT):
        x = label_width + column * thumb_size[0] + thumb_size[0] // 2
        draw.text((x, 7), f"frame {column + 1}", fill=(145, 156, 190), font=font, anchor="ma")

    for row, percent in enumerate(STATES):
        y = header_height + row * thumb_size[1]
        draw.text((8, y + 8), f"{percent}%", fill=(230, 235, 255), font=font)
        for column, frame in enumerate(frames_by_state[percent]):
            thumb = frame.resize(thumb_size, Image.Resampling.NEAREST)
            contact.paste(thumb, (label_width + column * thumb_size[0], y), thumb)
    contact.save(PREVIEW_DIR / "all-sprites-contact.png", optimize=True)

    for percent, frames in frames_by_state.items():
        frames[0].save(
            PREVIEW_DIR / f"quota-{percent}-animation.gif",
            save_all=True,
            append_images=frames[1:],
            duration=FRAME_DURATION_MS,
            loop=0,
            disposal=2,
            optimize=False,
        )


def validate(frames_by_state: dict[int, list[Image.Image]]) -> None:
    files = sorted(FRAME_DIR.glob("quota-*-frame-*.png"))
    if len(files) != len(STATES) * FRAME_COUNT:
        raise RuntimeError(f"Expected 66 frames, found {len(files)}")

    for percent, frames in frames_by_state.items():
        alpha_hashes = {
            hashlib.sha256(frame.getchannel("A").tobytes()).hexdigest()
            for frame in frames
        }
        frame_hashes = {
            hashlib.sha256(frame.tobytes()).hexdigest()
            for frame in frames
        }
        if len(alpha_hashes) != 1:
            raise RuntimeError(f"{percent}% silhouette changes between frames")
        if len(frame_hashes) != FRAME_COUNT:
            raise RuntimeError(f"{percent}% animation frames are not unique")
        if any(frame.mode != "RGBA" or frame.size != CANVAS_SIZE for frame in frames):
            raise RuntimeError(f"{percent}% has an invalid frame format")
        if any(frame.getpixel((0, 0))[3] != 0 for frame in frames):
            raise RuntimeError(f"{percent}% does not have transparent corners")


def main() -> None:
    FRAME_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    master = Image.open(MASTER).convert("RGB")
    if master.width % 4 or master.height % 3:
        raise RuntimeError(f"Master must be a 4x3 grid, got {master.size}")

    frames_by_state: dict[int, list[Image.Image]] = {}
    for index, percent in enumerate(STATES):
        base = aligned_sprite(keyed_cell(master, index))
        frames = [animated_frame(base, frame_index) for frame_index in range(FRAME_COUNT)]
        frames_by_state[percent] = frames
        for frame_index, frame in enumerate(frames):
            frame.save(
                FRAME_DIR / f"quota-{percent}-frame-{frame_index}.png",
                optimize=True,
            )

    validate(frames_by_state)
    save_previews(frames_by_state)
    manifest = {
        "canvas": {"width": CANVAS_SIZE[0], "height": CANVAS_SIZE[1]},
        "anchor": {"x": ANCHOR[0], "y": ANCHOR[1]},
        "framesPerState": FRAME_COUNT,
        "frameDurationMs": FRAME_DURATION_MS,
        "states": STATES,
        "filenamePattern": "frames/quota-{percent}-frame-{frame}.png",
    }
    (ROOT / "Assets/Sprites/manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(STATES) * FRAME_COUNT} aligned RGBA frames")


if __name__ == "__main__":
    main()
