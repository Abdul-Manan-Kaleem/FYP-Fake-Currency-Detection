import random, cv2, numpy as np
def local_blur(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[y1:y2, x1:x2]

    if region.size == 0:
        return result

    kernel = random.choice([
        9,
        15,
        21
    ])

    result[y1:y2, x1:x2] = cv2.GaussianBlur(
        region,
        (kernel, kernel),
        0
    )

    return result


def local_noise(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[
        y1:y2,
        x1:x2
    ].astype(np.float32)

    if region.size == 0:
        return result

    sigma = random.uniform(
        12,
        28
    )

    noise = np.random.normal(
        0,
        sigma,
        region.shape
    )

    altered = region + noise

    altered = np.clip(
        altered,
        0,
        255
    ).astype(np.uint8)

    result[y1:y2, x1:x2] = altered

    return result


def local_brightness(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[
        y1:y2,
        x1:x2
    ].astype(np.float32)

    if region.size == 0:
        return result

    factor = random.choice([
        random.uniform(0.70, 0.85),
        random.uniform(1.15, 1.30)
    ])

    altered = region * factor

    altered = np.clip(
        altered,
        0,
        255
    ).astype(np.uint8)

    result[y1:y2, x1:x2] = altered

    return result


def local_contrast(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[
        y1:y2,
        x1:x2
    ]

    if region.size == 0:
        return result

    factor = random.choice([
        random.uniform(0.65, 0.85),
        random.uniform(1.15, 1.35)
    ])

    region_float = region.astype(
        np.float32
    )

    mean = np.mean(
        region_float,
        axis=(0, 1),
        keepdims=True
    )

    altered = (
        (region_float - mean) * factor
        + mean
    )

    altered = np.clip(
        altered,
        0,
        255
    ).astype(np.uint8)

    result[y1:y2, x1:x2] = altered

    return result


def local_color_shift(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[
        y1:y2,
        x1:x2
    ]

    if region.size == 0:
        return result

    hsv = cv2.cvtColor(
        region,
        cv2.COLOR_RGB2HSV
    )

    shift = random.choice([
        random.randint(-12, -5),
        random.randint(5, 12)
    ])

    hue = hsv[:, :, 0].astype(
        np.int16
    )

    hue = (hue + shift) % 180

    hsv[:, :, 0] = hue.astype(
        np.uint8
    )

    altered = cv2.cvtColor(
        hsv,
        cv2.COLOR_HSV2RGB
    )

    result[y1:y2, x1:x2] = altered

    return result


def local_noise_texture(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[
        y1:y2,
        x1:x2
    ]

    if region.size == 0:
        return result

    gray = cv2.cvtColor(
        region,
        cv2.COLOR_RGB2GRAY
    )

    noise = np.random.normal(
        0,
        18,
        gray.shape
    ).astype(
        np.float32
    )

    texture = (
        gray.astype(np.float32)
        + noise
    )

    texture = np.clip(
        texture,
        0,
        255
    ).astype(np.uint8)

    texture_rgb = cv2.cvtColor(
        texture,
        cv2.COLOR_GRAY2RGB
    )

    # Blend with original rather than completely replacing it
    altered = cv2.addWeighted(
        region,
        0.70,
        texture_rgb,
        0.30,
        0
    )

    result[y1:y2, x1:x2] = altered

    return result


def local_partial_obstruction(image, box):

    x1, y1, x2, y2 = box

    result = image.copy()

    region = result[
        y1:y2,
        x1:x2
    ].copy()

    if region.size == 0:
        return result

    h, w = region.shape[:2]

    ox1 = int(w * 0.25)
    oy1 = int(h * 0.25)

    ox2 = int(w * 0.75)
    oy2 = int(h * 0.75)

    # Use the surrounding region's average
    # instead of a pure black/white rectangle.
    average = np.mean(
        region,
        axis=(0, 1)
    ).astype(np.uint8)

    cv2.rectangle(
        region,
        (ox1, oy1),
        (ox2, oy2),
        tuple(
            int(v)
            for v in average
        ),
        -1
    )

    result[
        y1:y2,
        x1:x2
    ] = region

    return result

def get_safe_area(image):
    h, w = image.shape[:2]
    return int(w*0.12), int(h*0.12), int(w*0.88), int(h*0.88)
GRID_COLS=8; GRID_ROWS=4
def get_patch_region(image, patch_index):

    h, w = image.shape[:2]

    safe_x1, safe_y1, safe_x2, safe_y2 = get_safe_area(image)

    safe_w = safe_x2 - safe_x1
    safe_h = safe_y2 - safe_y1

    patch_w = safe_w / GRID_COLS
    patch_h = safe_h / GRID_ROWS

    row = patch_index // GRID_COLS
    col = patch_index % GRID_COLS

    px1 = int(safe_x1 + col * patch_w)
    py1 = int(safe_y1 + row * patch_h)

    px2 = int(safe_x1 + (col + 1) * patch_w)
    py2 = int(safe_y1 + (row + 1) * patch_h)

    pw = px2 - px1
    ph = py2 - py1

    # Alter only part of the selected patch.
    region_ratio = random.uniform(
        0.30,
        0.55
    )

    rw = max(
        12,
        int(pw * region_ratio)
    )

    rh = max(
        12,
        int(ph * region_ratio)
    )

    rw = min(rw, pw - 4)
    rh = min(rh, ph - 4)

    rx1 = px1 + (pw - rw) // 2
    ry1 = py1 + (ph - rh) // 2

    rx2 = rx1 + rw
    ry2 = ry1 + rh

    return (
        rx1,
        ry1,
        rx2,
        ry2
    )
ALTERATIONS = {

    "local_blur":
        local_blur,

    "local_noise":
        local_noise,

    "local_brightness":
        local_brightness,

    "local_contrast":
        local_contrast,

    "local_color_shift":
        local_color_shift,

    "local_noise_texture":
        local_noise_texture,

    "local_partial_obstruction":
        local_partial_obstruction,
}


ALTERATION_NAMES = list(
    ALTERATIONS.keys()
)


print("Alteration types:")

for name in ALTERATION_NAMES:
    print("-", name)