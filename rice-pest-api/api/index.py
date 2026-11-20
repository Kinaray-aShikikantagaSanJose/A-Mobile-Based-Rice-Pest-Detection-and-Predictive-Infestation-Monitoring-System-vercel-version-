"""Vercel entry point: Vercel's Python runtime serves the ASGI `app` found here.

vercel.json sends every path (/auth/..., /sync/..., /docs, ...) to this
function, so the API keeps the same URLs it has when run with run_server.py.
"""
import os
import sys

# Make the project root importable so `app` resolves as a package.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.main import app  # noqa: E402,F401
