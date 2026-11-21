import os
import unittest
from collections.abc import Callable
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")

from sqlalchemy.pool import NullPool

from app import database


class DatabaseConnectionConfigTests(unittest.TestCase):
    def _make_engine(
        self, serverless: bool
    ) -> tuple[object, dict[str, object], list[tuple[str, Callable[..., object]]]]:
        listeners: list[tuple[str, Callable[..., object]]] = []

        def register_listener(
            _engine: object, event_name: str
        ) -> Callable[[Callable[..., object]], Callable[..., object]]:
            def register(callback: Callable[..., object]) -> Callable[..., object]:
                listeners.append((event_name, callback))
                return callback

            return register

        with (
            patch.object(database, "SERVERLESS", serverless),
            patch.object(database, "create_engine", return_value=object()) as create_engine,
            patch.object(database.event, "listens_for", side_effect=register_listener),
        ):
            engine = database._make_engine(
                "postgresql://postgres:password@project.supabase.co:6543/postgres"
            )

        options = dict(create_engine.call_args.kwargs)
        return engine, options, listeners

    def test_serverless_uses_null_pool_without_session_timezone_set(self):
        _, options, listeners = self._make_engine(serverless=True)

        self.assertIs(options["poolclass"], NullPool)
        self.assertFalse(options["pool_pre_ping"])
        self.assertEqual(listeners, [])

    def test_direct_connection_sets_timezone_per_connection(self):
        _, options, listeners = self._make_engine(serverless=False)

        self.assertNotIn("poolclass", options)
        self.assertTrue(options["pool_pre_ping"])
        self.assertEqual(len(listeners), 1)

        class Cursor:
            def __init__(self):
                self.statement: str | None = None
                self.parameters: tuple[str, ...] | None = None

            def execute(self, statement: str, parameters: tuple[str, ...]) -> None:
                self.statement = statement
                self.parameters = parameters

            def close(self) -> None:
                pass

        class Connection:
            def __init__(self):
                self.created_cursor = Cursor()
                self.committed = False

            def cursor(self) -> Cursor:
                return self.created_cursor

            def commit(self) -> None:
                self.committed = True

        connection = Connection()
        listeners[0][1](connection, None)

        self.assertEqual(connection.created_cursor.statement, "SET TIME ZONE %s")
        self.assertEqual(connection.created_cursor.parameters, (database.APP_TIMEZONE,))
        self.assertTrue(connection.committed)


if __name__ == "__main__":
    unittest.main()
