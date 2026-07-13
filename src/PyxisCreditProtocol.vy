# pragma version ^0.4.3

interface IERC20:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

BPS: constant(uint256) = 10_000
YEAR: constant(uint256) = 365 * 24 * 60 * 60
MIN_CYCLE: constant(uint256) = 1 * 24 * 60 * 60
MAX_CYCLE: constant(uint256) = 120 * 24 * 60 * 60
MAX_APR_BPS: constant(uint256) = 5_000
MAX_MIN_PAYMENT_BPS: constant(uint256) = 5_000
MAX_LIQUIDATION_BPS: constant(uint256) = 15_000
MAX_RESERVE_BPS: constant(uint256) = 5_000
STATUS_NONE: constant(uint256) = 0
STATUS_OPEN: constant(uint256) = 1
STATUS_ACTIVE: constant(uint256) = 2
STATUS_DELINQUENT: constant(uint256) = 3
STATUS_DEFAULTED: constant(uint256) = 4
STATUS_LIQUIDATED: constant(uint256) = 5
STATUS_CLOSED: constant(uint256) = 6
EVENT_OPENED: constant(bytes32) = keccak256("LINE_OPENED")
EVENT_DRAWN: constant(bytes32) = keccak256("LINE_DRAWN")
EVENT_REPAID: constant(bytes32) = keccak256("LINE_REPAID")
EVENT_CHECKPOINT: constant(bytes32) = keccak256("LINE_CHECKPOINT")
EVENT_DEFAULT: constant(bytes32) = keccak256("LINE_DEFAULT")
EVENT_LIQUIDATION: constant(bytes32) = keccak256("LINE_LIQUIDATION")

struct CreditLine:
    borrower: address
    controller: address
    limit: uint256
    principal: uint256
    accrued_interest: uint256
    apr_bps: uint256
    min_payment_bps: uint256
    liquidation_bps: uint256
    reserve_bps: uint256
    collateral: uint256
    opened_at: uint256
    last_accrual: uint256
    last_checkpoint: uint256
    next_due: uint256
    cycle: uint256
    grace_period: uint256
    minimum_due: uint256
    paid_since_checkpoint: uint256
    status: uint256
    drawn_total: uint256
    repaid_total: uint256
    interest_paid: uint256
    principal_paid: uint256
    missed_cycles: uint256
    defaulted_at: uint256
    liquidated_at: uint256
    liquidator: address
    liquidation_value: uint256
    covenant_score: uint256
    risk_weight_bps: uint256
    last_payment_at: uint256
    last_draw_at: uint256
    metadata: bytes32

struct LenderState:
    shares: uint256
    principal_deposited: uint256
    principal_withdrawn: uint256
    interest_claimed: uint256
    reserve_claimed: uint256
    first_deposit_at: uint256
    last_action_at: uint256
    delegate: address
    locked_until: uint256
    flags: uint256

struct ProtocolSnapshot:
    liquid_assets: uint256
    total_lender_shares: uint256
    total_principal: uint256
    total_accrued_interest: uint256
    total_collateral: uint256
    total_defaulted: uint256
    total_liquidated: uint256
    total_reserve: uint256
    open_lines: uint256
    active_lines: uint256
    defaulted_lines: uint256
    utilization_bps: uint256
    reserve_ratio_bps: uint256
    updated_at: uint256

event LiquidityDeposited:
    account: indexed(address)
    amount: uint256
    shares: uint256

event LiquidityWithdrawn:
    account: indexed(address)
    amount: uint256
    shares: uint256

event LineOpened:
    line_id: indexed(uint256)
    borrower: indexed(address)
    limit: uint256
    apr_bps: uint256

event CollateralPosted:
    line_id: indexed(uint256)
    borrower: indexed(address)
    amount: uint256

event Drawn:
    line_id: indexed(uint256)
    borrower: indexed(address)
    amount: uint256
    principal: uint256

event Repaid:
    line_id: indexed(uint256)
    borrower: indexed(address)
    amount: uint256
    interest_paid: uint256
    principal_paid: uint256

event Checkpointed:
    line_id: indexed(uint256)
    status: uint256
    minimum_due: uint256
    next_due: uint256

event LineDefaulted:
    line_id: indexed(uint256)
    borrower: indexed(address)
    debt: uint256
    collateral: uint256

event Liquidated:
    line_id: indexed(uint256)
    liquidator: indexed(address)
    repaid: uint256
    seized: uint256

