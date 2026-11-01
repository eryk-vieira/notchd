#!/usr/bin/env python3
"""Makes an agent's avatar from a photo, for notchd (core/AvatarView.qml).

    make-avatar.py --photo <image> --out <folder> --models <cache folder>

Writes <folder>, replaced as a whole once everything is ready:

  color.png   the photo, the person's mask in its alpha (hair included)
  depth.png   how near each point is, 0 far .. 255 near; 0 outside the person
  face.json   {"size": [w, h], "points": {name: [x, y]}} in the photo's pixels
  source.jpg  the photo as used: upright, at most 768 px

The rules that read face.json (where the mouth and eyes are, the framing)
are core/Avatar.js's; this only makes the files.

Progress goes to stdout, one JSON object a line: {"step": ..., "progress":
0..1} while it works, then {"done": true}, or {"error": ..., "packages":
[...]}; the exit code is 0 only when done. Needs python-numpy,
python-pillow, python-onnxruntime-cpu and python-mediapipe. The models are
downloaded into --models the first time (about 120 MB), each checked
against its sha256.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.request

# name: (url, sha256, size in bytes). Pinned: a model that changes upstream
# fails the check instead of changing the avatars.
MODELS = {
    # Depth Anything V2 Small, Apache-2.0 (the Base and Large models are not).
    "depth_anything_v2_small.onnx": (
        "https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/"
        "4472b7362082ad9968fee890ca0f1e5aca36b93d/onnx/model.onnx",
        "afb6a5c28f3b6bf1618c6e43f02073ef9dfdc70e937502d51603e57b0a1df10c", 99_000_000),
    # MediaPipe's models, Apache-2.0.
    "selfie_multiclass_256x256.tflite": (
        "https://storage.googleapis.com/mediapipe-models/image_segmenter/"
        "selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite",
        "c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0", 16_371_837),
    "face_landmarker.task": (
        "https://storage.googleapis.com/mediapipe-models/face_landmarker/"
        "face_landmarker/float16/1/face_landmarker.task",
        "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff", 3_758_596),
}

# The face's points face.json keeps, by MediaPipe's face mesh index. "A" is
# the eye on the photo's left, "B" the other.
POINTS = {
    "mouthL": 78, "mouthR": 308, "chin": 152, "top": 10, "left": 234, "right": 454,
    "eyeAOuter": 33, "eyeAInner": 133, "eyeAUpper": 159, "eyeALower": 145,
    "eyeBOuter": 263, "eyeBInner": 362, "eyeBUpper": 386, "eyeBLower": 374,
}

MAX_SIDE = 768
DEPTH_SIDE = 518  # Depth Anything's training size; any multiple of 14 works

PACKAGES = {"numpy": "python-numpy", "PIL": "python-pillow",
            "onnxruntime": "python-onnxruntime-cpu", "mediapipe": "python-mediapipe"}


class Failure(Exception):
    pass


def say(**fields):
    print(json.dumps(fields), flush=True)


def check_packages():
    import importlib.util
    missing = [pkg for mod, pkg in PACKAGES.items() if importlib.util.find_spec(mod) is None]
    if missing:
        say(error="missing", packages=missing)
        sys.exit(2)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def ensure_models(folder):
    """Downloads the models that aren't there yet; returns their paths."""
    os.makedirs(folder, exist_ok=True)
    paths = {name: os.path.join(folder, name) for name in MODELS}
    todo = [n for n in MODELS if not os.path.exists(paths[n])]
    total = sum(MODELS[n][2] for n in todo) or 1
    done = 0
    for name in todo:
        url, digest, _ = MODELS[name]
        tmp = paths[name] + ".part"
        say(step="download", progress=done / total)
        last = 0.0
        try:
            with urllib.request.urlopen(url, timeout=60) as r, open(tmp, "wb") as f:
                while True:
                    block = r.read(1 << 16)
                    if not block:
                        break
                    f.write(block)
                    done += len(block)
                    if done / total - last >= 0.01:
                        last = done / total
                        say(step="download", progress=min(1.0, last))
        except OSError as e:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise Failure(f"Couldn't download {name}: {e}")
        if sha256(tmp) != digest:
            os.remove(tmp)
            raise Failure(f"{name} didn't download right (its checksum differs); try again.")
        os.replace(tmp, paths[name])
    return paths


def load_photo(path):
    from PIL import Image, ImageOps
    try:
        img = Image.open(path)
        img = ImageOps.exif_transpose(img).convert("RGB")
    except (OSError, ValueError) as e:
        raise Failure(f"Can't read the photo: {e}")
    scale = MAX_SIDE / max(img.size)
    if scale < 1:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    return img


