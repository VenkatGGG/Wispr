from __future__ import annotations

import unittest

from wispr.http_utils import build_multipart_form_data, decode_json_or_text


class HttpUtilsTests(unittest.TestCase):
    def test_build_multipart_form_data_contains_fields_and_file(self) -> None:
        body, content_type = build_multipart_form_data(
            fields={"language": "en"},
            file_field_name="file",
            filename="dictation.wav",
            file_bytes=b"abc123",
            content_type="audio/wav",
        )

        self.assertIn("multipart/form-data; boundary=", content_type)
        self.assertIn(b'name="language"', body)
        self.assertIn(b'dictation.wav', body)
        self.assertIn(b"abc123", body)
        self.assertTrue(body.endswith(b"--\r\n"))

    def test_decode_json_or_text_handles_json_and_plain_text(self) -> None:
        self.assertEqual(decode_json_or_text(b'{"text":"hello"}'), {"text": "hello"})
        self.assertEqual(decode_json_or_text(b"hello"), "hello")


if __name__ == "__main__":
    unittest.main()
