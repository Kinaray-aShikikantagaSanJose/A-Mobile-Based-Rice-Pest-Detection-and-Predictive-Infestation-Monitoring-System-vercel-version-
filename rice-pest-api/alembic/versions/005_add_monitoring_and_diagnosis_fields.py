"""add monitoring method, target pest/sex, and diagnosis columns

Revision ID: 005
Revises: 004
Create Date: 2026-09-18

Closes the gap between the mobile SQLite schema (v7) and the server:
the app already captures monitoring_method / target_pest / target_sex
(flow step 5) and the technician diagnosis / referral reason (T-034),
but the server had no columns to store them.

NOTE: before running, open 004_add_analytics_views.py and make sure
`down_revision` below equals the exact `revision` string declared there
(if it is a hex id rather than "004", paste it here).

Raw-SQL fallback (if you apply schema changes manually instead of
Alembic, e.g. inside the docker-compose PostGIS container):

    ALTER TABLE scans ADD COLUMN IF NOT EXISTS monitoring_method TEXT NOT NULL DEFAULT '';
    ALTER TABLE scans ADD COLUMN IF NOT EXISTS target_pest      TEXT NOT NULL DEFAULT '';
    ALTER TABLE scans ADD COLUMN IF NOT EXISTS target_sex       TEXT NOT NULL DEFAULT '';
    ALTER TABLE scans ADD COLUMN IF NOT EXISTS diagnosis        TEXT NOT NULL DEFAULT '';
"""
from alembic import op
import sqlalchemy as sa

revision = "005"
down_revision = "004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "scans",
        sa.Column("monitoring_method", sa.Text(), nullable=False, server_default=""),
    )
    op.add_column(
        "scans",
        sa.Column("target_pest", sa.Text(), nullable=False, server_default=""),
    )
    op.add_column(
        "scans",
        sa.Column("target_sex", sa.Text(), nullable=False, server_default=""),
    )
    op.add_column(
        "scans",
        sa.Column("diagnosis", sa.Text(), nullable=False, server_default=""),
    )


def downgrade() -> None:
    op.drop_column("scans", "diagnosis")
    op.drop_column("scans", "target_sex")
    op.drop_column("scans", "target_pest")
    op.drop_column("scans", "monitoring_method")