event TreasuryChanged:
    old_treasury: indexed(address)
    new_treasury: indexed(address)

event UnderwriterChanged:
    old_underwriter: indexed(address)
    new_underwriter: indexed(address)

event ParameterChanged:
    key: indexed(bytes32)
    value: uint256

asset: public(address)
owner: public(address)
treasury: public(address)
underwriter: public(address)
paused: public(bool)
locked: bool

line_count: public(uint256)
open_line_count: public(uint256)
active_line_count: public(uint256)
defaulted_line_count: public(uint256)
liquidated_line_count: public(uint256)
total_lender_shares: public(uint256)
total_lender_principal: public(uint256)
total_principal: public(uint256)
total_accrued_interest: public(uint256)
total_interest_paid: public(uint256)
total_principal_paid: public(uint256)
total_collateral: public(uint256)
total_defaulted_debt: public(uint256)
total_liquidated_collateral: public(uint256)
total_reserve: public(uint256)
total_reserve_claimed: public(uint256)
reserve_factor_bps: public(uint256)
minimum_collateral_bps: public(uint256)
global_line_limit: public(uint256)
global_borrower_limit: public(uint256)
liquidation_discount_bps: public(uint256)
keeper_reward_bps: public(uint256)
last_snapshot_at: public(uint256)
snapshot_liquid_assets: public(uint256)
snapshot_utilization_bps: public(uint256)

lines: HashMap[uint256, CreditLine]
lenders: HashMap[address, LenderState]
borrower_line_count: public(HashMap[address, uint256])
borrower_total_limit: public(HashMap[address, uint256])
borrower_total_principal: public(HashMap[address, uint256])
borrower_total_collateral: public(HashMap[address, uint256])
authorized_keepers: public(HashMap[address, bool])
controllers: public(HashMap[address, bool])
line_owner_index: public(HashMap[address, HashMap[uint256, uint256]])
event_counts: public(HashMap[bytes32, uint256])

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
    self.global_line_limit = max_value(uint256)
    self.global_borrower_limit = max_value(uint256)
    self.liquidation_discount_bps = 500
    self.keeper_reward_bps = 50
    self.authorized_keepers[msg.sender] = True
    self.controllers[msg.sender] = True
    self.last_snapshot_at = block.timestamp

@internal
def _enter():
    assert not self.locked, "LOCKED"
    self.locked = True

@internal
def _exit():
    self.locked = False

@internal
@view
def _is_admin(account: address) -> bool:
    return account == self.owner or account == self.underwriter or self.controllers[account]

@internal
@view
def _is_keeper(account: address) -> bool:
    return account == self.owner or account == self.underwriter or self.authorized_keepers[account]

@internal
@view
def _line_exists(line_id: uint256) -> bool:
    return line_id > 0 and line_id <= self.line_count and self.lines[line_id].borrower != empty(address)

@internal
@view
def _available_liquidity() -> uint256:
    balance: uint256 = staticcall IERC20(self.asset).balanceOf(self)
    if balance <= self.total_collateral + self.total_reserve:
        return 0
    return balance - self.total_collateral - self.total_reserve

@internal
@view
def _debt_of(line_id: uint256) -> uint256:
    return self.lines[line_id].principal + self.lines[line_id].accrued_interest

@internal
@view
def _pending_interest(line_id: uint256) -> uint256:
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        return 0
    elapsed: uint256 = block.timestamp - self.lines[line_id].last_accrual
    if elapsed == 0:
        return 0
    return principal * self.lines[line_id].apr_bps * elapsed // BPS // YEAR

@internal
@view
def _minimum_from_state(line_id: uint256) -> uint256:
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        return 0
    amortization: uint256 = principal * self.lines[line_id].min_payment_bps // BPS
    scheduled_interest: uint256 = self.lines[line_id].accrued_interest
    if amortization < scheduled_interest:
        return scheduled_interest
    return amortization

@internal
@view
def _minimum_with_pending(line_id: uint256) -> uint256:
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        return 0
    amortization: uint256 = principal * self.lines[line_id].min_payment_bps // BPS
    scheduled_interest: uint256 = self.lines[line_id].accrued_interest + self._pending_interest(line_id)
    if amortization < scheduled_interest:
        return scheduled_interest
    return amortization

@internal
@view
def _collateral_required(limit: uint256) -> uint256:
    return limit * self.minimum_collateral_bps // BPS

@internal
@view
def _line_capacity(line_id: uint256) -> uint256:
    if self.lines[line_id].limit <= self.lines[line_id].principal:
        return 0
    return self.lines[line_id].limit - self.lines[line_id].principal

