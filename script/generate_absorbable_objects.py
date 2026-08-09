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
FINAL_CHARACTER_PAIR_SOURCE = ROOT / "docs/concepts/absorbable-people-06-07-v2.png"
OUTPUT_DIR = ROOT / "Assets/Sprites/objects"
PREVIEW = ROOT / "Assets/Sprites/previews/absorbable-objects-atlas.png"
CANVAS_SIZE = (80, 80)
SUBJECT_MAX_SIZE = 50
PREVIEW_BACKGROUND = (5, 8, 24)
RUNTIME_RENDERED_SIZES = (60, 80, 100)
OBJECT_STRONG_FOREGROUND_THRESHOLD = 80
EXPECTED_OBJECT_SOURCE_BOUNDS = {
    "ufo": (13, 76, 194, 239),
    "broken-solar-panel": (14, 55, 183, 222),
    "fox": (23, 8, 189, 217),
    "bear-cub": (10, 19, 174, 200),
}

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


def remove_tiny_components(
    mask: np.ndarray,
    minimum_area: int = 4,
    required_pixels: np.ndarray | None = None,
) -> np.ndarray:
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

        has_required_pixel = required_pixels is None or any(
            required_pixels[y, x] for x, y in component
        )
        if len(component) >= minimum_area and has_required_pixel:
            for x, y in component:
                cleaned[y, x] = True

    return cleaned


def component_labels(mask: np.ndarray) -> tuple[np.ndarray, int]:
    height, width = mask.shape
    labels = np.zeros(mask.shape, dtype=np.int32)
    count = 0

    for start_y, start_x in zip(*np.where(mask)):
        if labels[start_y, start_x]:
            continue
        count += 1
        labels[start_y, start_x] = count
        stack = [(int(start_x), int(start_y))]
        while stack:
            x, y = stack.pop()
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
                    and not labels[neighbor_y, neighbor_x]
                ):
                    labels[neighbor_y, neighbor_x] = count
                    stack.append((neighbor_x, neighbor_y))

    return labels, count


def nonbridging_coverage(
    nearest_mask: np.ndarray,
    coverage: np.ndarray,
) -> tuple[np.ndarray, int]:
    labels, nearest_component_count = component_labels(nearest_mask)
    parent = list(range(nearest_component_count + 1))
    origin = list(range(nearest_component_count + 1))
    accepted = np.zeros(nearest_mask.shape, dtype=bool)

    def find(component: int) -> int:
        while parent[component] != component:
            parent[component] = parent[parent[component]]
            component = parent[component]
        return component

    def union(left: int, right: int) -> int:
        left = find(left)
        right = find(right)
        if left == right:
            return left
        if right < left:
            left, right = right, left
        parent[right] = left
        origin[left] = origin[left] or origin[right]
        return left

    recovered = (coverage > 0) & ~nearest_mask
    candidates = sorted(
        ((int(y), int(x)) for y, x in np.argwhere(recovered)),
        key=lambda point: (-int(coverage[point]), point[0], point[1]),
    )
    height, width = nearest_mask.shape
    for y, x in candidates:
        neighbors = {
            find(int(labels[neighbor_y, neighbor_x]))
            for neighbor_x, neighbor_y in (
                (x - 1, y),
                (x + 1, y),
                (x, y - 1),
                (x, y + 1),
            )
            if 0 <= neighbor_x < width
            and 0 <= neighbor_y < height
            and labels[neighbor_y, neighbor_x]
        }
        if len({origin[component] for component in neighbors if origin[component]}) > 1:
            continue
        if neighbors:
            component = min(neighbors)
            for neighbor in neighbors:
                component = union(component, neighbor)
        else:
            component = len(parent)
            parent.append(component)
            origin.append(0)
        labels[y, x] = component
        accepted[y, x] = True

    return accepted, nearest_component_count


