import json
import subprocess
import sys
from pathlib import Path

import pytest

from src.operations.portfolio import summarize


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture()
def snapshot():
    return json.loads((ROOT / "examples" / "portfolio.json").read_text(encoding="utf-8"))


def test_sector_and_portfolio_reconciliation(snapshot):
    result = summarize(snapshot)
    assert result.line_count == 3
    assert result.active_line_count == 2
    assert result.commitment == 350_000
    assert result.principal == 150_000
    assert result.interest == 2_000
    assert result.debt == sum(sector.debt for sector in result.sectors)
    assert result.collateral == sum(sector.collateral for sector in result.sectors)
    assert result.utilization_bps == 2_500
    assert result.weighted_apr_bps == 1_266
    assert result.liquid_cash == 568_000


def test_stress_uses_sector_debt_and_reserve_floor(snapshot):
    result = summarize(snapshot)
    assert result.stressed_loss == 8_104
    assert result.stressed_reserve_after_loss == 11_896
    snapshot["sector_stress_bps"] = {"trade": 9_000, "services": 9_000}
    assert summarize(snapshot).stressed_reserve_after_loss == 0


def test_overdue_is_observational_only(snapshot):
    result = summarize(snapshot)
    assert result.overdue_line_count == 1
    snapshot["as_of"] = 1_750_000_000
    assert summarize(snapshot).overdue_line_count == 0


@pytest.mark.parametrize(
    "field,value",
    [("principal", 300_000), ("apr_bps", 10_001), ("line_id", 0), ("collateral", -1)],
)
def test_rejects_invalid_line_values(snapshot, field, value):
    snapshot["lines"][0][field] = value
    with pytest.raises(ValueError):
        summarize(snapshot)


def test_rejects_duplicate_line_ids(snapshot):
    snapshot["lines"][1]["line_id"] = snapshot["lines"][0]["line_id"]
    with pytest.raises(ValueError, match="duplicate"):
        summarize(snapshot)


def test_rejects_unbacked_segregated_assets(snapshot):
    snapshot["cash"] = 10_000
    with pytest.raises(ValueError):
        summarize(snapshot)


def test_empty_portfolio_has_no_division_error(snapshot):
    snapshot["lines"] = []
    result = summarize(snapshot)
    assert result.debt == 0
    assert result.weighted_apr_bps == 0
    assert result.collateral_coverage_bps == 0


def test_cli_returns_structured_report():
    completed = subprocess.run(
        [sys.executable, str(ROOT / "src" / "operations" / "portfolio.py"),
         str(ROOT / "examples" / "portfolio.json")],
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(completed.stdout)
    assert report["debt"] == 152_000
    assert [sector["sector"] for sector in report["sectors"]] == ["services", "trade"]