@internal
@view
def _utilization_bps() -> uint256:
    supplied: uint256 = self.total_lender_principal
    if supplied == 0:
        return 0
    if self.total_principal >= supplied:
        return BPS
    return self.total_principal * BPS // supplied

@internal
@view
def _reserve_ratio_bps() -> uint256:
    supplied: uint256 = self.total_lender_principal
    if supplied == 0:
        return 0
    return self.total_reserve * BPS // supplied

@internal
def _record_event(kind: bytes32):
    self.event_counts[kind] += 1

@internal
def _accrue(line_id: uint256):
    assert self._line_exists(line_id), "LINE"
    principal: uint256 = self.lines[line_id].principal
    if principal == 0:
        self.lines[line_id].last_accrual = block.timestamp
        return
    elapsed: uint256 = block.timestamp - self.lines[line_id].last_accrual
    if elapsed == 0:
        return
    interest: uint256 = principal * self.lines[line_id].apr_bps * elapsed // BPS // YEAR
    if interest > 0:
        self.lines[line_id].accrued_interest += interest
        self.total_accrued_interest += interest
    self.lines[line_id].last_accrual = block.timestamp

@internal
def _apply_payment(line_id: uint256, amount: uint256) -> (uint256, uint256, uint256):
    remaining: uint256 = amount
    interest_paid: uint256 = 0
    principal_paid: uint256 = 0
    reserve_paid: uint256 = 0
    accrued: uint256 = self.lines[line_id].accrued_interest
    if remaining > 0 and accrued > 0:
        if remaining >= accrued:
            interest_paid = accrued
        else:
            interest_paid = remaining
        self.lines[line_id].accrued_interest -= interest_paid
        self.total_accrued_interest -= interest_paid
        remaining -= interest_paid
    if interest_paid > 0:
        reserve_paid = interest_paid * self.lines[line_id].reserve_bps // BPS
        if reserve_paid > 0:
            self.total_reserve += reserve_paid
        self.lines[line_id].interest_paid += interest_paid
        self.total_interest_paid += interest_paid
    principal: uint256 = self.lines[line_id].principal
    if remaining > 0 and principal > 0:
        if remaining >= principal:
            principal_paid = principal
        else:
            principal_paid = remaining
        self.lines[line_id].principal -= principal_paid
        self.total_principal -= principal_paid
        self.borrower_total_principal[self.lines[line_id].borrower] -= principal_paid
        self.lines[line_id].principal_paid += principal_paid
        self.total_principal_paid += principal_paid
        remaining -= principal_paid
    self.lines[line_id].repaid_total += amount - remaining
    return interest_paid, principal_paid, reserve_paid

@internal
def _refresh_snapshot():
    self.snapshot_liquid_assets = self._available_liquidity()
    self.snapshot_utilization_bps = self._utilization_bps()
    self.last_snapshot_at = block.timestamp

@internal
def _close_if_repaid(line_id: uint256):
    if self.lines[line_id].principal == 0 and self.lines[line_id].accrued_interest == 0:
        if self.lines[line_id].status == STATUS_ACTIVE or self.lines[line_id].status == STATUS_DELINQUENT:
            if self.active_line_count > 0:
                self.active_line_count -= 1
            self.lines[line_id].status = STATUS_CLOSED
            self.lines[line_id].minimum_due = 0
            self.lines[line_id].paid_since_checkpoint = 0
            if self.lines[line_id].collateral > 0:
                collateral: uint256 = self.lines[line_id].collateral
                self.lines[line_id].collateral = 0
                self.total_collateral -= collateral
                self.borrower_total_collateral[self.lines[line_id].borrower] -= collateral
                assert extcall IERC20(self.asset).transfer(self.lines[line_id].borrower, collateral), "COLLATERAL_RETURN"

@internal
def _start_line(line_id: uint256):
    if self.lines[line_id].status == STATUS_OPEN:
        self.lines[line_id].status = STATUS_ACTIVE
        self.lines[line_id].last_checkpoint = block.timestamp
        self.lines[line_id].next_due = block.timestamp + self.lines[line_id].cycle
        self.lines[line_id].minimum_due = self._minimum_from_state(line_id)
        self.active_line_count += 1
        if self.open_line_count > 0:
            self.open_line_count -= 1

