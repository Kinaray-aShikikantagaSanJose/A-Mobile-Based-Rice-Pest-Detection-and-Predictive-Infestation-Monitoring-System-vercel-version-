import unittest
from types import TracebackType
from unittest.mock import patch

from app import storage


class _Response:
    def read(self) -> bytes:
        return b"stored image"

    def __enter__(self) -> "_Response":
        return self

    def __exit__(
        self,
        _exc_type: type[BaseException] | None,
        _exc_value: BaseException | None,
        _traceback: TracebackType | None,
    ) -> bool:
        return False


class StorageAuthTests(unittest.TestCase):
    def test_secret_key_authenticates_bucket_operations_with_apikey_only(self):
        with (
            patch.multiple(
                storage,
                SUPABASE_URL="https://project.supabase.co",
                SUPABASE_SECRET_KEY="sb_secret_unit_test",
                SUPABASE_SERVICE_ROLE_KEY="",
                SUPABASE_KEY="sb_secret_unit_test",
            ),
            patch.object(storage.urllib.request, "urlopen", return_value=_Response()) as urlopen,
        ):
            for bucket in (storage.SCANS, storage.AVATARS):
                storage.put(bucket, "photo.jpg", b"upload")
                self.assertEqual(storage.get(bucket, "photo.jpg"), b"stored image")
                storage.delete(bucket, "photo.jpg")

        requests = [call.args[0] for call in urlopen.call_args_list]
        self.assertEqual(
            [request.get_method() for request in requests],
            ["POST", "GET", "DELETE", "POST", "GET", "DELETE"],
        )
        self.assertEqual(
            ["/scans/photo.jpg", "/scans/photo.jpg", "/scans/photo.jpg",
             "/avatars/photo.jpg", "/avatars/photo.jpg", "/avatars/photo.jpg"],
            [request.full_url.removeprefix("https://project.supabase.co/storage/v1/object")
             for request in requests],
        )
        for request in requests:
            self.assertEqual(request.get_header("Apikey"), "sb_secret_unit_test")
            self.assertIsNone(request.get_header("Authorization"))

    def test_legacy_service_role_key_remains_supported(self):
        with (
            patch.multiple(
                storage,
                SUPABASE_URL="https://project.supabase.co",
                SUPABASE_SECRET_KEY="",
                SUPABASE_SERVICE_ROLE_KEY="legacy-service-role-test",
                SUPABASE_KEY="legacy-service-role-test",
            ),
            patch.object(storage.urllib.request, "urlopen", return_value=_Response()) as urlopen,
        ):
            self.assertEqual(storage.get(storage.SCANS, "photo.jpg"), b"stored image")

        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_header("Apikey"), "legacy-service-role-test")
        self.assertEqual(request.get_header("Authorization"), "Bearer legacy-service-role-test")


if __name__ == "__main__":
    unittest.main()