def coverage_preserving_resize(
    image: Image.Image,
    size: tuple[int, int],
) -> Image.Image:
    nearest = image.resize(size, Image.Resampling.NEAREST)
    coverage = image.getchannel("A").resize(size, Image.Resampling.BOX)
    coverage_pixels = np.asarray(coverage)
    coverage_mask = coverage_pixels > 0
    pixels = np.asarray(nearest).copy()
    nearest_mask = pixels[:, :, 3] > 0
    if np.any(nearest_mask & ~coverage_mask):
        raise RuntimeError("NEAREST alpha falls outside BOX source coverage")

    recovered, nearest_component_count = nonbridging_coverage(
        nearest_mask,
        coverage_pixels,
    )
    resized_mask = nearest_mask | recovered
    box_pixels = np.asarray(
        image.convert("RGBa").resize(size, Image.Resampling.BOX).convert("RGBA")
    )
    if np.any(box_pixels[recovered, 3] == 0):
        raise RuntimeError("Recovered source coverage has no premultiplied RGBA color")
    pixels[recovered, :3] = box_pixels[recovered, :3]
    pixels[:, :, 3] = resized_mask.astype(np.uint8) * 255

    resized = Image.fromarray(pixels, "RGBA")
    resized_alpha = np.asarray(resized.getchannel("A"))
    if np.any(nearest_mask & ~(resized_alpha > 0)) or np.any(
        (resized_alpha > 0) & ~coverage_mask
    ):
        raise RuntimeError("Resized alpha falls outside NEAREST-to-BOX coverage")
    if set(resized_alpha.ravel()) - {0, 255}:
        raise RuntimeError("Coverage-preserving resize produced antialiased alpha")
    if component_labels(resized_alpha > 0)[1] < nearest_component_count:
        raise RuntimeError("Recovered source coverage joined separate NEAREST components")
    return resized


def extract_mask(
    cell: Image.Image,
    minimum_component_area: int = 4,
    edge_clear_width: int = 10,
    strong_foreground_threshold: float | None = None,
) -> np.ndarray:
    pixels = np.asarray(cell.convert("RGB"))
    background = background_color(pixels)
    distance = np.linalg.norm(pixels.astype(np.float32) - background, axis=2)

    mask = distance > 10
    if strong_foreground_threshold is not None:
        mask = remove_tiny_components(
            mask,
            minimum_component_area,
            distance > strong_foreground_threshold,
        )
    allowed = distance > 4.5
    for _ in range(4):
        expanded = np.asarray(
            Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
        ) > 0
        mask |= expanded & allowed

    if edge_clear_width:
        mask[:edge_clear_width] = False
        mask[-edge_clear_width:] = False
        mask[:, :edge_clear_width] = False
        mask[:, -edge_clear_width:] = False
    return remove_tiny_components(fill_holes(mask), minimum_component_area)


