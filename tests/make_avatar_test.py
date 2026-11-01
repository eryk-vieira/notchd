"""Tests of core/avatar/make-avatar.py that need no models: MediaPipe is
faked, so only NumPy and Pillow must be there; without them every test is
skipped (`make test` runs this on any machine). The models' own work is
checked by hand (DEVELOPMENT.md, Avatars).
"""
import contextlib
import importlib.util
import io
import os
import sys
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "core", "avatar", "make-avatar.py")

try:
    import numpy as np
    from PIL import Image
    HAVE_DEPS = True
except ImportError:
    HAVE_DEPS = False


def load_script():
    spec = importlib.util.spec_from_file_location("make_avatar", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fake_mediapipe(background):
    """A mediapipe whose segmenter answers `background` as the background's
    confidence mask."""
    class Segmenter:
        @staticmethod
        def create_from_options(options):
            return Segmenter()

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def segment(self, image):
            mask = types.SimpleNamespace(numpy_view=lambda: background)
            return types.SimpleNamespace(confidence_masks=[mask])

    mp = types.ModuleType("mediapipe")
    mp.Image = lambda image_format, data: data
    mp.ImageFormat = types.SimpleNamespace(SRGB=1)
    tasks = types.ModuleType("mediapipe.tasks")
    python = types.ModuleType("mediapipe.tasks.python")
    python.BaseOptions = lambda **kw: kw
    python.vision = types.SimpleNamespace(ImageSegmenterOptions=lambda **kw: kw, ImageSegmenter=Segmenter)
    return {"mediapipe": mp, "mediapipe.tasks": tasks, "mediapipe.tasks.python": python}


@unittest.skipUnless(HAVE_DEPS, "needs numpy and pillow")
class PersonMask(unittest.TestCase):
    def mask_for(self, background, size=(40, 30)):
        saved = {k: sys.modules.get(k) for k in ("mediapipe", "mediapipe.tasks", "mediapipe.tasks.python")}
        sys.modules.update(fake_mediapipe(background))
        try:
            img = Image.new("RGB", size)
            return load_script().person_mask(img, "model.tflite")
        finally:
            for k, v in saved.items():
                if v is None:
                    sys.modules.pop(k, None)
                else:
                    sys.modules[k] = v

    # Bug guarded: MediaPipe 1.x answers (h, w, 1) masks; Pillow can't
    # resize one ("Cannot handle this data type: (1, 1, 1), <f4").
    def test_a_mask_with_a_channel_axis(self):
        background = np.zeros((30, 40, 1), np.float32)
        background[:, :10] = 1.0
        mask = self.mask_for(background)
        self.assertEqual(mask.shape, (30, 40))
        self.assertEqual(float(mask[0, 0]), 0.0)
        self.assertEqual(float(mask[0, 20]), 1.0)

    def test_a_flat_mask(self):
        mask = self.mask_for(np.full((30, 40), 0.25, np.float32))
        self.assertEqual(mask.shape, (30, 40))
        self.assertAlmostEqual(float(mask.mean()), 0.75, places=5)

    def test_a_mask_of_another_size_is_resized_to_the_photo(self):
        mask = self.mask_for(np.zeros((256, 256, 1), np.float32))
        self.assertEqual(mask.shape, (30, 40))
        self.assertAlmostEqual(float(mask.mean()), 1.0, places=5)


@unittest.skipUnless(HAVE_DEPS, "needs numpy and pillow")
class Order(unittest.TestCase):
    # Bug guarded: ONNX Runtime loaded after python-mediapipe (which brings
    # TensorFlow) aborts the process on a protobuf check; the depth must be
    # estimated before any MediaPipe step.
    def test_depth_before_mediapipe(self):
        script = load_script()
        calls = []
        img = Image.new("RGB", (8, 6))
        flat = np.ones((6, 8), np.float32)
        script.ensure_models = lambda folder: {n: n for n in script.MODELS}
        script.load_photo = lambda path: img
        script.raw_depth = lambda im, model: calls.append("depth") or flat
        script.person_mask = lambda im, model: calls.append("mask") or flat
        script.face_points = lambda im, model: calls.append("face") or {}
        script.depth_map = lambda d, mask: calls.append("normalize") or d
        script.write = lambda *a: calls.append("write")
        sys.argv = ["make-avatar.py", "--photo", "p.jpg", "--out", "o", "--models", "m"]
        script.check_packages = lambda: None
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            script.main()
        self.assertEqual(calls, ["depth", "mask", "face", "normalize", "write"])
        self.assertIn('{"done": true}', out.getvalue())


if __name__ == "__main__":
    unittest.main()
