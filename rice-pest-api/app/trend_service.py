"""Weekly pest-count trend prediction (ordinary least-squares line, numpy).

Same fit as scikit-learn's LinearRegression, without shipping scikit-learn
and SciPy (about 160 MB), which would push the Vercel function past its
250 MB size limit.

Consumes the same weekly history rows the /analytics/trends endpoint
already returns and produces a 4-week projection. Kept as a separate
service so the router and analytics_service stay untouched except for
one call site.
"""

from datetime import date, timedelta

import numpy as np

MIN_WEEKS_FOR_MODEL = 4  # below this, regression is noise -> naive fallback
PROJECTION_WEEKS = 4


def predict_weekly_pests(history, weeks_ahead=PROJECTION_WEEKS):
    """Project pest totals for the next `weeks_ahead` weeks.

    history: list of dicts, each with 'week' (ISO date string, e.g.
             '2026-01-05') and 'pests' (int), ordered oldest -> newest.
    Returns: list of dicts [{'week': 'YYYY-MM-DD', 'pests': int}, ...].
    Never raises on sparse data; falls back to the historical mean.
    """
    if not history:
        return []

    if not isinstance(weeks_ahead, int) or not 1 <= weeks_ahead <= 52:
        raise ValueError('weeks_ahead must be an integer from 1 to 52.')

    rows = []
    for row in history:
        try:
            week = date.fromisoformat(row['week'])
            pests = row['pests']
            observations = row.get('observations', 1)
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError('Each history row needs an ISO week, pest count, and optional observation count.') from exc
        if (
            isinstance(pests, bool)
            or not isinstance(pests, int)
            or pests < 0
            or isinstance(observations, bool)
            or not isinstance(observations, int)
            or observations < 0
        ):
            raise ValueError('Pest and observation counts must be non-negative integers.')
        rows.append((week, pests, observations))

    rows.sort(key=lambda row: row[0])
    if len({row[0] for row in rows}) != len(rows):
        raise ValueError('History must contain no more than one row per week.')
    last_week = rows[-1][0]
    observed = [(week, pests) for week, pests, count in rows if count > 0]
    if not observed:
        return []

    # Too little signal to fit a line: predict the average week instead.
    if len(observed) < MIN_WEEKS_FOR_MODEL:
        mean = round(sum(pests for _, pests in observed) / len(observed))
        return [
            {
                'week': (last_week + timedelta(weeks=i + 1)).isoformat(),
                'pests': mean,
            }
            for i in range(weeks_ahead)
        ]

    # Use real week offsets so missing report weeks don't compress the trend.
    origin = rows[0][0]
    x = np.array([(week - origin).days / 7 for week, _ in observed], dtype=float)
    y = np.array([pests for _, pests in observed], dtype=float)
    # Least squares, same result as LinearRegression().fit(x, y).
    x_mean, y_mean = x.mean(), y.mean()
    spread = float(((x - x_mean) ** 2).sum())
    slope = float(((x - x_mean) * (y - y_mean)).sum() / spread) if spread else 0.0
    intercept = float(y_mean - slope * x_mean)

    projection = []
    for i in range(1, weeks_ahead + 1):
        week = last_week + timedelta(weeks=i)
        predicted = intercept + slope * ((week - origin).days / 7)
        projection.append(
            {
                'week': week.isoformat(),
                'pests': max(0, round(predicted)),  # counts can't be negative
            }
        )
    return projection