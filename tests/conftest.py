from dataclasses import dataclass
from pathlib import Path

import boa
import pytest


ROOT = Path(__file__).resolve().parents[1]
WAD = 10**18
DAY = 24 * 60 * 60
MAX_UINT = 2**256 - 1


def amount(units: int) -> int:
    return units * WAD


def tag(label: str) -> bytes:
    return label.encode("ascii").ljust(32, b"\x00")


@dataclass
class Accounts:
    owner: str
    underwriter: str
    treasury: str
    lender: str
    borrower: str
    liquidator: str
    keeper: str


@dataclass
class Deployment:
    token: object
    core: object
    accounts: Accounts


@pytest.fixture()
def deployment():
    with boa.env.anchor():
        accounts = Accounts(
            owner=boa.env.eoa,
            underwriter=boa.env.generate_address("underwriter"),
            treasury=boa.env.generate_address("treasury"),
            lender=boa.env.generate_address("lender"),
            borrower=boa.env.generate_address("borrower"),
            liquidator=boa.env.generate_address("liquidator"),
            keeper=boa.env.generate_address("keeper"),
        )

        token = boa.load(str(ROOT / "src" / "mocks" / "PyxisUSD.vy"), "Pyxis USD", "pUSD", 18)
        core = boa.load(
            str(ROOT / "src" / "core" / "PyxisCreditCore.vy"),
            token.address,
            accounts.treasury,
            accounts.underwriter,
        )

        token.mint(accounts.lender, amount(1_000_000))
        token.mint(accounts.borrower, amount(300_000))
        token.mint(accounts.liquidator, amount(500_000))
        token.mint(accounts.keeper, amount(100_000))

        for account in [
            accounts.lender,
            accounts.borrower,
            accounts.liquidator,
            accounts.keeper,
        ]:
            with boa.env.prank(account):
                token.approve(core.address, MAX_UINT)

        with boa.env.prank(accounts.underwriter):
            core.set_keeper(accounts.keeper, True)

        yield Deployment(token=token, core=core, accounts=accounts)


@pytest.fixture()
def funded_line(deployment):
    token = deployment.token
    core = deployment.core
    accounts = deployment.accounts

    with boa.env.prank(accounts.lender):
        core.deposit_liquidity(amount(600_000))

    with boa.env.prank(accounts.underwriter):
        line_id = core.open_line(
            accounts.borrower,
            amount(200_000),
            1_200,
            500,
            30 * DAY,
            5 * DAY,
            11_000,
            8_400,
            tag("SME-REVOLVER"),
        )

    with boa.env.prank(accounts.borrower):
        core.post_collateral(line_id, amount(60_000))

    return line_id