def person_mask(img, model):
    """0..1 per pixel: anything but the background (hair, skin, clothes)."""
    import mediapipe as mp
    import numpy as np
    from mediapipe.tasks.python import BaseOptions, vision
    options = vision.ImageSegmenterOptions(
        base_options=BaseOptions(model_asset_path=model), output_confidence_masks=True)
    with vision.ImageSegmenter.create_from_options(options) as seg:
        result = seg.segment(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.asarray(img)))
    background = np.asarray(result.confidence_masks[0].numpy_view(), dtype=np.float32)
    # MediaPipe 1.x answers (h, w, 1); Pillow takes only (h, w) floats.
    if background.ndim == 3:
        background = background[..., 0]
    mask = np.clip(1.0 - background, 0.0, 1.0)
    if mask.shape != (img.height, img.width):
        from PIL import Image
        mask = np.asarray(Image.fromarray(mask).resize(img.size, Image.BILINEAR))
    return mask


def face_points(img, model):
    """The biggest face's points, in pixels."""
    import mediapipe as mp
    import numpy as np
    from mediapipe.tasks.python import BaseOptions, vision
    options = vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model), num_faces=4)
    with vision.FaceLandmarker.create_from_options(options) as lm:
        result = lm.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.asarray(img)))
    if not result.face_landmarks:
        raise Failure("No face found in the photo. Try one where the face is clear and from the front.")

    def area(face):
        xs = [p.x for p in face]
        ys = [p.y for p in face]
        return (max(xs) - min(xs)) * (max(ys) - min(ys))
    face = max(result.face_landmarks, key=area)
    return {name: [round(face[i].x * img.width, 2), round(face[i].y * img.height, 2)]
            for name, i in POINTS.items()}


def raw_depth(img, model):
    """Depth Anything's answer at the photo's size: bigger is nearer."""
    import numpy as np
    import onnxruntime as ort
    from PIL import Image
    scale = DEPTH_SIDE / max(img.size)
    w = max(14, round(img.width * scale / 14) * 14)
    h = max(14, round(img.height * scale / 14) * 14)
    x = np.asarray(img.resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    x = x.transpose(2, 0, 1)[None].astype(np.float32)
    session = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
    d = session.run(None, {"pixel_values": x})[0][0].astype(np.float32)
    return np.asarray(Image.fromarray(d).resize(img.size, Image.BICUBIC))


def depth_map(d, mask):
    """0 far .. 1 near, stretched over the person; 0 outside it."""
    import numpy as np
    from PIL import Image, ImageFilter
    inside = d[mask > 0.5]
    if inside.size == 0:
        raise Failure("No person found in the photo.")
    lo, hi = np.percentile(inside, 1), np.percentile(inside, 99.5)
    d = np.clip((d - lo) / max(hi - lo, 1e-6), 0.0, 1.0) * np.clip(mask * 1.5, 0.0, 1.0)
    out = Image.fromarray((d * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
    return out


def write(out, img, mask, depth, points):
    """Everything into <out>.tmp, then put in <out>'s place."""
    import numpy as np
    from PIL import Image
    tmp, old = out + ".tmp", out + ".old"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    rgba = img.copy()
    rgba.putalpha(Image.fromarray((mask * 255).astype(np.uint8)))
    rgba.save(os.path.join(tmp, "color.png"))
    depth.save(os.path.join(tmp, "depth.png"))
    img.save(os.path.join(tmp, "source.jpg"), quality=90)
    with open(os.path.join(tmp, "face.json"), "w") as f:
        json.dump({"size": [img.width, img.height], "points": points}, f, indent=1)
    shutil.rmtree(old, ignore_errors=True)
    if os.path.exists(out):
        os.replace(out, old)
    os.replace(tmp, out)
    shutil.rmtree(old, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--photo", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--models", required=True)
    args = ap.parse_args()
    check_packages()
    try:
        models = ensure_models(args.models)
        say(step="load")
        img = load_photo(args.photo)
        # Depth first: python-mediapipe brings TensorFlow, and ONNX Runtime
        # loaded after it aborts the process (two protobufs disagree:
        # "Check failed: VerifyHasBitConsistency"). Loaded before, both run.
        say(step="depth")
        depth = raw_depth(img, models["depth_anything_v2_small.onnx"])
        say(step="mask")
        mask = person_mask(img, models["selfie_multiclass_256x256.tflite"])
        say(step="face")
        points = face_points(img, models["face_landmarker.task"])
        depth = depth_map(depth, mask)
        say(step="write")
        write(os.path.abspath(args.out), img, mask, depth, points)
    except Failure as e:
        say(error=str(e))
        sys.exit(1)
    except Exception as e:  # noqa: BLE001 - whatever breaks, the settings say it
        say(error=f"{type(e).__name__}: {e}")
        sys.exit(1)
    say(done=True)


if __name__ == "__main__":
    main()
