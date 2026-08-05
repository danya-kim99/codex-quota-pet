#!/usr/bin/env python3
"""Extract approved absorbable-object sprites and build their runtime manifest."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OBJECT_SOURCE = ROOT / "docs/concepts/absorbable-objects-contact-sheet-v1.png"
CHARACTER_SOURCE = ROOT / "docs/concepts/characters-contact-sheet-v1.png"
CREAM_SWEATER_SOURCE = ROOT / "docs/concepts/absorbable-person-05-v1.png"
FINAL_CHARACTER_PAIR_SOURCE = ROOT / "docs/concepts/absorbable-people-06-07-v1.png"
OUTPUT_DIR = ROOT / "Assets/Sprites/objects"
PREVIEW = ROOT / "Assets/Sprites/previews/absorbable-objects-atlas.png"
CANVAS_SIZE = (64, 64)
SUBJECT_MAX_SIZE = 50

MODELS = [
    ("astronaut", "space"),
    ("rocket", "space"),
    ("satellite", "space"),
    ("lunar-rover", "space"),
    ("ufo", "space"),
    ("space-probe", "space"),
    ("comet", "space"),
    ("asteroid", "space"),
    ("ringed-planet", "space"),
    ("space-capsule", "space"),
    ("broken-solar-panel", "space"),
    ("space-wrench", "space"),
    ("kitten", "animals"),
    ("corgi", "animals"),
    ("bunny", "animals"),
    ("red-panda", "animals"),
    ("axolotl", "animals"),
    ("frog", "animals"),
    ("duckling", "animals"),
    ("raccoon", "animals"),
    ("hamster", "animals"),
    ("fox", "animals"),
    ("penguin", "animals"),
    ("bear-cub", "animals"),
    ("character-white-shirt", "characters"),
    ("character-purple-shirt", "characters"),
    ("character-green-hoodie", "characters"),
    ("character-glasses", "characters"),
    ("character-cream-sweater", "characters"),
    ("character-cargo-skirt", "characters"),
    ("character-botanical-shirt", "characters"),
]

OBJECT_MODELS = MODELS[:24]
CHARACTER_MODELS = MODELS[24:]


def background_color(cell: np.ndarray) -> np.ndarray:
    border = np.concatenate(
        (
            cell[:12].reshape(-1, 3),
            cell[-12:].reshape(-1, 3),
            cell[:, :12].reshape(-1, 3),
            cell[:, -12:].reshape(-1, 3),
        )
    )
    return np.median(border, axis=0)


def fill_holes(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    outside = np.zeros_like(mask)
    stack: list[tuple[int, int]] = []

    for x in range(width):
        stack.extend(((x, 0), (x, height - 1)))
    for y in range(height):
        stack.extend(((0, y), (width - 1, y)))

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= width or y >= height:
            continue
        if outside[y, x] or mask[y, x]:
            continue
        outside[y, x] = True
        stack.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))

    return mask | (~outside & ~mask)


def remove_tiny_components(mask: np.ndarray, minimum_area: int = 4) -> np.ndarray:
    height, width = mask.shape
    visited = np.zeros_like(mask)
    cleaned = np.zeros_like(mask)

    for start_y, start_x in zip(*np.where(mask)):
        if visited[start_y, start_x]:
            continue
        stack = [(int(start_x), int(start_y))]
        component: list[tuple[int, int]] = []
        visited[start_y, start_x] = True

        while stack:
            x, y = stack.pop()
            component.append((x, y))
            for neighbor_x, neighbor_y in (
                (x - 1, y),
                (x + 1, y),
                (x, y - 1),
                (x, y + 1),
            ):
                if (
                    0 <= neighbor_x < width
                    and 0 <= neighbor_y < height
                    and mask[neighbor_y, neighbor_x]
                    and not visited[neighbor_y, neighbor_x]
                ):
                    visited[neighbor_y, neighbor_x] = True
                    stack.append((neighbor_x, neighbor_y))

        if len(component) >= minimum_area:
            for x, y in component:
                cleaned[y, x] = True

    return cleaned


def extract_sprite(cell: Image.Image) -> Image.Image:
    pixels = np.asarray(cell.convert("RGB"))
    background = background_color(pixels)
    distance = np.linalg.norm(pixels.astype(np.float32) - background, axis=2)

    mask = distance > 10
    allowed = distance > 4.5
    for _ in range(4):
        expanded = np.asarray(
            Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
        ) > 0
        mask |= expanded & allowed

    mask[:10] = False
    mask[-10:] = False
    mask[:, :10] = False
    mask[:, -10:] = False
    mask = remove_tiny_components(fill_holes(mask))

    alpha = Image.fromarray(mask.astype(np.uint8) * 255, "L")
    sprite = cell.convert("RGBA")
    sprite.putalpha(alpha)
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError("Extracted an empty object cell")

    sprite = sprite.crop(bounds)
    scale = min(SUBJECT_MAX_SIZE / sprite.width, SUBJECT_MAX_SIZE / sprite.height)
    sprite = sprite.resize(
        (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
        Image.Resampling.NEAREST,
    )

    canvas = Image.new("RGBA", CANVAS_SIZE)
    canvas.alpha_composite(
        sprite,
        (
            (CANVAS_SIZE[0] - sprite.width) // 2,
            (CANVAS_SIZE[1] - sprite.height) // 2,
        ),
    )
    return canvas


def validate(sprites: dict[str, Image.Image]) -> None:
    if len(sprites) != len(MODELS):
        raise RuntimeError(f"Expected {len(MODELS)} sprites, found {len(sprites)}")

    ids = [identifier for identifier, _ in MODELS]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Absorbable object IDs are not unique")

    for identifier, image in sprites.items():
        alpha = image.getchannel("A")
        bounds = alpha.getbbox()
        if image.mode != "RGBA" or image.size != CANVAS_SIZE:
            raise RuntimeError(f"{identifier} has an invalid format")
        if bounds is None:
            raise RuntimeError(f"{identifier} is empty")
        if bounds[0] == 0 or bounds[1] == 0 or bounds[2] == image.width or bounds[3] == image.height:
            raise RuntimeError(f"{identifier} touches the canvas edge: {bounds}")
        if set(alpha.get_flattened_data()) - {0, 255}:
            raise RuntimeError(f"{identifier} contains antialiased alpha")
        if any(image.getpixel(point)[3] for point in ((0, 0), (63, 0), (0, 63), (63, 63))):
            raise RuntimeError(f"{identifier} has a nontransparent corner")


def save_preview(sprites: dict[str, Image.Image]) -> None:
    cell_size = (128, 112)
    columns = 7
    rows = (len(MODELS) + columns - 1) // columns
    preview = Image.new(
        "RGB",
        (cell_size[0] * columns, cell_size[1] * rows),
        (5, 8, 24),
    )
    draw = ImageDraw.Draw(preview)
    for index, (identifier, _) in enumerate(MODELS):
        column = index % columns
        row = index // columns
        origin = (column * cell_size[0], row * cell_size[1])
        sprite = sprites[identifier].resize((96, 96), Image.Resampling.NEAREST)
        preview.paste(sprite, (origin[0] + 16, origin[1] + 8), sprite)
        draw.rectangle(
            (
                origin[0],
                origin[1],
                origin[0] + cell_size[0] - 1,
                origin[1] + cell_size[1] - 1,
            ),
            outline=(14, 20, 48),
        )
    preview.save(PREVIEW, optimize=True)


def extract_sheet(
    source_path: Path,
    models: list[tuple[str, str]],
    columns: int,
    rows: int,
    inset: int = 0,
) -> dict[str, Image.Image]:
    source = Image.open(source_path).convert("RGB")
    sprites: dict[str, Image.Image] = {}

    for index, (identifier, _) in enumerate(models):
        column = index % columns
        row = index // columns
        cell = source.crop(
            (
                round(column * source.width / columns) + inset,
                round(row * source.height / rows) + inset,
                round((column + 1) * source.width / columns) - inset,
                round((row + 1) * source.height / rows) - inset,
            )
        )
        sprites[identifier] = extract_sprite(cell)

    return sprites


def main() -> None:
    sprites = extract_sheet(
        OBJECT_SOURCE,
        OBJECT_MODELS,
        columns=6,
        rows=4,
        inset=20,
    )
    sprites.update(
        extract_sheet(CHARACTER_SOURCE, CHARACTER_MODELS[:4], columns=4, rows=1, inset=28)
    )
    sprites.update(
        extract_sheet(CREAM_SWEATER_SOURCE, CHARACTER_MODELS[4:5], columns=1, rows=1, inset=28)
    )
    sprites.update(
        extract_sheet(
            FINAL_CHARACTER_PAIR_SOURCE,
            CHARACTER_MODELS[5:],
            columns=2,
            rows=1,
            inset=28,
        )
    )
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for identifier, sprite in sprites.items():
        sprite.save(OUTPUT_DIR / f"absorb-{identifier}.png", optimize=True)

    validate(sprites)
    save_preview(sprites)

    manifest = {
        "canvas": {"width": CANVAS_SIZE[0], "height": CANVAS_SIZE[1]},
        "categories": [
            {"id": "space", "weight": 2},
            {"id": "animals", "weight": 2},
            {"id": "characters", "weight": 1},
        ],
        "objects": [
            {
                "id": identifier,
                "category": category,
                "asset": f"absorb-{identifier}",
            }
            for identifier, category in MODELS
        ],
    }
    (OUTPUT_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Generated and validated {len(sprites)} absorbable object sprites")


if __name__ == "__main__":
    main()
