#!/usr/bin/env python3
"""Render a review-only three-object absorption prototype."""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw

import render_astronaut_absorption_prototype as single


ROOT = Path(__file__).resolve().parents[2]
CONCEPT_DIR = ROOT / "docs/concepts"
GIF_PATH = CONCEPT_DIR / "triple-absorption-prototype-v2.gif"
STORYBOARD_PATH = CONCEPT_DIR / "triple-absorption-storyboard-v2.png"
FRAME_DURATION_MS = 40
IDLE_FRAME_COUNT = 7


@dataclass(frozen=True)
class PrototypeObject:
    sprite_path: Path
    target_height: int
    start_time: float
    duration: float
    start_angle: float
    turns: float
    vertical_scale: float


OBJECTS = [
    PrototypeObject(
        CONCEPT_DIR / "astronaut-prototype-sprite-v1.png",
        56,
        0.00,
        0.92,
        -0.22,
        0.62,
        0.43,
    ),
    PrototypeObject(
        CONCEPT_DIR / "rocket-prototype-sprite-v1.png",
        52,
        0.10,
        1.04,
        math.pi - 0.12,
        -0.56,
        0.38,
    ),
    PrototypeObject(
        CONCEPT_DIR / "kitten-prototype-sprite-v1.png",
        54,
        0.22,
        0.98,
        -math.pi / 2,
        0.70,
        0.50,
    ),
]


def load_sprite(path: Path, target_height: int) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError(f"Empty prototype sprite: {path}")
    image = image.crop(bounds)
    target_width = round(image.width * target_height / image.height)
    return image.resize((target_width, target_height), Image.Resampling.NEAREST)


def motion_state(item: PrototypeObject, progress: float) -> tuple[tuple[int, int], float]:
    radius = 168 * max(0, 1 - progress**1.35)
    angle = item.start_angle + math.tau * item.turns * (progress**0.9)
    position = (
        round(single.CORE[0] + math.cos(angle) * radius),
        round(single.CORE[1] + math.sin(angle) * radius * item.vertical_scale),
    )
    return position, angle


def reaction_intensity(progress: float) -> float:
    if progress < 0.84 or progress > 1:
        return 0
    return math.sin(min(1, (progress - 0.84) / 0.16) * math.pi)


def draw_reaction(canvas: Image.Image, intensity: float) -> None:
    if intensity <= 0:
        return
    overlay = Image.new("RGBA", single.CANVAS_SIZE)
    draw = ImageDraw.Draw(overlay)
    alpha = round(255 * intensity)
    draw.ellipse((157, 67, 243, 153), outline=(255, 126, 24, alpha), width=2)
    draw.ellipse((161, 71, 239, 149), outline=(255, 229, 72, alpha), width=3)
    draw.line((125, 108, 275, 108), fill=(255, 188, 48, alpha), width=4)
    draw.line((132, 109, 268, 109), fill=(255, 255, 224, alpha), width=2)
    canvas.alpha_composite(overlay)


def render_frame(
    sprites: list[Image.Image],
    elapsed: float | None,
    frame_number: int,
) -> Image.Image:
    active: list[tuple[PrototypeObject, Image.Image, float]] = []
    if elapsed is not None:
        for item, sprite in zip(OBJECTS, sprites, strict=True):
            progress = (elapsed - item.start_time) / item.duration
            if 0 <= progress <= 1:
                active.append((item, sprite, progress))

    total_reaction = min(1, sum(reaction_intensity(progress) for _, _, progress in active))
    canvas = Image.new("RGBA", single.CANVAS_SIZE, single.BACKGROUND)
    hole_frame = int((frame_number * FRAME_DURATION_MS / 1000) / (0.14 / 0.55)) % 6
    single.paste_centered(canvas, single.load_hole(hole_frame, total_reaction), single.CORE)

    active.sort(key=lambda value: value[2])
    should_occlude_core = False
    for item, sprite, progress in active:
        position, angle = motion_state(item, progress)
        transformed = single.transformed_astronaut(sprite, progress, angle, position)
        if transformed is not None:
            single.paste_centered(canvas, transformed, position)
        single.draw_particles(canvas, progress, position)
        should_occlude_core = should_occlude_core or progress >= 0.93

    if should_occlude_core:
        draw = ImageDraw.Draw(canvas)
        draw.ellipse((164, 74, 236, 146), fill=(0, 0, 3, 255))
    draw_reaction(canvas, total_reaction)
    return canvas.convert("RGB")


def main() -> None:
    sprites = [load_sprite(item.sprite_path, item.target_height) for item in OBJECTS]
    last_finish = max(item.start_time + item.duration for item in OBJECTS)
    motion_frame_count = math.ceil(last_finish * 1000 / FRAME_DURATION_MS) + 1
    frames: list[Image.Image] = []
    motion_frames: list[Image.Image] = []

    for frame_number in range(IDLE_FRAME_COUNT):
        frames.append(render_frame(sprites, None, frame_number))

    for index in range(motion_frame_count):
        elapsed = index * FRAME_DURATION_MS / 1000
        frame = render_frame(sprites, elapsed, IDLE_FRAME_COUNT + index)
        frames.append(frame)
        motion_frames.append(frame)

    for index in range(IDLE_FRAME_COUNT):
        frames.append(
            render_frame(
                sprites,
                None,
                IDLE_FRAME_COUNT + motion_frame_count + index,
            )
        )

    frames[0].save(
        GIF_PATH,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        disposal=2,
        optimize=False,
    )

    selected = [0, 4, 8, 12, 18, motion_frame_count - 2]
    storyboard = Image.new(
        "RGB",
        (single.CANVAS_SIZE[0] * 3, single.CANVAS_SIZE[1] * 2),
        single.BACKGROUND[:3],
    )
    for index, selected_frame in enumerate(selected):
        storyboard.paste(
            motion_frames[selected_frame],
            (
                (index % 3) * single.CANVAS_SIZE[0],
                (index // 3) * single.CANVAS_SIZE[1],
            ),
        )
    storyboard.save(STORYBOARD_PATH, optimize=True)

    print(f"Wrote {GIF_PATH.relative_to(ROOT)} ({len(frames)} frames)")
    print(f"Wrote {STORYBOARD_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
