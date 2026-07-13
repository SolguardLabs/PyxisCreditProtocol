# pragma version ^0.4.3

interface IPyxisCore:
    def quote_debt(line_id: uint256) -> uint256: view
    def quote_interest(line_id: uint256) -> uint256: view
    def quote_minimum_due(line_id: uint256) -> uint256: view
    def quote_available(line_id: uint256) -> uint256: view
    def quote_liquidation(line_id: uint256, repay_amount: uint256) -> (uint256, uint256): view
    def can_liquidate(line_id: uint256) -> bool: view
    def is_current(line_id: uint256) -> bool: view
    def get_line_summary(line_id: uint256) -> (address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256): view
    def get_lender_summary(account: address) -> (uint256, uint256, uint256, uint256, uint256, uint256, address, uint256): view
    def total_principal() -> uint256: view
    def total_accrued_interest() -> uint256: view
    def total_collateral() -> uint256: view
    def total_lender_principal() -> uint256: view
    def total_lender_shares() -> uint256: view
    def total_defaulted_debt() -> uint256: view
    def total_liquidated_collateral() -> uint256: view
    def total_reserve() -> uint256: view
    def open_line_count() -> uint256: view
    def active_line_count() -> uint256: view
    def defaulted_line_count() -> uint256: view
    def liquidated_line_count() -> uint256: view
    def line_count() -> uint256: view
    def borrower_line_count(borrower: address) -> uint256: view
    def line_owner_index(borrower: address, index: uint256) -> uint256: view
    def borrower_total_limit(borrower: address) -> uint256: view
    def borrower_total_principal(borrower: address) -> uint256: view
    def borrower_total_collateral(borrower: address) -> uint256: view

BPS: constant(uint256) = 10_000
STATUS_OPEN: constant(uint256) = 1
STATUS_ACTIVE: constant(uint256) = 2
STATUS_DELINQUENT: constant(uint256) = 3
STATUS_DEFAULTED: constant(uint256) = 4
STATUS_LIQUIDATED: constant(uint256) = 5
STATUS_CLOSED: constant(uint256) = 6
MAX_BATCH: constant(uint256) = 8

struct LineView:
    line_id: uint256
    borrower: address
    status: uint256
    limit: uint256
    principal: uint256
    interest: uint256
    debt: uint256
    minimum_due: uint256
    paid_since_checkpoint: uint256
    next_due: uint256
    collateral: uint256
    covenant_score: uint256
    available: uint256
    liquidatable: bool
    current: bool
    health_bps: uint256
    utilization_bps: uint256
    collateral_bps: uint256

struct BorrowerView:
    borrower: address
    line_count: uint256
    total_limit: uint256
    total_principal: uint256
    total_collateral: uint256
    aggregate_debt: uint256
    weighted_health_bps: uint256
    open_or_active: uint256
    delinquent_or_defaulted: uint256
    liquidatable_count: uint256
    next_due: uint256
    largest_line: uint256

struct LenderView:
    account: address
    shares: uint256
    principal_deposited: uint256
    principal_withdrawn: uint256
    interest_claimed: uint256
    reserve_claimed: uint256
    last_action_at: uint256
    delegate: address
    locked_until: uint256
    ownership_bps: uint256
    withdrawable_estimate: uint256

struct PortfolioView:
    total_lines: uint256
    open_lines: uint256
    active_lines: uint256
    defaulted_lines: uint256
    liquidated_lines: uint256
    total_lender_principal: uint256
    total_lender_shares: uint256
    total_principal: uint256
    total_interest: uint256
    total_collateral: uint256
    total_defaulted: uint256
    total_liquidated: uint256
    total_reserve: uint256
    utilization_bps: uint256
    reserve_bps: uint256
    collateralization_bps: uint256

event CoreChanged:
    old_core: indexed(address)
    new_core: indexed(address)

owner: public(address)
core: public(address)
name: public(String[32])
version: public(String[16])

@deploy
def __init__(_core: address):
    assert _core != empty(address), "CORE"
    self.owner = msg.sender
    self.core = _core
    self.name = "PyxisCreditLens"
    self.version = "1.0.0"

@internal
@view
def _line_health_bps(debt: uint256, collateral: uint256) -> uint256:
    if debt == 0:
        return max_value(uint256)
    return collateral * BPS // debt

@internal
@view
def _line_utilization_bps(principal: uint256, limit: uint256) -> uint256:
    if limit == 0:
        return 0
    if principal >= limit:
        return BPS
    return principal * BPS // limit

@internal
@view
def _line_collateral_bps(principal: uint256, collateral: uint256) -> uint256:
    if principal == 0:
        return max_value(uint256)
    return collateral * BPS // principal

@internal
@view
def _min_u256(a: uint256, b: uint256) -> uint256:
    if a < b:
        return a
    return b

