import json
import os
import socket
import unittest

os.environ["DISCOVERY_PORT"] = "18001"

from app import discovery


class DiscoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.started = discovery.start(api_port=8443, scheme="https")

    def _ask(self, message: bytes):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(1.0)
            sock.sendto(message, ("127.0.0.1", discovery.DISCOVERY_PORT))
            try:
                return sock.recvfrom(512)[0]
            except socket.timeout:
                return None

    def test_answers_with_service_port_and_scheme(self):
        self.assertTrue(self.started)
        reply = json.loads(self._ask(discovery.DISCOVERY_REQUEST))
        self.assertEqual(reply, {"service": "palay-patrol", "port": 8443, "scheme": "https"})

    def test_ignores_other_traffic(self):
        self.assertIsNone(self._ask(b"hello"))

    def test_second_start_is_a_no_op(self):
        self.assertFalse(discovery.start(api_port=1, scheme="http"))


if __name__ == "__main__":
    unittest.main()
