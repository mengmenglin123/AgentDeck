from __future__ import annotations

import base64
import os
import tempfile
import unittest

import uploads


class TestUploads(unittest.TestCase):
    def test_saves_inside_workdir_and_annotates(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            msg = {"images": [{"name": "../../evil shot.png", "mime": "image/png", "data_base64": base64.b64encode(b"png").decode()}],
                   "files": [{"name": "", "mime": "text/plain", "data_base64": base64.b64encode("日志".encode()).decode()}]}
            self.assertTrue(uploads.has_attachments(msg))
            paths = uploads.save(root, msg, clock=lambda: 0)
            self.assertEqual(len(paths), 2)
            for p in paths:
                self.assertTrue(p.startswith(".huanhermes/uploads/"))
                self.assertTrue(os.path.isfile(os.path.join(root, p)))
            self.assertIn("evil_shot.png", paths[0])
            self.assertTrue(paths[1].endswith("attachment-2.txt"))
            self.assertTrue(os.path.isfile(os.path.join(root, ".huanhermes/uploads/.gitignore")))
            text = uploads.annotate("看看这个", paths)
            self.assertIn(paths[0], text)
            self.assertNotIn("\n", text)
            self.assertTrue(uploads.annotate("", paths).startswith("[附件"))

    def test_rejects_bad_input(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(uploads.UploadError):
                uploads.save(root, {"files": [{"data_base64": "!!notbase64"}]})
            big = base64.b64encode(b"x" * (uploads.MAX_ITEM_BYTES + 1)).decode()
            with self.assertRaises(uploads.UploadError):
                uploads.save(root, {"files": [{"data_base64": big}]})
            self.assertEqual(uploads.save(root, {"images": []}), [])


if __name__ == "__main__":
    unittest.main()