@internal
@view
def _line_view(line_id: uint256) -> LineView:
    borrower: address = empty(address)
    status: uint256 = 0
    limit: uint256 = 0
    principal: uint256 = 0
    interest: uint256 = 0
    minimum_due: uint256 = 0
    paid_since_checkpoint: uint256 = 0
    next_due: uint256 = 0
    collateral: uint256 = 0
    covenant_score: uint256 = 0
    borrower, status, limit, principal, interest, minimum_due, paid_since_checkpoint, next_due, collateral, covenant_score = staticcall IPyxisCore(self.core).get_line_summary(line_id)
    debt: uint256 = staticcall IPyxisCore(self.core).quote_debt(line_id)
    available: uint256 = staticcall IPyxisCore(self.core).quote_available(line_id)
    liquidatable: bool = staticcall IPyxisCore(self.core).can_liquidate(line_id)
    current: bool = staticcall IPyxisCore(self.core).is_current(line_id)
    return LineView(
        line_id=line_id,
        borrower=borrower,
        status=status,
        limit=limit,
        principal=principal,
        interest=interest,
        debt=debt,
        minimum_due=minimum_due,
        paid_since_checkpoint=paid_since_checkpoint,
        next_due=next_due,
        collateral=collateral,
        covenant_score=covenant_score,
        available=available,
        liquidatable=liquidatable,
        current=current,
        health_bps=self._line_health_bps(debt, collateral),
        utilization_bps=self._line_utilization_bps(principal, limit),
        collateral_bps=self._line_collateral_bps(principal, collateral)
    )