@internal
def _mark_default(line_id: uint256):
    if self.lines[line_id].status != STATUS_DEFAULTED:
        if self.lines[line_id].status == STATUS_ACTIVE or self.lines[line_id].status == STATUS_DELINQUENT:
            if self.active_line_count > 0:
                self.active_line_count -= 1
        self.lines[line_id].status = STATUS_DEFAULTED
        self.lines[line_id].defaulted_at = block.timestamp
        self.lines[line_id].missed_cycles += 1
        debt: uint256 = self._debt_of(line_id)
        self.total_defaulted_debt += debt
        self.defaulted_line_count += 1
        self._record_event(EVENT_DEFAULT)
        log LineDefaulted(line_id=line_id, borrower=self.lines[line_id].borrower, debt=debt, collateral=self.lines[line_id].collateral)

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner, "OWNER"
    self.paused = enabled

@external
def set_treasury(new_treasury: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_treasury != empty(address), "TREASURY"
    old: address = self.treasury
    self.treasury = new_treasury
    log TreasuryChanged(old_treasury=old, new_treasury=new_treasury)

@external
def set_underwriter(new_underwriter: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_underwriter != empty(address), "UNDERWRITER"
    old: address = self.underwriter
    self.underwriter = new_underwriter
    log UnderwriterChanged(old_underwriter=old, new_underwriter=new_underwriter)

@external
def set_controller(account: address, allowed: bool):
    assert msg.sender == self.owner, "OWNER"
    self.controllers[account] = allowed

@external
def set_keeper(account: address, allowed: bool):
    assert msg.sender == self.owner or msg.sender == self.underwriter, "AUTH"
    self.authorized_keepers[account] = allowed

@external
def set_reserve_factor(new_value: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_value <= MAX_RESERVE_BPS, "RESERVE"
    self.reserve_factor_bps = new_value
    log ParameterChanged(key=keccak256("reserve_factor_bps"), value=new_value)

@external
def set_minimum_collateral(new_value: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_value <= MAX_LIQUIDATION_BPS, "COLLATERAL"
    self.minimum_collateral_bps = new_value
    log ParameterChanged(key=keccak256("minimum_collateral_bps"), value=new_value)

@external
def set_global_line_limit(new_value: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_value > 0, "LIMIT"
    self.global_line_limit = new_value
    log ParameterChanged(key=keccak256("global_line_limit"), value=new_value)

@external
def set_global_borrower_limit(new_value: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_value > 0, "BORROWER_LIMIT"
    self.global_borrower_limit = new_value
    log ParameterChanged(key=keccak256("global_borrower_limit"), value=new_value)

@external
def set_liquidation_discount(new_value: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_value <= 2_500, "DISCOUNT"
    self.liquidation_discount_bps = new_value
    log ParameterChanged(key=keccak256("liquidation_discount_bps"), value=new_value)

@external
def set_keeper_reward(new_value: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_value <= 500, "KEEPER_REWARD"
    self.keeper_reward_bps = new_value
    log ParameterChanged(key=keccak256("keeper_reward_bps"), value=new_value)

@external
def deposit_liquidity(amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert amount > 0, "AMOUNT"
    shares: uint256 = amount
    if self.total_lender_shares > 0 and self.total_lender_principal > 0:
        shares = amount * self.total_lender_shares // self.total_lender_principal
        if shares == 0:
            shares = 1
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    if self.lenders[msg.sender].first_deposit_at == 0:
        self.lenders[msg.sender].first_deposit_at = block.timestamp
    self.lenders[msg.sender].shares += shares
    self.lenders[msg.sender].principal_deposited += amount
    self.lenders[msg.sender].last_action_at = block.timestamp
    self.total_lender_shares += shares
    self.total_lender_principal += amount
    self._refresh_snapshot()
    log LiquidityDeposited(account=msg.sender, amount=amount, shares=shares)
    self._exit()

@external
def withdraw_liquidity(shares: uint256):
    self._enter()
    assert shares > 0, "SHARES"
    assert self.lenders[msg.sender].shares >= shares, "BALANCE"
    assert self.lenders[msg.sender].locked_until <= block.timestamp, "LOCKED_LENDER"
    amount: uint256 = shares
    if self.total_lender_shares > 0:
        amount = shares * self.total_lender_principal // self.total_lender_shares
    assert amount <= self._available_liquidity(), "LIQUIDITY"
    self.lenders[msg.sender].shares -= shares
    self.lenders[msg.sender].principal_withdrawn += amount
    self.lenders[msg.sender].last_action_at = block.timestamp
    self.total_lender_shares -= shares
    self.total_lender_principal -= amount
    assert extcall IERC20(self.asset).transfer(msg.sender, amount), "TRANSFER"
    self._refresh_snapshot()
    log LiquidityWithdrawn(account=msg.sender, amount=amount, shares=shares)
    self._exit()

@external
def lock_lender_until(account: address, timestamp: uint256):
    assert self._is_admin(msg.sender), "AUTH"
    assert account != empty(address), "ACCOUNT"
    self.lenders[account].locked_until = timestamp

@external
def set_lender_delegate(delegate: address):
    self.lenders[msg.sender].delegate = delegate
    self.lenders[msg.sender].last_action_at = block.timestamp

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
    assert not self.paused, "PAUSED"
    assert self._is_admin(msg.sender), "AUTH"
    assert borrower != empty(address), "BORROWER"
    assert limit > 0 and limit <= self.global_line_limit, "LIMIT"
    assert self.borrower_total_limit[borrower] + limit <= self.global_borrower_limit, "BORROWER_LIMIT"
    assert apr_bps <= MAX_APR_BPS, "APR"
    assert min_payment_bps > 0 and min_payment_bps <= MAX_MIN_PAYMENT_BPS, "MIN_PAYMENT"
    assert cycle >= MIN_CYCLE and cycle <= MAX_CYCLE, "CYCLE"
    assert liquidation_bps >= BPS and liquidation_bps <= MAX_LIQUIDATION_BPS, "LIQUIDATION"
    assert covenant_score <= BPS, "COVENANT"
    self.line_count += 1
    line_id: uint256 = self.line_count
    self.lines[line_id] = CreditLine(
        borrower=borrower,
        controller=msg.sender,
        limit=limit,
        principal=0,
        accrued_interest=0,
        apr_bps=apr_bps,
        min_payment_bps=min_payment_bps,
        liquidation_bps=liquidation_bps,
        reserve_bps=self.reserve_factor_bps,
        collateral=0,
        opened_at=block.timestamp,
        last_accrual=block.timestamp,
        last_checkpoint=block.timestamp,
        next_due=block.timestamp + cycle,
        cycle=cycle,
        grace_period=grace_period,
        minimum_due=0,
        paid_since_checkpoint=0,
        status=STATUS_OPEN,
        drawn_total=0,
        repaid_total=0,
        interest_paid=0,
        principal_paid=0,
        missed_cycles=0,
        defaulted_at=0,
        liquidated_at=0,
        liquidator=empty(address),
        liquidation_value=0,
        covenant_score=covenant_score,
        risk_weight_bps=BPS,
        last_payment_at=0,
        last_draw_at=0,
        metadata=metadata
    )
    count: uint256 = self.borrower_line_count[borrower]
    self.borrower_line_count[borrower] = count + 1
    self.line_owner_index[borrower][count] = line_id
    self.borrower_total_limit[borrower] += limit
    self.open_line_count += 1
    self._record_event(EVENT_OPENED)
    log LineOpened(line_id=line_id, borrower=borrower, limit=limit, apr_bps=apr_bps)
    self._exit()
    return line_id

@external
def post_collateral(line_id: uint256, amount: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert amount > 0, "AMOUNT"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert self.lines[line_id].status == STATUS_OPEN or self.lines[line_id].status == STATUS_ACTIVE, "STATUS"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self.lines[line_id].collateral += amount
    self.total_collateral += amount
    self.borrower_total_collateral[msg.sender] += amount
    log CollateralPosted(line_id=line_id, borrower=msg.sender, amount=amount)
    self._exit()

@external
def draw(line_id: uint256, amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert self._line_exists(line_id), "LINE"
    assert amount > 0, "AMOUNT"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert self.lines[line_id].status == STATUS_OPEN or self.lines[line_id].status == STATUS_ACTIVE, "STATUS"
    assert self.lines[line_id].collateral >= self._collateral_required(self.lines[line_id].limit), "COLLATERAL"
    self._start_line(line_id)
    self._accrue(line_id)
    assert amount <= self._line_capacity(line_id), "CAPACITY"
    assert amount <= self._available_liquidity(), "LIQUIDITY"
    self.lines[line_id].principal += amount
    self.lines[line_id].drawn_total += amount
    self.lines[line_id].last_draw_at = block.timestamp
    self.total_principal += amount
    self.borrower_total_principal[self.lines[line_id].borrower] += amount
    if self.lines[line_id].minimum_due == 0:
        self.lines[line_id].minimum_due = self._minimum_from_state(line_id)
    assert extcall IERC20(self.asset).transfer(msg.sender, amount), "TRANSFER"
    self._refresh_snapshot()
    self._record_event(EVENT_DRAWN)
    log Drawn(line_id=line_id, borrower=msg.sender, amount=amount, principal=self.lines[line_id].principal)
    self._exit()

@external
def repay(line_id: uint256, amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert self._line_exists(line_id), "LINE"
    assert amount > 0, "AMOUNT"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert self.lines[line_id].status == STATUS_ACTIVE or self.lines[line_id].status == STATUS_DELINQUENT, "STATUS"
    scheduled_due: uint256 = self.lines[line_id].minimum_due
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self.lines[line_id].paid_since_checkpoint += amount
    interest_paid: uint256 = 0
    principal_paid: uint256 = 0
    reserve_paid: uint256 = 0
    interest_paid, principal_paid, reserve_paid = self._apply_payment(line_id, amount)
    if scheduled_due > 0 and self.lines[line_id].paid_since_checkpoint >= scheduled_due:
        self.lines[line_id].paid_since_checkpoint -= scheduled_due
        self.lines[line_id].minimum_due = self._minimum_from_state(line_id)
        self.lines[line_id].last_checkpoint = block.timestamp
        self.lines[line_id].next_due = block.timestamp + self.lines[line_id].cycle
        self.lines[line_id].status = STATUS_ACTIVE
    self._accrue(line_id)
    self.lines[line_id].last_payment_at = block.timestamp
    self._close_if_repaid(line_id)
    self._refresh_snapshot()
    self._record_event(EVENT_REPAID)
    log Repaid(line_id=line_id, borrower=msg.sender, amount=amount, interest_paid=interest_paid, principal_paid=principal_paid)
    self._exit()

@external
def checkpoint(line_id: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert self._is_keeper(msg.sender) or msg.sender == self.lines[line_id].borrower, "KEEPER"
    status: uint256 = self.lines[line_id].status
    assert status == STATUS_ACTIVE or status == STATUS_DELINQUENT or status == STATUS_OPEN, "STATUS"
    if status == STATUS_OPEN:
        self._start_line(line_id)
    self._accrue(line_id)
    if self.lines[line_id].principal == 0 and self.lines[line_id].accrued_interest == 0:
        self._close_if_repaid(line_id)
        self._refresh_snapshot()
        log Checkpointed(line_id=line_id, status=self.lines[line_id].status, minimum_due=self.lines[line_id].minimum_due, next_due=self.lines[line_id].next_due)
        self._exit()
        return
    if block.timestamp > self.lines[line_id].next_due + self.lines[line_id].grace_period:
        if self.lines[line_id].paid_since_checkpoint < self.lines[line_id].minimum_due:
            self._mark_default(line_id)
            self._refresh_snapshot()
            log Checkpointed(line_id=line_id, status=self.lines[line_id].status, minimum_due=self.lines[line_id].minimum_due, next_due=self.lines[line_id].next_due)
            self._exit()
            return
    if block.timestamp >= self.lines[line_id].next_due:
        if self.lines[line_id].paid_since_checkpoint >= self.lines[line_id].minimum_due:
            if self.lines[line_id].minimum_due > 0:
                self.lines[line_id].paid_since_checkpoint -= self.lines[line_id].minimum_due
            self.lines[line_id].minimum_due = self._minimum_with_pending(line_id)
            self.lines[line_id].last_checkpoint = block.timestamp
            self.lines[line_id].next_due = block.timestamp + self.lines[line_id].cycle
            self.lines[line_id].status = STATUS_ACTIVE
        else:
            self.lines[line_id].status = STATUS_DELINQUENT
    self._refresh_snapshot()
    self._record_event(EVENT_CHECKPOINT)
    log Checkpointed(line_id=line_id, status=self.lines[line_id].status, minimum_due=self.lines[line_id].minimum_due, next_due=self.lines[line_id].next_due)
    self._exit()

@external
def liquidate(line_id: uint256, repay_amount: uint256):
    self._enter()
    assert not self.paused, "PAUSED"
    assert self._line_exists(line_id), "LINE"
    if self.lines[line_id].status != STATUS_DEFAULTED:
        assert block.timestamp > self.lines[line_id].next_due + self.lines[line_id].grace_period, "NOT_DUE"
        self._accrue(line_id)
        assert self.lines[line_id].paid_since_checkpoint < self.lines[line_id].minimum_due, "CURRENT"
        self._mark_default(line_id)
    assert self.lines[line_id].status == STATUS_DEFAULTED, "STATUS"
    debt: uint256 = self._debt_of(line_id)
    assert debt > 0, "DEBT"
    amount: uint256 = repay_amount
    if amount > debt:
        amount = debt
    assert amount > 0, "AMOUNT"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    bonus: uint256 = amount * self.liquidation_discount_bps // BPS
    seize: uint256 = amount + bonus
    if seize > self.lines[line_id].collateral:
        seize = self.lines[line_id].collateral
    interest_paid: uint256 = 0
    principal_paid: uint256 = 0
    reserve_paid: uint256 = 0
    interest_paid, principal_paid, reserve_paid = self._apply_payment(line_id, amount)
    if seize > 0:
        self.lines[line_id].collateral -= seize
        self.total_collateral -= seize
        self.borrower_total_collateral[self.lines[line_id].borrower] -= seize
        assert extcall IERC20(self.asset).transfer(msg.sender, seize), "SEIZE"
    self.lines[line_id].liquidator = msg.sender
    self.lines[line_id].liquidation_value += seize
    self.lines[line_id].liquidated_at = block.timestamp
    self.total_liquidated_collateral += seize
    self._record_event(EVENT_LIQUIDATION)
    if self.lines[line_id].principal == 0 and self.lines[line_id].accrued_interest == 0:
        self.lines[line_id].status = STATUS_LIQUIDATED
        self.liquidated_line_count += 1
    self._refresh_snapshot()
    log Liquidated(line_id=line_id, liquidator=msg.sender, repaid=amount, seized=seize)
    self._exit()

@external
def seize_residual_collateral(line_id: uint256, receiver: address):
    self._enter()
    assert self._is_admin(msg.sender), "AUTH"
    assert self._line_exists(line_id), "LINE"
    assert receiver != empty(address), "RECEIVER"
    assert self.lines[line_id].status == STATUS_LIQUIDATED or self.lines[line_id].status == STATUS_DEFAULTED, "STATUS"
    collateral: uint256 = self.lines[line_id].collateral
    assert collateral > 0, "COLLATERAL"
    self.lines[line_id].collateral = 0
    self.total_collateral -= collateral
    self.borrower_total_collateral[self.lines[line_id].borrower] -= collateral
    assert extcall IERC20(self.asset).transfer(receiver, collateral), "TRANSFER"
    self._refresh_snapshot()
    self._exit()

@external
def claim_reserve(amount: uint256):
    self._enter()
    assert msg.sender == self.treasury or msg.sender == self.owner, "TREASURY"
    assert amount > 0 and amount <= self.total_reserve, "AMOUNT"
    assert amount <= staticcall IERC20(self.asset).balanceOf(self), "BALANCE"
    self.total_reserve -= amount
    self.total_reserve_claimed += amount
    assert extcall IERC20(self.asset).transfer(self.treasury, amount), "TRANSFER"
    self._refresh_snapshot()
    self._exit()

@external
def release_collateral(line_id: uint256, amount: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert msg.sender == self.lines[line_id].borrower, "BORROWER"
    assert amount > 0, "AMOUNT"
    assert self.lines[line_id].status == STATUS_OPEN or self.lines[line_id].status == STATUS_ACTIVE, "STATUS"
    self._accrue(line_id)
    debt: uint256 = self._debt_of(line_id)
    remaining: uint256 = self.lines[line_id].collateral - amount
    required: uint256 = self._collateral_required(self.lines[line_id].limit)
    if debt == 0:
        required = 0
    assert remaining >= required, "COVERAGE"
    self.lines[line_id].collateral = remaining
    self.total_collateral -= amount
    self.borrower_total_collateral[msg.sender] -= amount
    assert extcall IERC20(self.asset).transfer(msg.sender, amount), "TRANSFER"
    self._refresh_snapshot()
    self._exit()

@external
def update_line_metadata(line_id: uint256, metadata: bytes32):
    assert self._line_exists(line_id), "LINE"
    assert self._is_admin(msg.sender) or msg.sender == self.lines[line_id].borrower, "AUTH"
    self.lines[line_id].metadata = metadata

@external
def update_covenant_score(line_id: uint256, score: uint256):
    assert self._line_exists(line_id), "LINE"
    assert self._is_admin(msg.sender), "AUTH"
    assert score <= BPS, "SCORE"
    self.lines[line_id].covenant_score = score

@external
def update_risk_weight(line_id: uint256, weight_bps: uint256):
    assert self._line_exists(line_id), "LINE"
    assert self._is_admin(msg.sender), "AUTH"
    assert weight_bps >= BPS and weight_bps <= MAX_LIQUIDATION_BPS, "WEIGHT"
    self.lines[line_id].risk_weight_bps = weight_bps

@external
def extend_grace_period(line_id: uint256, additional_seconds: uint256):
    assert self._line_exists(line_id), "LINE"
    assert self._is_admin(msg.sender), "AUTH"
    assert additional_seconds <= MAX_CYCLE, "GRACE"
    self.lines[line_id].grace_period += additional_seconds

@external
def reduce_line_limit(line_id: uint256, new_limit: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert self._is_admin(msg.sender), "AUTH"
    assert new_limit >= self.lines[line_id].principal, "PRINCIPAL"
    assert new_limit < self.lines[line_id].limit, "LIMIT"
    old_limit: uint256 = self.lines[line_id].limit
    self.lines[line_id].limit = new_limit
    self.borrower_total_limit[self.lines[line_id].borrower] -= old_limit - new_limit
    self._refresh_snapshot()
    self._exit()

@external
def increase_line_limit(line_id: uint256, new_limit: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    assert self._is_admin(msg.sender), "AUTH"
    assert new_limit > self.lines[line_id].limit, "LIMIT"
    delta: uint256 = new_limit - self.lines[line_id].limit
    assert new_limit <= self.global_line_limit, "GLOBAL"
    assert self.borrower_total_limit[self.lines[line_id].borrower] + delta <= self.global_borrower_limit, "BORROWER_LIMIT"
    self.lines[line_id].limit = new_limit
    self.borrower_total_limit[self.lines[line_id].borrower] += delta
    self._refresh_snapshot()
    self._exit()

@external
def sync_line(line_id: uint256):
    self._enter()
    assert self._line_exists(line_id), "LINE"
    self._accrue(line_id)
    self._refresh_snapshot()
    self._exit()

@external
@view
def quote_debt(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    return self._debt_of(line_id) + self._pending_interest(line_id)

@external
@view
def quote_interest(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    return self.lines[line_id].accrued_interest + self._pending_interest(line_id)

@external
@view
def quote_minimum_due(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    return self._minimum_with_pending(line_id)

@external
@view
def quote_available(line_id: uint256) -> uint256:
    assert self._line_exists(line_id), "LINE"
    capacity: uint256 = self._line_capacity(line_id)
    liquidity: uint256 = self._available_liquidity()
    if capacity < liquidity:
        return capacity
    return liquidity

@external
@view
def quote_collateral_required(limit: uint256) -> uint256:
    return self._collateral_required(limit)

@external
@view
def quote_liquidation(line_id: uint256, repay_amount: uint256) -> (uint256, uint256):
    assert self._line_exists(line_id), "LINE"
    debt: uint256 = self._debt_of(line_id) + self._pending_interest(line_id)
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
    if self.lines[line_id].status != STATUS_ACTIVE and self.lines[line_id].status != STATUS_DELINQUENT:
        return False
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
def get_line_summary(line_id: uint256) -> (
    address,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256
):
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
        self.lines[line_id].covenant_score
    )

@external
@view
def get_lender_summary(account: address) -> (
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    address,
    uint256
):
    return (
        self.lenders[account].shares,
        self.lenders[account].principal_deposited,
        self.lenders[account].principal_withdrawn,
        self.lenders[account].interest_claimed,
        self.lenders[account].reserve_claimed,
        self.lenders[account].last_action_at,
        self.lenders[account].delegate,
        self.lenders[account].locked_until
    )

@external
@view
def protocol_snapshot() -> ProtocolSnapshot:
    return ProtocolSnapshot(
        liquid_assets=self._available_liquidity(),
        total_lender_shares=self.total_lender_shares,
        total_principal=self.total_principal,
        total_accrued_interest=self.total_accrued_interest,
        total_collateral=self.total_collateral,
        total_defaulted=self.total_defaulted_debt,
        total_liquidated=self.total_liquidated_collateral,
        total_reserve=self.total_reserve,
        open_lines=self.open_line_count,
        active_lines=self.active_line_count,
        defaulted_lines=self.defaulted_line_count,
        utilization_bps=self._utilization_bps(),
        reserve_ratio_bps=self._reserve_ratio_bps(),
        updated_at=block.timestamp
    )