def extract_sprite(
    cell: Image.Image,
    minimum_component_area: int = 4,
    edge_clear_width: int = 10,
    strong_foreground_threshold: float | None = None,
) -> Image.Image:
    mask = extract_mask(
        cell,
        minimum_component_area,
        edge_clear_width,
        strong_foreground_threshold,
    )

    alpha = Image.fromarray(mask.astype(np.uint8) * 255, "L")
    sprite = cell.convert("RGBA")
    sprite.putalpha(alpha)
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError("Extracted an empty object cell")

    sprite = sprite.crop(bounds)
    scale = min(SUBJECT_MAX_SIZE / sprite.width, SUBJECT_MAX_SIZE / sprite.height)
    sprite = coverage_preserving_resize(
        sprite,
        (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
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


def validate_object_source_extraction(sprites: dict[str, Image.Image]) -> None:
    source = Image.open(OBJECT_SOURCE).convert("RGB")
    for index, (identifier, _) in enumerate(OBJECT_MODELS):
        column = index % 6
        row = index // 6
        cell = source.crop(
            (
                round(column * source.width / 6),
                round(row * source.height / 4),
                round((column + 1) * source.width / 6),
                round((row + 1) * source.height / 4),
            )
        )
        minimum_component_area = 5 if identifier == "axolotl" else 4
        source_mask = extract_mask(
            cell,
            minimum_component_area,
            edge_clear_width=0,
            strong_foreground_threshold=OBJECT_STRONG_FOREGROUND_THRESHOLD,
        )
        if (
            source_mask[0].any()
            or source_mask[-1].any()
            or source_mask[:, 0].any()
            or source_mask[:, -1].any()
        ):
            raise RuntimeError(f"{identifier} retains contact-sheet grid pixels")

        expected_bounds = EXPECTED_OBJECT_SOURCE_BOUNDS.get(identifier)
        if expected_bounds is not None:
            actual_bounds = Image.fromarray(source_mask).getbbox()
            if actual_bounds != expected_bounds:
                raise RuntimeError(
                    f"{identifier} lost approved source boundary coverage: "
                    f"expected {expected_bounds}, found {actual_bounds}"
                )

        expected_sprite = extract_sprite(
            cell,
            minimum_component_area,
            edge_clear_width=0,
            strong_foreground_threshold=OBJECT_STRONG_FOREGROUND_THRESHOLD,
        )
        if expected_sprite.tobytes() != sprites[identifier].tobytes():
            raise RuntimeError(f"{identifier} does not use full-cell source extraction")


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
        last_x = image.width - 1
        last_y = image.height - 1
        if any(
            image.getpixel(point)[3]
            for point in ((0, 0), (last_x, 0), (0, last_y), (last_x, last_y))
        ):
            raise RuntimeError(f"{identifier} has a nontransparent corner")
        for rendered_size in RUNTIME_RENDERED_SIZES:
            rendered = image.resize((rendered_size, rendered_size), Image.Resampling.NEAREST)
            rendered_alpha = rendered.getchannel("A")
            rendered_bounds = rendered_alpha.getbbox()
            if rendered_bounds is None or (
                rendered_bounds[0] == 0
                or rendered_bounds[1] == 0
                or rendered_bounds[2] == rendered.width
                or rendered_bounds[3] == rendered.height
            ):
                raise RuntimeError(
                    f"{identifier} touches the rendered canvas edge at "
                    f"{rendered_size} × {rendered_size}: {rendered_bounds}"
                )
            if set(rendered_alpha.get_flattened_data()) - {0, 255}:
                raise RuntimeError(
                    f"{identifier} has antialiased rendered alpha at "
                    f"{rendered_size} × {rendered_size}"
                )

    validate_object_source_extraction(sprites)


def save_preview(sprites: dict[str, Image.Image]) -> None:
    cell_size = (128, 112)
    columns = 7
    rows = (len(MODELS) + columns - 1) // columns
    preview = Image.new(
        "RGB",
        (cell_size[0] * columns, cell_size[1] * rows),
        PREVIEW_BACKGROUND,
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
    inset_overrides: dict[str, int] | None = None,
    minimum_component_area_overrides: dict[str, int] | None = None,
    edge_clear_width: int = 10,
    strong_foreground_threshold: float | None = None,
) -> dict[str, Image.Image]:
    source = Image.open(source_path).convert("RGB")
    sprites: dict[str, Image.Image] = {}

    for index, (identifier, _) in enumerate(models):
        column = index % columns
        row = index // columns
        model_inset = (inset_overrides or {}).get(identifier, inset)
        minimum_component_area = (minimum_component_area_overrides or {}).get(
            identifier,
            4,
        )
        cell = source.crop(
            (
                round(column * source.width / columns) + model_inset,
                round(row * source.height / rows) + model_inset,
                round((column + 1) * source.width / columns) - model_inset,
                round((row + 1) * source.height / rows) - model_inset,
            )
        )
        sprites[identifier] = extract_sprite(
            cell,
            minimum_component_area,
            edge_clear_width,
            strong_foreground_threshold,
        )

    return sprites


def main() -> None:
    sprites = extract_sheet(
        OBJECT_SOURCE,
        OBJECT_MODELS,
        columns=6,
        rows=4,
        inset=0,
        minimum_component_area_overrides={"axolotl": 5},
        edge_clear_width=0,
        strong_foreground_threshold=OBJECT_STRONG_FOREGROUND_THRESHOLD,
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