@external
def transfer_owner(new_owner: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_owner != empty(address), "OWNER_ZERO"
    self.owner = new_owner

@external
def set_core(new_core: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_core != empty(address), "CORE"
    old_core: address = self.core
    self.core = new_core
    log CoreChanged(old_core=old_core, new_core=new_core)

@external
@view
def line_view(line_id: uint256) -> LineView:
    return self._line_view(line_id)

@external
@view
def line_debt_parts(line_id: uint256) -> (uint256, uint256, uint256):
    view: LineView = self._line_view(line_id)
    return view.principal, view.interest, view.debt

@external
@view
def line_calendar(line_id: uint256) -> (uint256, uint256, uint256, bool):
    view: LineView = self._line_view(line_id)
    overdue_seconds: uint256 = 0
    if block.timestamp > view.next_due:
        overdue_seconds = block.timestamp - view.next_due
    return view.next_due, overdue_seconds, view.minimum_due, view.current

@external
@view
def liquidation_quote(line_id: uint256, repay_amount: uint256) -> (uint256, uint256, uint256):
    amount: uint256 = 0
    seize: uint256 = 0
    amount, seize = staticcall IPyxisCore(self.core).quote_liquidation(line_id, repay_amount)
    debt: uint256 = staticcall IPyxisCore(self.core).quote_debt(line_id)
    remaining: uint256 = 0
    if debt > amount:
        remaining = debt - amount
    return amount, seize, remaining

@external
@view
def borrower_view(borrower: address) -> BorrowerView:
    count: uint256 = staticcall IPyxisCore(self.core).borrower_line_count(borrower)
    total_limit: uint256 = staticcall IPyxisCore(self.core).borrower_total_limit(borrower)
    total_principal: uint256 = staticcall IPyxisCore(self.core).borrower_total_principal(borrower)
    total_collateral: uint256 = staticcall IPyxisCore(self.core).borrower_total_collateral(borrower)
    aggregate_debt: uint256 = 0
    weighted_health: uint256 = 0
    open_or_active: uint256 = 0
    bad: uint256 = 0
    liquidatable_count: uint256 = 0
    next_due: uint256 = max_value(uint256)
    largest_line: uint256 = 0
    max_principal: uint256 = 0
    bounded: uint256 = self._min_u256(count, MAX_BATCH)
    for i: uint256 in range(MAX_BATCH):
        if i >= bounded:
            break
        line_id: uint256 = staticcall IPyxisCore(self.core).line_owner_index(borrower, i)
        if line_id == 0:
            continue
        view: LineView = self._line_view(line_id)
        aggregate_debt += view.debt
        if view.debt > 0 and view.health_bps < max_value(uint256):
            weighted_health += view.health_bps * view.debt
        if view.status == STATUS_OPEN or view.status == STATUS_ACTIVE:
            open_or_active += 1
        if view.status == STATUS_DELINQUENT or view.status == STATUS_DEFAULTED:
            bad += 1
        if view.liquidatable:
            liquidatable_count += 1
        if view.next_due < next_due and view.status == STATUS_ACTIVE:
            next_due = view.next_due
        if view.principal > max_principal:
            max_principal = view.principal
            largest_line = line_id
    health: uint256 = 0
    if aggregate_debt > 0:
        health = weighted_health // aggregate_debt
    if next_due == max_value(uint256):
        next_due = 0
    return BorrowerView(
        borrower=borrower,
        line_count=count,
        total_limit=total_limit,
        total_principal=total_principal,
        total_collateral=total_collateral,
        aggregate_debt=aggregate_debt,
        weighted_health_bps=health,
        open_or_active=open_or_active,
        delinquent_or_defaulted=bad,
        liquidatable_count=liquidatable_count,
        next_due=next_due,
        largest_line=largest_line
    )

@external
@view
def lender_view(account: address) -> LenderView:
    shares: uint256 = 0
    principal_deposited: uint256 = 0
    principal_withdrawn: uint256 = 0
    interest_claimed: uint256 = 0
    reserve_claimed: uint256 = 0
    last_action_at: uint256 = 0
    delegate: address = empty(address)
    locked_until: uint256 = 0
    shares, principal_deposited, principal_withdrawn, interest_claimed, reserve_claimed, last_action_at, delegate, locked_until = staticcall IPyxisCore(self.core).get_lender_summary(account)
    total_shares: uint256 = staticcall IPyxisCore(self.core).total_lender_shares()
    total_principal: uint256 = staticcall IPyxisCore(self.core).total_lender_principal()
    ownership: uint256 = 0
    withdrawable: uint256 = 0
    if total_shares > 0:
        ownership = shares * BPS // total_shares
        withdrawable = shares * total_principal // total_shares
    return LenderView(
        account=account,
        shares=shares,
        principal_deposited=principal_deposited,
        principal_withdrawn=principal_withdrawn,
        interest_claimed=interest_claimed,
        reserve_claimed=reserve_claimed,
        last_action_at=last_action_at,
        delegate=delegate,
        locked_until=locked_until,
        ownership_bps=ownership,
        withdrawable_estimate=withdrawable
    )

@external
@view
def portfolio_view() -> PortfolioView:
    total_lines: uint256 = staticcall IPyxisCore(self.core).line_count()
    open_lines: uint256 = staticcall IPyxisCore(self.core).open_line_count()
    active_lines: uint256 = staticcall IPyxisCore(self.core).active_line_count()
    defaulted_lines: uint256 = staticcall IPyxisCore(self.core).defaulted_line_count()
    liquidated_lines: uint256 = staticcall IPyxisCore(self.core).liquidated_line_count()
    total_lender_principal: uint256 = staticcall IPyxisCore(self.core).total_lender_principal()
    total_lender_shares: uint256 = staticcall IPyxisCore(self.core).total_lender_shares()
    total_principal: uint256 = staticcall IPyxisCore(self.core).total_principal()
    total_interest: uint256 = staticcall IPyxisCore(self.core).total_accrued_interest()
    total_collateral: uint256 = staticcall IPyxisCore(self.core).total_collateral()
    total_defaulted: uint256 = staticcall IPyxisCore(self.core).total_defaulted_debt()
    total_liquidated: uint256 = staticcall IPyxisCore(self.core).total_liquidated_collateral()
    total_reserve: uint256 = staticcall IPyxisCore(self.core).total_reserve()
    utilization: uint256 = 0
    reserve_bps: uint256 = 0
    collateralization: uint256 = 0
    if total_lender_principal > 0:
        utilization = total_principal * BPS // total_lender_principal
        reserve_bps = total_reserve * BPS // total_lender_principal
    if total_principal + total_interest > 0:
        collateralization = total_collateral * BPS // (total_principal + total_interest)
    return PortfolioView(
        total_lines=total_lines,
        open_lines=open_lines,
        active_lines=active_lines,
        defaulted_lines=defaulted_lines,
        liquidated_lines=liquidated_lines,
        total_lender_principal=total_lender_principal,
        total_lender_shares=total_lender_shares,
        total_principal=total_principal,
        total_interest=total_interest,
        total_collateral=total_collateral,
        total_defaulted=total_defaulted,
        total_liquidated=total_liquidated,
        total_reserve=total_reserve,
        utilization_bps=utilization,
        reserve_bps=reserve_bps,
        collateralization_bps=collateralization
    )

@external
@view
def batch_line_health(a: uint256, b: uint256, c: uint256, d: uint256) -> (uint256, uint256, uint256, uint256):
    ha: uint256 = 0
    hb: uint256 = 0
    hc: uint256 = 0
    hd: uint256 = 0
    if a != 0:
        ha = self._line_view(a).health_bps
    if b != 0:
        hb = self._line_view(b).health_bps
    if c != 0:
        hc = self._line_view(c).health_bps
    if d != 0:
        hd = self._line_view(d).health_bps
    return ha, hb, hc, hd

@external
@view
def batch_due_dates(a: uint256, b: uint256, c: uint256, d: uint256) -> (uint256, uint256, uint256, uint256):
    da: uint256 = 0
    db: uint256 = 0
    dc: uint256 = 0
    dd: uint256 = 0
    if a != 0:
        da = self._line_view(a).next_due
    if b != 0:
        db = self._line_view(b).next_due
    if c != 0:
        dc = self._line_view(c).next_due
    if d != 0:
        dd = self._line_view(d).next_due
    return da, db, dc, dd

@external
@view
def batch_current(a: uint256, b: uint256, c: uint256, d: uint256) -> (bool, bool, bool, bool):
    ca: bool = False
    cb: bool = False
    cc: bool = False
    cd: bool = False
    if a != 0:
        ca = staticcall IPyxisCore(self.core).is_current(a)
    if b != 0:
        cb = staticcall IPyxisCore(self.core).is_current(b)
    if c != 0:
        cc = staticcall IPyxisCore(self.core).is_current(c)
    if d != 0:
        cd = staticcall IPyxisCore(self.core).is_current(d)
    return ca, cb, cc, cd
