import boa

from conftest import DAY, WAD, amount


STATUS_ACTIVE = 2
STATUS_DELINQUENT = 3
STATUS_DEFAULTED = 4


def test_lender_deposit_open_line_and_drawdown(deployment, funded_line):
    token = deployment.token
    core = deployment.core
    accounts = deployment.accounts

    borrower_before = token.balanceOf(accounts.borrower)

    with boa.env.prank(accounts.borrower):
        core.draw(funded_line, amount(80_000))

    summary = core.get_line_summary(funded_line)

    assert summary[0] == accounts.borrower
    assert summary[1] == STATUS_ACTIVE
    assert summary[2] == amount(200_000)
    assert summary[3] == amount(80_000)
    assert summary[5] == amount(4_000)
    assert token.balanceOf(accounts.borrower) == borrower_before + amount(80_000)
    assert core.total_principal() == amount(80_000)
    assert core.quote_available(funded_line) == amount(120_000)


def test_interest_checkpoint_sets_cycle_obligation(deployment, funded_line):
    core = deployment.core
    accounts = deployment.accounts

    with boa.env.prank(accounts.borrower):
        core.draw(funded_line, amount(100_000))

    boa.env.time_travel(seconds=29 * DAY)

    pending_interest = core.quote_interest(funded_line)
    assert pending_interest > amount(950)
    assert pending_interest < amount(960)

    with boa.env.prank(accounts.keeper):
        core.checkpoint(funded_line)

    summary = core.get_line_summary(funded_line)
    assert summary[1] == STATUS_ACTIVE
    assert summary[4] == pending_interest
    assert summary[5] == amount(5_000)
    assert summary[7] > boa.env.timestamp


def test_repayment_reduces_interest_then_principal(deployment, funded_line):
    core = deployment.core
    accounts = deployment.accounts

    with boa.env.prank(accounts.borrower):
        core.draw(funded_line, amount(90_000))

    boa.env.time_travel(seconds=20 * DAY)

    with boa.env.prank(accounts.keeper):
        core.sync_line(funded_line)

    interest_before = core.quote_interest(funded_line)
    principal_before = core.get_line_summary(funded_line)[3]
    assert interest_before > 0

    with boa.env.prank(accounts.borrower):
        core.repay(funded_line, interest_before + amount(5_000))

    summary = core.get_line_summary(funded_line)
    assert summary[3] == principal_before - amount(5_000)
    assert summary[4] == 0
    assert core.total_interest_paid() == interest_before
    assert core.total_principal_paid() == amount(5_000)


def test_checkpoint_marks_default_after_missed_payment(deployment, funded_line):
    core = deployment.core
    accounts = deployment.accounts

    with boa.env.prank(accounts.borrower):
        core.draw(funded_line, amount(75_000))

    boa.env.time_travel(seconds=36 * DAY)

    with boa.env.prank(accounts.keeper):
        core.checkpoint(funded_line)

    summary = core.get_line_summary(funded_line)
    assert summary[1] == STATUS_DEFAULTED
    assert core.can_liquidate(funded_line)
    assert core.defaulted_line_count() == 1
    assert core.total_defaulted_debt() == core.quote_debt(funded_line)


def test_liquidation_seizes_collateral_and_reduces_debt(deployment, funded_line):
    token = deployment.token
    core = deployment.core
    accounts = deployment.accounts

    with boa.env.prank(accounts.borrower):
        core.draw(funded_line, amount(75_000))

    boa.env.time_travel(seconds=36 * DAY)

    with boa.env.prank(accounts.keeper):
        core.checkpoint(funded_line)

    liquidator_before = token.balanceOf(accounts.liquidator)
    debt_before = core.quote_debt(funded_line)
    collateral_before = core.get_line_summary(funded_line)[8]
    repay_amount, seize_amount = core.quote_liquidation(funded_line, amount(20_000))

    with boa.env.prank(accounts.liquidator):
        core.liquidate(funded_line, repay_amount)

    summary = core.get_line_summary(funded_line)

    assert repay_amount == amount(20_000)
    assert seize_amount == amount(21_000)
    assert token.balanceOf(accounts.liquidator) == liquidator_before - repay_amount + seize_amount
    assert summary[8] == collateral_before - seize_amount
    assert core.quote_debt(funded_line) < debt_before
    assert core.total_liquidated_collateral() == seize_amount


def test_normal_minimum_payment_keeps_line_current(deployment, funded_line):
    core = deployment.core
    accounts = deployment.accounts

    with boa.env.prank(accounts.borrower):
        core.draw(funded_line, amount(60_000))

    minimum = core.get_line_summary(funded_line)[5]
    assert minimum == amount(3_000)

    with boa.env.prank(accounts.borrower):
        core.repay(funded_line, minimum)

    summary = core.get_line_summary(funded_line)
    assert summary[1] == STATUS_ACTIVE
    assert summary[6] == 0
    assert core.is_current(funded_line)
