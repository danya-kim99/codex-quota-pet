#!/usr/bin/env python3
"""Render the approved astronaut absorption motion as a review-only GIF."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parents[2]
CONCEPT_DIR = ROOT / "docs/concepts"
ASTRONAUT_PATH = CONCEPT_DIR / "astronaut-prototype-sprite-v1.png"
GIF_PATH = CONCEPT_DIR / "astronaut-absorption-prototype-v2.gif"
STORYBOARD_PATH = CONCEPT_DIR / "astronaut-absorption-storyboard-v2.png"

CANVAS_SIZE = (400, 220)
CORE = (200, 110)
BACKGROUND = (5, 8, 24, 255)
MOTION_FRAME_COUNT = 20
FRAME_DURATION_MS = 40
IDLE_FRAME_COUNT = 7


def load_astronaut() -> Image.Image:
    image = Image.open(ASTRONAUT_PATH).convert("RGBA")
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("Astronaut sprite has no visible pixels")
    image = image.crop(bounds)
    target_height = 56
    target_width = round(image.width * target_height / image.height)
    return image.resize((target_width, target_height), Image.Resampling.NEAREST)


def load_hole(frame_index: int, pulse: float = 0) -> Image.Image:
    image = Image.open(
        ROOT / f"Assets/Sprites/frames/quota-50-frame-{frame_index}.png"
    ).convert("RGBA")
    target_height = CANVAS_SIZE[1]
    target_width = round(image.width * target_height / image.height)
    image = image.resize((target_width, target_height), Image.Resampling.NEAREST)

    if pulse > 0:
        scale = 1 + 0.022 * pulse
        image = image.resize(
            (round(image.width * scale), round(image.height * scale)),
            Image.Resampling.NEAREST,
        )
        image = ImageEnhance.Brightness(image).enhance(1 + 0.28 * pulse)
    return image


def paste_centered(canvas: Image.Image, image: Image.Image, center: tuple[int, int]) -> None:
    origin = (round(center[0] - image.width / 2), round(center[1] - image.height / 2))
    canvas.alpha_composite(image, origin)


def quantized(value: float, steps: int) -> float:
    return math.floor(value * steps + 1e-9) / steps


def transformed_astronaut(
    source: Image.Image,
    progress: float,
    angle: float,
    position: tuple[int, int],
) -> Image.Image | None:
    if progress >= 0.995:
        return None

    if progress < 0.64:
        bob = 1 + 0.04 * math.sin(progress * math.tau * 3)
        width = max(1, round(source.width * bob))
        height = max(1, round(source.height * bob))
        rotation = round(math.degrees(angle) / 45) * 45
    else:
        stretch_progress = quantized((progress - 0.64) / 0.36, 5)
        length = min(2.5, 1 + 2 * stretch_progress)
        width_factor = max(0.5, 1 - 0.7 * stretch_progress)

        if stretch_progress < 0.6:
            disappearance = 1
        elif stretch_progress < 0.8:
            disappearance = 0.85
        elif stretch_progress < 1:
            disappearance = 0.6
        else:
            disappearance = 0.3

        width = max(1, round(source.width * width_factor * disappearance))
        height = max(1, round(source.height * length * disappearance))
        inward_angle = math.atan2(CORE[1] - position[1], CORE[0] - position[0])
        rotation = round((math.degrees(inward_angle) - 90) / 45) * 45

    image = source.resize((width, height), Image.Resampling.NEAREST)
    image = image.rotate(rotation, resample=Image.Resampling.NEAREST, expand=True)
    return disintegrated(image, progress)


def disintegrated(image: Image.Image, progress: float) -> Image.Image:
    if progress < 0.72:
        return image

    amount = quantized(min(1, (progress - 0.72) / 0.28), 8)
    alpha = image.getchannel("A")
    draw = ImageDraw.Draw(alpha)
    block_size = 2
    threshold = amount * 0.8

    for y in range(0, image.height, block_size):
        for x in range(0, image.width, block_size):
            sample = ((x * 73_856_093) ^ (y * 19_349_663)) % 997 / 997
            if sample < threshold:
                draw.rectangle(
                    (x, y, x + block_size - 1, y + block_size - 1),
                    fill=0,
                )

    image.putalpha(alpha)
    return image


def motion_state(progress: float) -> tuple[tuple[int, int], float]:
    start_radius = 168
    start_angle = -0.25
    angle = start_angle + math.tau * 0.62 * (progress**0.9)
    radius = start_radius * max(0, 1 - progress**1.35)
    position = (
        round(CORE[0] + math.cos(angle) * radius),
        round(CORE[1] + math.sin(angle) * radius * 0.45),
    )
    return position, angle


def draw_particles(canvas: Image.Image, progress: float, position: tuple[int, int]) -> None:
    if progress < 0.70:
        return

    colors = [
        (255, 246, 224, 255),
        (255, 213, 55, 255),
        (255, 112, 24, 255),
        (180, 84, 255, 255),
        (98, 229, 255, 255),
    ]
    draw = ImageDraw.Draw(canvas)
    phase = min(1, (progress - 0.70) / 0.30)
    delta_x = CORE[0] - position[0]
    delta_y = CORE[1] - position[1]
    distance = max(1, math.hypot(delta_x, delta_y))
    normal_x = -delta_y / distance
    normal_y = delta_x / distance

    for index in range(14):
        activation = index / 22
        local_phase = min(1, max(0, (phase - activation) * 1.7))
        if local_phase <= 0:
            continue
        travel = min(1, local_phase * 0.9 + (index % 3) * 0.04)
        spread = ((index % 5) - 2) * 3 * (1 - travel)
        x = round(position[0] + delta_x * travel + normal_x * spread)
        y = round(position[1] + delta_y * travel + normal_y * spread)
        size = 4 if index % 4 == 0 else 3 if index % 2 == 0 else 2
        draw.rectangle(
            (x - size // 2, y - size // 2, x + size // 2, y + size // 2),
            fill=colors[index % len(colors)],
        )


def draw_core_occlusion(canvas: Image.Image, progress: float) -> None:
    if progress < 0.93:
        return
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((164, 74, 236, 146), fill=(0, 0, 3, 255))


def draw_reaction(canvas: Image.Image, progress: float) -> None:
    if progress < 0.84:
        return

    reaction = math.sin(min(1, (progress - 0.84) / 0.16) * math.pi)
    overlay = Image.new("RGBA", CANVAS_SIZE)
    draw = ImageDraw.Draw(overlay)
    alpha = round(255 * reaction)
    draw.ellipse((157, 67, 243, 153), outline=(255, 126, 24, alpha), width=2)
    draw.ellipse((161, 71, 239, 149), outline=(255, 229, 72, alpha), width=3)
    draw.line((125, 108, 275, 108), fill=(255, 188, 48, alpha), width=4)
    draw.line((132, 109, 268, 109), fill=(255, 255, 224, alpha), width=2)
    canvas.alpha_composite(overlay)


def render_frame(source: Image.Image, progress: float | None, frame_number: int) -> Image.Image:
    pulse = 0.0
    if progress is not None and progress >= 0.84:
        pulse = math.sin(min(1, (progress - 0.84) / 0.16) * math.pi)

    canvas = Image.new("RGBA", CANVAS_SIZE, BACKGROUND)
    hole_frame = int((frame_number * FRAME_DURATION_MS / 1000) / (0.14 / 0.55)) % 6
    paste_centered(canvas, load_hole(hole_frame, pulse), CORE)

    if progress is not None:
        position, angle = motion_state(progress)
        astronaut = transformed_astronaut(source, progress, angle, position)
        if astronaut is not None:
            paste_centered(canvas, astronaut, position)
        draw_particles(canvas, progress, position)
        draw_core_occlusion(canvas, progress)
        draw_reaction(canvas, progress)

    return canvas.convert("RGB")


def main() -> None:
    astronaut = load_astronaut()
    frames: list[Image.Image] = []

    for frame_number in range(IDLE_FRAME_COUNT):
        frames.append(render_frame(astronaut, None, frame_number))

    motion_frames: list[Image.Image] = []
    for index in range(MOTION_FRAME_COUNT):
        progress = index / (MOTION_FRAME_COUNT - 1)
        frame = render_frame(astronaut, progress, IDLE_FRAME_COUNT + index)
        frames.append(frame)
        motion_frames.append(frame)

    for index in range(IDLE_FRAME_COUNT):
        frames.append(
            render_frame(
                astronaut,
                None,
                IDLE_FRAME_COUNT + MOTION_FRAME_COUNT + index,
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

    selected = [0, 4, 8, 12, 15, 17]
    storyboard = Image.new("RGB", (CANVAS_SIZE[0] * 3, CANVAS_SIZE[1] * 2), BACKGROUND[:3])
    for index, selected_frame in enumerate(selected):
        storyboard.paste(
            motion_frames[selected_frame],
            ((index % 3) * CANVAS_SIZE[0], (index // 3) * CANVAS_SIZE[1]),
        )
    storyboard.save(STORYBOARD_PATH, optimize=True)

    print(f"Wrote {GIF_PATH.relative_to(ROOT)} ({len(frames)} frames)")
    print(f"Wrote {STORYBOARD_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
