# pragma version ^0.4.3

interface IERC20:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

BPS: constant(uint256) = 10_000
YEAR: constant(uint256) = 365 * 24 * 60 * 60
STATUS_OPEN: constant(uint256) = 1
STATUS_ACTIVE: constant(uint256) = 2
STATUS_DELINQUENT: constant(uint256) = 3
STATUS_DEFAULTED: constant(uint256) = 4
STATUS_LIQUIDATED: constant(uint256) = 5
STATUS_CLOSED: constant(uint256) = 6

struct Line:
    borrower: address
    limit: uint256
    principal: uint256
    accrued_interest: uint256
    apr_bps: uint256
    min_payment_bps: uint256
    liquidation_bps: uint256
    collateral: uint256
    opened_at: uint256
    last_accrual: uint256
    next_due: uint256
    cycle: uint256
    grace_period: uint256
    minimum_due: uint256
    paid_since_checkpoint: uint256
    status: uint256
    defaulted_at: uint256
    liquidated_collateral: uint256

event LiquidityDeposited:
    account: indexed(address)
    amount: uint256

event LineOpened:
    line_id: indexed(uint256)
    borrower: indexed(address)
    limit: uint256

event CollateralPosted:
    line_id: indexed(uint256)
    amount: uint256

event Drawn:
    line_id: indexed(uint256)
    amount: uint256
    principal: uint256

event Repaid:
    line_id: indexed(uint256)
    amount: uint256
    interest_paid: uint256
    principal_paid: uint256

event Checkpointed:
    line_id: indexed(uint256)
    status: uint256
    minimum_due: uint256
    next_due: uint256

event Defaulted:
    line_id: indexed(uint256)
    debt: uint256
    collateral: uint256

event Liquidated:
    line_id: indexed(uint256)
    liquidator: indexed(address)
    repaid: uint256
    seized: uint256

asset: public(address)
owner: public(address)
underwriter: public(address)
treasury: public(address)
paused: public(bool)
locked: bool
line_count: public(uint256)
active_line_count: public(uint256)
defaulted_line_count: public(uint256)
liquidated_line_count: public(uint256)
total_lender_principal: public(uint256)
total_lender_shares: public(uint256)
total_principal: public(uint256)
total_accrued_interest: public(uint256)
total_interest_paid: public(uint256)
total_principal_paid: public(uint256)
total_collateral: public(uint256)
total_defaulted_debt: public(uint256)
total_liquidated_collateral: public(uint256)
reserve_factor_bps: public(uint256)
minimum_collateral_bps: public(uint256)
liquidation_discount_bps: public(uint256)
keepers: public(HashMap[address, bool])
lender_shares: public(HashMap[address, uint256])
borrower_line_count: public(HashMap[address, uint256])
line_owner_index: public(HashMap[address, HashMap[uint256, uint256]])
borrower_total_limit: public(HashMap[address, uint256])
borrower_total_principal: public(HashMap[address, uint256])
borrower_total_collateral: public(HashMap[address, uint256])
lines: HashMap[uint256, Line]

@deploy
def __init__(_asset: address, _treasury: address, _underwriter: address):
    assert _asset != empty(address), "ASSET"
    assert _treasury != empty(address), "TREASURY"
    assert _underwriter != empty(address), "UNDERWRITER"
    self.asset = _asset
    self.owner = msg.sender
    self.treasury = _treasury
    self.underwriter = _underwriter
    self.reserve_factor_bps = 1_000
    self.minimum_collateral_bps = 2_000
    self.liquidation_discount_bps = 500
    self.keepers[msg.sender] = True
    self.keepers[_underwriter] = True

@internal
def _enter():
    assert not self.locked, "LOCKED"
    self.locked = True

@internal
def _exit():
    self.locked = False

@internal
@view
def _line_exists(line_id: uint256) -> bool:
    return line_id > 0 and line_id <= self.line_count and self.lines[line_id].borrower != empty(address)

@internal
@view
def _is_keeper(account: address) -> bool:
    return account == self.owner or account == self.underwriter or self.keepers[account]

@internal
@view
def _available_liquidity() -> uint256:
    balance: uint256 = staticcall IERC20(self.asset).balanceOf(self)
    reserved: uint256 = self.total_collateral
    if balance <= reserved:
        return 0
    return balance - reserved

@internal
@view
def _pending_interest(line_id: uint256) -> uint256:
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        return 0
    elapsed: uint256 = block.timestamp - self.lines[line_id].last_accrual
    return principal * self.lines[line_id].apr_bps * elapsed // BPS // YEAR

