import json
import hashlib
import tempfile
import threading
import unittest
from dataclasses import replace
import urllib.error
import urllib.request
from pathlib import Path

from server import Config, PublicError, Service, make_server, validate_summary

TOKEN = "test-only-token-not-a-real-credential-123"
SUMMARY = {"plan": "threeK", "distance_m": 1_234.5, "duration_s": 800, "splits_s": [650], "effort": "right", "completed": False}


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.calls = []
        self.config = Config(TOKEN, Path(self.temp.name), "fake-speech-key", "eastus", "fake-ai-key", "https://example.invalid/v1", "fake-model")

    def upstream(self, url, headers, body, timeout):
        self.calls.append((url, headers, body, timeout))
        if "speech.microsoft.com" in url:
            return b"ID3-fake-test-audio", "audio/mpeg"
        return json.dumps({"choices": [{"message": {"content": "按舒服的节奏重复当前训练。"}}]}).encode(), "application/json"

    def test_voice_is_cached_without_second_provider_call(self):
        service = Service(self.config, self.upstream)
        request = {"text": "已完成一公里。", "voice": "zh-CN-XiaoxiaoNeural"}
        self.assertEqual(service.voice(request), service.voice(request))
        self.assertEqual(len(self.calls), 1)

    def test_ssml_text_is_escaped(self):
        Service(self.config, self.upstream).voice({"text": '<voice name="bad">&', "voice": "zh-CN-XiaoxiaoNeural"})
        self.assertIn(b"&lt;voice", self.calls[0][2])

    def test_no_voice_provider_without_configuration(self):
        with self.assertRaises(PublicError) as error:
            Service(Config(TOKEN, Path(self.temp.name)), self.upstream).voice({"text": "开始", "voice": "zh-CN-XiaoxiaoNeural"})
        self.assertEqual(error.exception.status, 503)
        self.assertEqual(self.calls, [])

    def test_invalid_voice_rejected_before_provider(self):
        for body in ({"text": "a" * 301, "voice": "zh-CN-XiaoxiaoNeural"}, {"text": "跑", "voice": "unknown"}, {"text": "", "voice": "zh-CN-XiaoxiaoNeural"}):
            with self.assertRaises(PublicError):
                Service(self.config, self.upstream).voice(body)
        self.assertEqual(self.calls, [])

    def test_wrongly_typed_voice_or_plan_rejected(self):
        with self.assertRaises(PublicError):
            Service(self.config, self.upstream).voice({"text": "开始", "voice": []})
        with self.assertRaises(PublicError):
            validate_summary({**SUMMARY, "plan": []})

    def test_pending_paid_audio_prevents_duplicate_call(self):
        text = "开始"
        voice = "zh-CN-XiaoxiaoNeural"
        digest = hashlib.sha256((voice + "\0" + text).encode()).hexdigest()
        (Path(self.temp.name) / (digest + ".pending")).write_bytes(b"preserved-audio")
        with self.assertRaises(PublicError) as error:
            Service(self.config, self.upstream).voice({"text": text, "voice": voice})
        self.assertEqual(error.exception.status, 503)
        self.assertEqual(self.calls, [])

    def test_analysis_does_not_send_coordinates(self):
        data, _ = Service(self.config, self.upstream).analysis(SUMMARY)
        self.assertIn("舒服", json.loads(data)["analysis"])
        payload = json.loads(self.calls[0][2])
        self.assertEqual(json.loads(payload["messages"][1]["content"]), SUMMARY)
        self.assertNotIn("latitude", self.calls[0][2].decode())

    def test_coordinates_are_rejected(self):
        with self.assertRaises(PublicError):
            validate_summary({**SUMMARY, "track": [{"latitude": 1}]})

    def test_deepseek_and_zhipu_short_review_requests(self):
        for base, model in (("https://api.deepseek.com", "deepseek-flash"),
                            ("https://open.bigmodel.cn/api/paas/v4/", "glm-5.3-flash")):
            with self.subTest(base=base):
                config = replace(self.config, ai_base_url=base, ai_model=model, ai_thinking="disabled")
                data, _ = Service(config, self.upstream).analysis(SUMMARY)
                url, _, body, _ = self.calls[-1]
                self.assertEqual(url, base.rstrip("/") + "/chat/completions")
                self.assertEqual(json.loads(body)["thinking"], {"type": "disabled"})
                self.assertTrue(json.loads(data)["analysis"])

    def test_generic_provider_does_not_receive_thinking_parameter(self):
        Service(self.config, self.upstream).analysis(SUMMARY)
        self.assertNotIn("thinking", json.loads(self.calls[0][2]))

    def test_invalid_thinking_setting_does_not_call_provider(self):
        with self.assertRaises(PublicError):
            Service(replace(self.config, ai_thinking="bad"), self.upstream).analysis(SUMMARY)
        self.assertEqual(self.calls, [])

    def test_nonfinite_and_boolean_numbers_are_rejected(self):
        for value in (float("nan"), float("inf"), -1, True):
            with self.assertRaises(PublicError):
                validate_summary({**SUMMARY, "distance_m": value})

    def test_split_limits_are_checked(self):
        for splits in ([0], [True], [1] * 101, "bad"):
            with self.assertRaises(PublicError):
                validate_summary({**SUMMARY, "splits_s": splits})

    def test_quota_error_not_retried_and_no_audio_is_cached(self):
        calls = []
        def fail(*args):
            calls.append(args)
            raise PublicError(429, "Provider rate or quota limit; not retried")
        with self.assertRaises(PublicError) as error:
            Service(self.config, fail).voice({"text": "开始", "voice": "zh-CN-XiaoxiaoNeural"})
        self.assertEqual(error.exception.status, 429)
        self.assertEqual(len(calls), 1)
        self.assertEqual(list(Path(self.temp.name).glob("*.mp3")), [])

    def test_invalid_audio_not_cached(self):
        with self.assertRaises(PublicError):
            Service(self.config, lambda *args: (b"not audio", "application/json")).voice({"text": "开始", "voice": "zh-CN-XiaoxiaoNeural"})

    def test_empty_model_text_is_reported_as_failure(self):
        service = Service(self.config, lambda *args: (b'{"choices":[{"message":{"content":null}}]}', "application/json"))
        with self.assertRaises(PublicError) as error:
            service.analysis(SUMMARY)
        self.assertEqual(error.exception.status, 502)


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.server = make_server(Config(TOKEN, Path(self.temp.name)), port=0,
                                  upstream=lambda *args: self.fail("Unexpected provider request"))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temp.cleanup()

    def request(self, path, body=None, token=TOKEN, content_type="application/json"):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=data, headers={"Authorization": "Bearer " + token, "Content-Type": content_type})
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.read()

    def test_health_has_no_secret_values(self):
        status, body = self.request("/health")
        self.assertEqual(status, 200)
        self.assertNotIn(TOKEN.encode(), body)
        self.assertFalse(json.loads(body)["speech_configured"])

    def test_bad_token_rejected(self):
        self.assertEqual(self.request("/v1/analysis", SUMMARY, token="wrong")[0], 401)

    def test_unconfigured_ai_returns_503(self):
        self.assertEqual(self.request("/v1/analysis", SUMMARY)[0], 503)

    def test_route_payload_rejected_over_http(self):
        self.assertEqual(self.request("/v1/analysis", {**SUMMARY, "longitude": 1})[0], 422)

    def test_bad_content_type_rejected(self):
        self.assertEqual(self.request("/v1/analysis", SUMMARY, content_type="text/plain")[0], 415)

    def test_oversized_request_rejected(self):
        self.assertEqual(self.request("/v1/analysis", {"text": "a" * 20_000})[0], 413)

    def test_unknown_path_is_404(self):
        self.assertEqual(self.request("/no-such-path")[0], 404)

    def test_json_list_is_not_accepted(self):
        self.assertEqual(self.request("/v1/analysis", [1, 2])[0], 422)


if __name__ == "__main__":
    unittest.main()
