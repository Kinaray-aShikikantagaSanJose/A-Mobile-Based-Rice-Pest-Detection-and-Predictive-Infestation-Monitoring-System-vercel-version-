import os
import unittest
import asyncio
import json

os.environ["JWT_SECRET_KEY"] = "unit-test-key-that-is-never-used-outside-tests"
os.environ["APP_ENV"] = "production"
os.environ["HTTPS_ONLY"] = "true"

from fastapi import Request, Response

from app.main import app
from app.main import transport_security_headers
from app.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    decode_refresh_token,
    hash_password,
    verify_password,
)
from app.trend_service import predict_weekly_pests


class SecurityTests(unittest.TestCase):
    def test_bcrypt_hash_and_verification(self):
        password = "FieldPass#2026"
        encoded = hash_password(password)
        self.assertTrue(encoded.startswith("$2"))
        self.assertNotEqual(encoded, hash_password(password))
        self.assertTrue(verify_password(password, encoded))
        self.assertFalse(verify_password("wrong", encoded))

    def test_bcrypt_rejects_passwords_over_72_utf8_bytes(self):
        too_long = "é" * 37
        with self.assertRaises(ValueError):
            hash_password(too_long)
        self.assertFalse(verify_password(too_long, "$2b$12$invalid"))

    def test_access_and_refresh_tokens_are_type_separated(self):
        access = create_access_token("tech@example.test", "technician")
        refresh = create_refresh_token("tech@example.test")
        self.assertEqual(decode_access_token(access)["role"], "technician")
        self.assertIsNone(decode_refresh_token(access))
        self.assertEqual(decode_refresh_token(refresh)["type"], "refresh")


class TrendPredictionTests(unittest.TestCase):
    def test_linear_regression_projects_increasing_counts(self):
        history = [
            {"week": "2026-01-05", "pests": 5, "observations": 1},
            {"week": "2026-01-12", "pests": 10, "observations": 1},
            {"week": "2026-01-19", "pests": 15, "observations": 1},
            {"week": "2026-01-26", "pests": 20, "observations": 1},
        ]
        self.assertEqual(
            predict_weekly_pests(history, 2),
            [
                {"week": "2026-02-02", "pests": 25},
                {"week": "2026-02-09", "pests": 30},
            ],
        )

    def test_sparse_observations_use_the_observed_week_mean(self):
        history = [
            {"week": "2026-01-05", "pests": 2, "observations": 1},
            {"week": "2026-01-12", "pests": 0, "observations": 0},
            {"week": "2026-01-19", "pests": 8, "observations": 1},
            {"week": "2026-01-26", "pests": 0, "observations": 0},
        ]
        result = predict_weekly_pests(history, 1)
        self.assertEqual(result, [{"week": "2026-02-02", "pests": 5}])

    def test_no_observed_counts_produces_no_forecast(self):
        self.assertEqual(
            predict_weekly_pests([{"week": "2026-01-05", "pests": 0, "observations": 0}]),
            [],
        )

    def test_invalid_horizon_is_rejected(self):
        with self.assertRaises(ValueError):
            predict_weekly_pests([{"week": "2026-01-05", "pests": 1}], 0)


class TransportSecurityTests(unittest.TestCase):
    def _request(self, scheme):
        request = Request(
            {
                "type": "http",
                "asgi": {"version": "3.0", "spec_version": "2.3"},
                "http_version": "1.1",
                "method": "GET",
                "scheme": scheme,
                "path": "/",
                "raw_path": b"/",
                "query_string": b"",
                "root_path": "",
                "headers": [],
                "client": ("127.0.0.1", 12345),
                "server": ("testserver", 443 if scheme == "https" else 80),
            }
        )

        async def call_next(_request):
            return Response("ok")

        return asyncio.run(transport_security_headers(request, call_next))

    def test_production_rejects_plain_http(self):
        response = self._request("http")
        self.assertEqual(response.status_code, 426)
        self.assertIn("HTTPS is required", json.loads(response.body)["detail"])

    def test_https_responses_include_security_headers(self):
        response = self._request("https")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.headers["strict-transport-security"],
            "max-age=31536000; includeSubDomains",
        )
        self.assertEqual(response.headers["x-content-type-options"], "nosniff")
        self.assertEqual(response.headers["x-frame-options"], "DENY")


if __name__ == "__main__":
    unittest.main()