@internal
@view
def _debt(line_id: uint256) -> uint256:
    return self.lines[line_id].principal + self.lines[line_id].accrued_interest + self._pending_interest(line_id)

@internal
@view
def _stored_minimum(line_id: uint256) -> uint256:
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        return 0
    amortization: uint256 = principal * self.lines[line_id].min_payment_bps // BPS
    if self.lines[line_id].accrued_interest > amortization:
        return self.lines[line_id].accrued_interest
    return amortization

@internal
@view
def _live_minimum(line_id: uint256) -> uint256:
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        return 0
    amortization: uint256 = principal * self.lines[line_id].min_payment_bps // BPS
    live_interest: uint256 = self.lines[line_id].accrued_interest + self._pending_interest(line_id)
    if live_interest > amortization:
        return live_interest
    return amortization

@internal
def _accrue(line_id: uint256):
    interest: uint256 = self._pending_interest(line_id)
    if interest > 0:
        self.lines[line_id].accrued_interest += interest
        self.total_accrued_interest += interest
    self.lines[line_id].last_accrual = block.timestamp

@internal
def _apply_payment(line_id: uint256, amount: uint256) -> (uint256, uint256):
    remaining: uint256 = amount
    interest_paid: uint256 = 0
    principal_paid: uint256 = 0
    if self.lines[line_id].accrued_interest > 0:
        if remaining >= self.lines[line_id].accrued_interest:
            interest_paid = self.lines[line_id].accrued_interest
        else:
            interest_paid = remaining
        self.lines[line_id].accrued_interest -= interest_paid
        self.total_accrued_interest -= interest_paid
        self.total_interest_paid += interest_paid
        remaining -= interest_paid
    if remaining > 0 and self.lines[line_id].principal > 0:
        if remaining >= self.lines[line_id].principal:
            principal_paid = self.lines[line_id].principal
        else:
            principal_paid = remaining
        self.lines[line_id].principal -= principal_paid
        self.total_principal -= principal_paid
        self.total_principal_paid += principal_paid
        self.borrower_total_principal[self.lines[line_id].borrower] -= principal_paid
    return interest_paid, principal_paid

@internal
def _close_if_repaid(line_id: uint256):
    if self.lines[line_id].principal == 0 and self.lines[line_id].accrued_interest == 0:
        if self.lines[line_id].status == STATUS_ACTIVE and self.active_line_count > 0:
            self.active_line_count -= 1
        self.lines[line_id].status = STATUS_CLOSED

@internal
def _mark_default(line_id: uint256):
    if self.lines[line_id].status != STATUS_DEFAULTED:
        if self.lines[line_id].status == STATUS_ACTIVE and self.active_line_count > 0:
            self.active_line_count -= 1
        self.lines[line_id].status = STATUS_DEFAULTED
        self.lines[line_id].defaulted_at = block.timestamp
        debt: uint256 = self._debt(line_id)
        self.total_defaulted_debt += debt
        self.defaulted_line_count += 1
        log Defaulted(line_id=line_id, debt=debt, collateral=self.lines[line_id].collateral)

@external
def set_keeper(account: address, allowed: bool):
    assert msg.sender == self.owner or msg.sender == self.underwriter, "AUTH"
    self.keepers[account] = allowed

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner, "OWNER"
    self.paused = enabled

