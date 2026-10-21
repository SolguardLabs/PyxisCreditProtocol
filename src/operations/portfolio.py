"""Deterministic, read-only portfolio calculations for exported Pyxis snapshots."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

BPS = 10_000
ACTIVE_STATUSES = {"open", "active", "delinquent"}
KNOWN_STATUSES = ACTIVE_STATUSES | {"defaulted", "liquidated", "closed"}


def _natural(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{field} must be a non-negative integer")
    return value


def _basis_points(value: Any, field: str) -> int:
    result = _natural(value, field)
    if result > BPS:
        raise ValueError(f"{field} must not exceed {BPS}")
    return result


@dataclass(frozen=True)
class LineSnapshot:
    line_id: int
    sector: str
    status: str
    limit: int
    principal: int
    interest: int
    collateral: int
    apr_bps: int
    next_due: int

    @classmethod
    def parse(cls, data: dict[str, Any]) -> LineSnapshot:
        line_id = _natural(data["line_id"], "line_id")
        if line_id == 0:
            raise ValueError("line_id must be positive")
        sector = data["sector"]
        status = data["status"]
        if not isinstance(sector, str) or not sector.strip():
            raise ValueError("sector must be non-empty")
        if status not in KNOWN_STATUSES:
            raise ValueError("unknown line status")
        limit = _natural(data["limit"], "limit")
        principal = _natural(data["principal"], "principal")
        interest = _natural(data["interest"], "interest")
        collateral = _natural(data["collateral"], "collateral")
        apr_bps = _basis_points(data["apr_bps"], "apr_bps")
        next_due = _natural(data["next_due"], "next_due")
        if principal > limit:
            raise ValueError("principal exceeds approved limit")
        if status in {"closed", "liquidated"} and principal + interest != 0:
            raise ValueError("terminal line retains debt")
        return cls(line_id, sector, status, limit, principal, interest, collateral, apr_bps, next_due)

    @property
    def debt(self) -> int:
        return self.principal + self.interest


@dataclass(frozen=True)
class SectorSummary:
    sector: str
    line_count: int
    commitment: int
    principal: int
    debt: int
    collateral: int
    weighted_apr_bps: int
    stress_loss: int


@dataclass(frozen=True)
class PortfolioSummary:
    as_of: int
    line_count: int
    active_line_count: int
    overdue_line_count: int
    commitment: int
    principal: int
    interest: int
    debt: int
    collateral: int
    liquid_cash: int
    utilization_bps: int
    collateral_coverage_bps: int
    weighted_apr_bps: int
    stressed_loss: int
    stressed_reserve_after_loss: int
    sectors: tuple[SectorSummary, ...]


def summarize(snapshot: dict[str, Any]) -> PortfolioSummary:
    as_of = _natural(snapshot["as_of"], "as_of")
    cash = _natural(snapshot["cash"], "cash")
    lender_principal = _natural(snapshot["lender_principal"], "lender_principal")
    reserve = _natural(snapshot["reserve"], "reserve")
    if reserve > cash:
        raise ValueError("reserve exceeds cash")
    stress = snapshot.get("sector_stress_bps", {})
    if not isinstance(stress, dict):
        raise ValueError("sector_stress_bps must be a mapping")
    for sector, haircut in stress.items():
        if not isinstance(sector, str) or not sector:
            raise ValueError("invalid sector key")
        _basis_points(haircut, f"sector_stress_bps.{sector}")
    raw_lines = snapshot["lines"]
    if not isinstance(raw_lines, list):
        raise ValueError("lines must be a list")
    lines = [LineSnapshot.parse(raw) for raw in raw_lines]
    if len({line.line_id for line in lines}) != len(lines):
        raise ValueError("duplicate line_id")

    collateral = sum(line.collateral for line in lines)
    if collateral + reserve > cash:
        raise ValueError("cash does not cover segregated collateral and reserve")
    active = [line for line in lines if line.status in ACTIVE_STATUSES]
    principal = sum(line.principal for line in lines)
    interest = sum(line.interest for line in lines)
    debt = principal + interest
    commitment = sum(line.limit for line in active)
    liquid_cash = cash - collateral - reserve
    if lender_principal and principal > lender_principal:
        raise ValueError("principal exceeds lender capital")

    sectors = []
    for sector in sorted({line.sector for line in lines}):
        sector_lines = [line for line in lines if line.sector == sector]
        sector_principal = sum(line.principal for line in sector_lines)
        sector_debt = sum(line.debt for line in sector_lines)
        sectors.append(
            SectorSummary(
                sector=sector,
                line_count=len(sector_lines),
                commitment=sum(line.limit for line in sector_lines if line in active),
                principal=sector_principal,
                debt=sector_debt,
                collateral=sum(line.collateral for line in sector_lines),
                weighted_apr_bps=(
                    sum(line.principal * line.apr_bps for line in sector_lines) // sector_principal
                    if sector_principal else 0
                ),
                stress_loss=sector_debt * stress.get(sector, 0) // BPS,
            )
        )
    stressed_loss = sum(item.stress_loss for item in sectors)
    return PortfolioSummary(
        as_of=as_of,
        line_count=len(lines),
        active_line_count=len(active),
        overdue_line_count=sum(1 for line in active if line.next_due < as_of),
        commitment=commitment,
        principal=principal,
        interest=interest,
        debt=debt,
        collateral=collateral,
        liquid_cash=liquid_cash,
        utilization_bps=principal * BPS // lender_principal if lender_principal else 0,
        collateral_coverage_bps=collateral * BPS // debt if debt else 0,
        weighted_apr_bps=(
            sum(line.principal * line.apr_bps for line in lines) // principal if principal else 0
        ),
        stressed_loss=stressed_loss,
        stressed_reserve_after_loss=max(0, reserve - stressed_loss),
        sectors=tuple(sectors),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize a local Pyxis credit snapshot")
    parser.add_argument("snapshot", type=Path, help="JSON export in base token units")
    args = parser.parse_args()
    result = summarize(json.loads(args.snapshot.read_text(encoding="utf-8")))
    print(json.dumps(asdict(result), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