@external
def deposit_liquidity(amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert amount > 0, "AMOUNT"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self.lender_shares[msg.sender] += amount
    self.total_lender_shares += amount
    self.total_lender_principal += amount
    log LiquidityDeposited(account=msg.sender, amount=amount)
    self._exit()

@external
def open_line(
    borrower: address,
    limit: uint256,
    apr_bps: uint256,
    min_payment_bps: uint256,
    cycle: uint256,
    grace_period: uint256,
    liquidation_bps: uint256,
    covenant_score: uint256,
    metadata: bytes32
) -> uint256:
    self._enter()
    assert msg.sender == self.owner or msg.sender == self.underwriter, "AUTH"
    assert borrower != empty(address), "BORROWER"
    assert limit > 0, "LIMIT"
    assert apr_bps <= 5_000, "APR"
    assert min_payment_bps > 0 and min_payment_bps <= 5_000, "MINIMUM"
    assert cycle >= 86_400 and cycle <= 10_368_000, "CYCLE"
    assert liquidation_bps >= BPS and liquidation_bps <= 15_000, "LIQUIDATION"
    self.line_count += 1
    line_id: uint256 = self.line_count
    self.lines[line_id] = Line(
        borrower=borrower,
        limit=limit,
        principal=0,
        accrued_interest=0,
        apr_bps=apr_bps,
        min_payment_bps=min_payment_bps,
        liquidation_bps=liquidation_bps,
        collateral=0,
        opened_at=block.timestamp,
        last_accrual=block.timestamp,
        next_due=block.timestamp + cycle,
        cycle=cycle,
        grace_period=grace_period,
        minimum_due=0,
        paid_since_checkpoint=0,
        status=STATUS_OPEN,
        defaulted_at=0,
        liquidated_collateral=0
    )
    index: uint256 = self.borrower_line_count[borrower]
    self.borrower_line_count[borrower] = index + 1
    self.line_owner_index[borrower][index] = line_id
    self.borrower_total_limit[borrower] += limit
    log LineOpened(line_id=line_id, borrower=borrower, limit=limit)
    self._exit()
    return line_id

@external
def post_collateral(line_id: uint256, amount: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert self.lines[line_id].status == STATUS_OPEN or self.lines[line_id].status == STATUS_ACTIVE, "STATUS"
    assert amount > 0, "AMOUNT"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self.lines[line_id].collateral += amount
    self.total_collateral += amount
    self.borrower_total_collateral[msg.sender] += amount
    log CollateralPosted(line_id=line_id, amount=amount)
    self._exit()

@external
def draw(line_id: uint256, amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert self._line_exists(line_id), "LINE"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert self.lines[line_id].status == STATUS_OPEN or self.lines[line_id].status == STATUS_ACTIVE, "STATUS"
    assert self.lines[line_id].collateral * BPS >= self.lines[line_id].limit * self.minimum_collateral_bps, "COLLATERAL"
    self._accrue(line_id)
    assert self.lines[line_id].principal + amount <= self.lines[line_id].limit, "LIMIT"
    assert amount <= self._available_liquidity(), "LIQUIDITY"
    if self.lines[line_id].status == STATUS_OPEN:
        self.lines[line_id].status = STATUS_ACTIVE
        self.active_line_count += 1
    self.lines[line_id].principal += amount
    self.total_principal += amount
    self.borrower_total_principal[msg.sender] += amount
    self.lines[line_id].minimum_due = self._stored_minimum(line_id)
    assert extcall IERC20(self.asset).transfer(msg.sender, amount), "TRANSFER"
    log Drawn(line_id=line_id, amount=amount, principal=self.lines[line_id].principal)
    self._exit()

@external
def repay(line_id: uint256, amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert self._line_exists(line_id), "LINE"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert self.lines[line_id].status == STATUS_ACTIVE or self.lines[line_id].status == STATUS_DELINQUENT, "STATUS"
    assert amount > 0, "AMOUNT"
    scheduled_due: uint256 = self.lines[line_id].minimum_due
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self.lines[line_id].paid_since_checkpoint += amount
    interest_paid: uint256 = 0
    principal_paid: uint256 = 0
    interest_paid, principal_paid = self._apply_payment(line_id, amount)
    if scheduled_due > 0 and self.lines[line_id].paid_since_checkpoint >= scheduled_due:
        self.lines[line_id].paid_since_checkpoint -= scheduled_due
        self.lines[line_id].minimum_due = self._stored_minimum(line_id)
        self.lines[line_id].next_due = block.timestamp + self.lines[line_id].cycle
        self.lines[line_id].status = STATUS_ACTIVE
    self._accrue(line_id)
    self._close_if_repaid(line_id)
    log Repaid(line_id=line_id, amount=amount, interest_paid=interest_paid, principal_paid=principal_paid)
    self._exit()

@external
def sync_line(line_id: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    self._accrue(line_id)
    self._exit()

@external
def checkpoint(line_id: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert self._is_keeper(msg.sender) or msg.sender == self.lines[line_id].borrower, "KEEPER"
    if self.lines[line_id].status == STATUS_OPEN:
        self.lines[line_id].status = STATUS_ACTIVE
        self.active_line_count += 1
    self._accrue(line_id)
    if block.timestamp > self.lines[line_id].next_due + self.lines[line_id].grace_period:
        if self.lines[line_id].paid_since_checkpoint < self.lines[line_id].minimum_due:
            self._mark_default(line_id)
            log Checkpointed(line_id=line_id, status=self.lines[line_id].status, minimum_due=self.lines[line_id].minimum_due, next_due=self.lines[line_id].next_due)
            self._exit()
            return
    if block.timestamp >= self.lines[line_id].next_due:
        if self.lines[line_id].paid_since_checkpoint >= self.lines[line_id].minimum_due:
            self.lines[line_id].paid_since_checkpoint -= self.lines[line_id].minimum_due
            self.lines[line_id].minimum_due = self._live_minimum(line_id)
            self.lines[line_id].next_due = block.timestamp + self.lines[line_id].cycle
            self.lines[line_id].status = STATUS_ACTIVE
        else:
            self.lines[line_id].status = STATUS_DELINQUENT
    log Checkpointed(line_id=line_id, status=self.lines[line_id].status, minimum_due=self.lines[line_id].minimum_due, next_due=self.lines[line_id].next_due)
    self._exit()

@external
def liquidate(line_id: uint256, repay_amount: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    if self.lines[line_id].status != STATUS_DEFAULTED:
        assert block.timestamp > self.lines[line_id].next_due + self.lines[line_id].grace_period, "NOT_DUE"
        self._accrue(line_id)
        assert self.lines[line_id].paid_since_checkpoint < self.lines[line_id].minimum_due, "CURRENT"
        self._mark_default(line_id)
    debt: uint256 = self._debt(line_id)
    amount: uint256 = repay_amount
    if amount > debt:
        amount = debt
    assert amount > 0, "AMOUNT"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    interest_paid: uint256 = 0
    principal_paid: uint256 = 0
    interest_paid, principal_paid = self._apply_payment(line_id, amount)
    seize: uint256 = amount + amount * self.liquidation_discount_bps // BPS
    if seize > self.lines[line_id].collateral:
        seize = self.lines[line_id].collateral
    self.lines[line_id].collateral -= seize
    self.total_collateral -= seize
    self.borrower_total_collateral[self.lines[line_id].borrower] -= seize
    self.lines[line_id].liquidated_collateral += seize
    self.total_liquidated_collateral += seize
    assert extcall IERC20(self.asset).transfer(msg.sender, seize), "SEIZE"
    if self.lines[line_id].principal == 0 and self.lines[line_id].accrued_interest == 0:
        self.lines[line_id].status = STATUS_LIQUIDATED
        self.liquidated_line_count += 1
    log Liquidated(line_id=line_id, liquidator=msg.sender, repaid=amount, seized=seize)
    self._exit()

@external
@view
def quote_debt(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    return self._debt(line_id)

@external
@view
def quote_interest(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    return self.lines[line_id].accrued_interest + self._pending_interest(line_id)

@external
@view
def quote_minimum_due(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    return self._live_minimum(line_id)

@external
@view
def quote_available(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    capacity: uint256 = 0
    if self.lines[line_id].limit > self.lines[line_id].principal:
        capacity = self.lines[line_id].limit - self.lines[line_id].principal
    liquidity: uint256 = self._available_liquidity()
    if capacity < liquidity:
        return capacity
    return liquidity

@external
@view
def quote_liquidation(line_id: uint256, repay_amount: uint256) -> (uint256, uint256):
    debt: uint256 = self._debt(line_id)
    amount: uint256 = repay_amount
    if amount > debt:
        amount = debt
    seize: uint256 = amount + amount * self.liquidation_discount_bps // BPS
    if seize > self.lines[line_id].collateral:
        seize = self.lines[line_id].collateral
    return amount, seize

@external
@view
def can_liquidate(line_id: uint256) -> bool:
    if not self._line_exists(line_id):
        return False
    if self.lines[line_id].status == STATUS_DEFAULTED:
        return True
    if block.timestamp <= self.lines[line_id].next_due + self.lines[line_id].grace_period:
        return False
    return self.lines[line_id].paid_since_checkpoint < self.lines[line_id].minimum_due

@external
@view
def is_current(line_id: uint256) -> bool:
    if not self._line_exists(line_id):
        return False
    if self.lines[line_id].status != STATUS_ACTIVE:
        return False
    if block.timestamp <= self.lines[line_id].next_due:
        return True
    return self.lines[line_id].paid_since_checkpoint >= self.lines[line_id].minimum_due

@external
@view
def get_line_summary(line_id: uint256) -> (address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256):
    assert self._line_exists(line_id), "LINE"
    return (
        self.lines[line_id].borrower,
        self.lines[line_id].status,
        self.lines[line_id].limit,
        self.lines[line_id].principal,
        self.lines[line_id].accrued_interest + self._pending_interest(line_id),
        self.lines[line_id].minimum_due,
        self.lines[line_id].paid_since_checkpoint,
        self.lines[line_id].next_due,
        self.lines[line_id].collateral,
        0
    )

@external
@view
def get_lender_summary(account: address) -> (uint256, uint256, uint256, uint256, uint256, uint256, address, uint256):
    return (self.lender_shares[account], self.lender_shares[account], 0, 0, 0, 0, empty(address), 0)
