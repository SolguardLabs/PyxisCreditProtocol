# pragma version ^0.4.3

interface IERC20:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

interface IPyxisCore:
    def quote_debt(line_id: uint256) -> uint256: view
    def quote_liquidation(line_id: uint256, repay_amount: uint256) -> (uint256, uint256): view
    def can_liquidate(line_id: uint256) -> bool: view
    def liquidate(line_id: uint256, repay_amount: uint256): nonpayable
    def get_line_summary(line_id: uint256) -> (address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256): view

BPS: constant(uint256) = 10_000
MAX_DAILY_ROUTES: constant(uint256) = 512
MAX_REPAY_BPS: constant(uint256) = 10_000
STATUS_DEFAULTED: constant(uint256) = 4

struct RoutePolicy:
    enabled: bool
    max_repay_bps: uint256
    min_profit_bps: uint256
    max_daily_routes: uint256
    keeper_fee_bps: uint256
    daily_routes: uint256
    day_index: uint256
    total_routes: uint256
    total_repaid: uint256
    total_seized: uint256

struct RouteTicket:
    exists: bool
    line_id: uint256
    liquidator: address
    max_repay: uint256
    min_seize: uint256
    deadline: uint256
    created_at: uint256
    executed_at: uint256
    cancelled: bool
    metadata: bytes32

struct RouteQuote:
    line_id: uint256
    borrower: address
    debt: uint256
    repay: uint256
    seize: uint256
    profit_bps: uint256
    liquidatable: bool
    status: uint256
    deadline_safe: bool

event OwnerChanged:
    old_owner: indexed(address)
    new_owner: indexed(address)

event KeeperChanged:
    keeper: indexed(address)
    allowed: bool

event PolicyUpdated:
    enabled: bool
    max_repay_bps: uint256
    min_profit_bps: uint256

event TicketCreated:
    ticket_id: indexed(uint256)
    line_id: indexed(uint256)
    liquidator: indexed(address)
    max_repay: uint256

event TicketCancelled:
    ticket_id: indexed(uint256)
    liquidator: indexed(address)

event RouteExecuted:
    ticket_id: indexed(uint256)
    line_id: indexed(uint256)
    liquidator: indexed(address)
    repaid: uint256
    seized: uint256

asset: public(address)
core: public(address)
owner: public(address)
fee_recipient: public(address)
paused: public(bool)
ticket_count: public(uint256)

policy: public(RoutePolicy)
keepers: public(HashMap[address, bool])
tickets: public(HashMap[uint256, RouteTicket])
liquidator_ticket_count: public(HashMap[address, uint256])

@deploy
def __init__(_asset: address, _core: address, _fee_recipient: address):
    assert _asset != empty(address), "ASSET"
    assert _core != empty(address), "CORE"
    self.asset = _asset
    self.core = _core
    self.owner = msg.sender
    self.fee_recipient = _fee_recipient
    self.keepers[msg.sender] = True
    self.policy = RoutePolicy(
        enabled=True,
        max_repay_bps=MAX_REPAY_BPS,
        min_profit_bps=0,
        max_daily_routes=MAX_DAILY_ROUTES,
        keeper_fee_bps=25,
        daily_routes=0,
        day_index=block.timestamp // 86_400,
        total_routes=0,
        total_repaid=0,
        total_seized=0
    )

@internal
@view
def _authorized(account: address) -> bool:
    return account == self.owner or self.keepers[account]

@internal
def _roll_day():
    day_index: uint256 = block.timestamp // 86_400
    if self.policy.day_index != day_index:
        self.policy.day_index = day_index
        self.policy.daily_routes = 0

@internal
@view
def _profit_bps(repay: uint256, seize: uint256) -> uint256:
    if repay == 0 or seize <= repay:
        return 0
    return (seize - repay) * BPS // repay

@internal
@view
def _quote(line_id: uint256, max_repay: uint256, deadline: uint256) -> RouteQuote:
    borrower: address = empty(address)
    status: uint256 = 0
    limit: uint256 = 0
    principal: uint256 = 0
    interest: uint256 = 0
    minimum_due: uint256 = 0
    paid: uint256 = 0
    next_due: uint256 = 0
    collateral: uint256 = 0
    score: uint256 = 0
    borrower, status, limit, principal, interest, minimum_due, paid, next_due, collateral, score = staticcall IPyxisCore(self.core).get_line_summary(line_id)
    debt: uint256 = staticcall IPyxisCore(self.core).quote_debt(line_id)
    repay: uint256 = max_repay
    if repay > debt:
        repay = debt
    policy_max: uint256 = debt * self.policy.max_repay_bps // BPS
    if repay > policy_max:
        repay = policy_max
    seize: uint256 = 0
    repay, seize = staticcall IPyxisCore(self.core).quote_liquidation(line_id, repay)
    liquidatable: bool = staticcall IPyxisCore(self.core).can_liquidate(line_id)
    return RouteQuote(
        line_id=line_id,
        borrower=borrower,
        debt=debt,
        repay=repay,
        seize=seize,
        profit_bps=self._profit_bps(repay, seize),
        liquidatable=liquidatable,
        status=status,
        deadline_safe=deadline == 0 or deadline >= block.timestamp
    )

@external
def transfer_owner(new_owner: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_owner != empty(address), "OWNER_ZERO"
    old_owner: address = self.owner
    self.owner = new_owner
    self.keepers[new_owner] = True
    log OwnerChanged(old_owner=old_owner, new_owner=new_owner)

@external
def set_keeper(keeper: address, allowed: bool):
    assert msg.sender == self.owner, "OWNER"
    assert keeper != empty(address), "KEEPER"
    self.keepers[keeper] = allowed
    log KeeperChanged(keeper=keeper, allowed=allowed)

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner, "OWNER"
    self.paused = enabled

@external
def set_fee_recipient(recipient: address):
    assert msg.sender == self.owner, "OWNER"
    self.fee_recipient = recipient

@external
def set_policy(
    enabled: bool,
    max_repay_bps: uint256,
    min_profit_bps: uint256,
    max_daily_routes: uint256,
    keeper_fee_bps: uint256
):
    assert msg.sender == self.owner, "OWNER"
    assert max_repay_bps > 0 and max_repay_bps <= MAX_REPAY_BPS, "REPAY"
    assert max_daily_routes > 0 and max_daily_routes <= MAX_DAILY_ROUTES, "DAILY"
    assert keeper_fee_bps <= 1_000, "FEE"
    self.policy.enabled = enabled
    self.policy.max_repay_bps = max_repay_bps
    self.policy.min_profit_bps = min_profit_bps
    self.policy.max_daily_routes = max_daily_routes
    self.policy.keeper_fee_bps = keeper_fee_bps
    log PolicyUpdated(enabled=enabled, max_repay_bps=max_repay_bps, min_profit_bps=min_profit_bps)

@external
def create_ticket(line_id: uint256, max_repay: uint256, min_seize: uint256, deadline: uint256, metadata: bytes32) -> uint256:
    assert not self.paused, "PAUSED"
    assert self.policy.enabled, "DISABLED"
    assert max_repay > 0, "REPAY"
    assert deadline == 0 or deadline > block.timestamp, "DEADLINE"
    quote: RouteQuote = self._quote(line_id, max_repay, deadline)
    assert quote.liquidatable, "NOT_LIQUIDATABLE"
    assert quote.repay > 0, "ZERO_REPAY"
    assert quote.seize >= min_seize, "SEIZE"
    assert quote.profit_bps >= self.policy.min_profit_bps, "PROFIT"
    self.ticket_count += 1
    ticket_id: uint256 = self.ticket_count
    self.tickets[ticket_id] = RouteTicket(
        exists=True,
        line_id=line_id,
        liquidator=msg.sender,
        max_repay=max_repay,
        min_seize=min_seize,
        deadline=deadline,
        created_at=block.timestamp,
        executed_at=0,
        cancelled=False,
        metadata=metadata
    )
    self.liquidator_ticket_count[msg.sender] += 1
    log TicketCreated(ticket_id=ticket_id, line_id=line_id, liquidator=msg.sender, max_repay=max_repay)
    return ticket_id

@external
def cancel_ticket(ticket_id: uint256):
    assert self.tickets[ticket_id].exists, "TICKET"
    assert not self.tickets[ticket_id].cancelled, "CANCELLED"
    assert self.tickets[ticket_id].executed_at == 0, "EXECUTED"
    assert msg.sender == self.tickets[ticket_id].liquidator or self._authorized(msg.sender), "AUTH"
    self.tickets[ticket_id].cancelled = True
    log TicketCancelled(ticket_id=ticket_id, liquidator=self.tickets[ticket_id].liquidator)

@external
def execute_ticket(ticket_id: uint256):
    assert not self.paused, "PAUSED"
    assert self.policy.enabled, "DISABLED"
    assert self.tickets[ticket_id].exists, "TICKET"
    assert not self.tickets[ticket_id].cancelled, "CANCELLED"
    assert self.tickets[ticket_id].executed_at == 0, "EXECUTED"
    assert msg.sender == self.tickets[ticket_id].liquidator or self._authorized(msg.sender), "AUTH"
    deadline: uint256 = self.tickets[ticket_id].deadline
    assert deadline == 0 or deadline >= block.timestamp, "DEADLINE"
    self._roll_day()
    assert self.policy.daily_routes < self.policy.max_daily_routes, "DAILY"
    quote: RouteQuote = self._quote(self.tickets[ticket_id].line_id, self.tickets[ticket_id].max_repay, deadline)
    assert quote.liquidatable, "NOT_LIQUIDATABLE"
    assert quote.seize >= self.tickets[ticket_id].min_seize, "SEIZE"
    assert quote.profit_bps >= self.policy.min_profit_bps, "PROFIT"
    liquidator: address = self.tickets[ticket_id].liquidator
    before_balance: uint256 = staticcall IERC20(self.asset).balanceOf(self)
    assert extcall IERC20(self.asset).transferFrom(liquidator, self, quote.repay), "TRANSFER_FROM"
    assert extcall IERC20(self.asset).approve(self.core, quote.repay), "APPROVE"
    extcall IPyxisCore(self.core).liquidate(self.tickets[ticket_id].line_id, quote.repay)
    after_balance: uint256 = staticcall IERC20(self.asset).balanceOf(self)
    seized: uint256 = 0
    if after_balance > before_balance:
        seized = after_balance - before_balance
    fee: uint256 = seized * self.policy.keeper_fee_bps // BPS
    if fee > 0 and self.fee_recipient != empty(address):
        assert extcall IERC20(self.asset).transfer(self.fee_recipient, fee), "FEE"
    payout: uint256 = seized - fee
    if payout > 0:
        assert extcall IERC20(self.asset).transfer(liquidator, payout), "PAYOUT"
    self.tickets[ticket_id].executed_at = block.timestamp
    self.policy.daily_routes += 1
    self.policy.total_routes += 1
    self.policy.total_repaid += quote.repay
    self.policy.total_seized += seized
    log RouteExecuted(ticket_id=ticket_id, line_id=self.tickets[ticket_id].line_id, liquidator=liquidator, repaid=quote.repay, seized=seized)

@external
@view
def route_quote(line_id: uint256, max_repay: uint256, deadline: uint256) -> RouteQuote:
    return self._quote(line_id, max_repay, deadline)

@external
@view
def ticket_quote(ticket_id: uint256) -> RouteQuote:
    assert self.tickets[ticket_id].exists, "TICKET"
    return self._quote(self.tickets[ticket_id].line_id, self.tickets[ticket_id].max_repay, self.tickets[ticket_id].deadline)

@external
@view
def executable(ticket_id: uint256) -> bool:
    if not self.tickets[ticket_id].exists or self.tickets[ticket_id].cancelled:
        return False
    if self.tickets[ticket_id].executed_at != 0:
        return False
    if self.paused or not self.policy.enabled:
        return False
    deadline: uint256 = self.tickets[ticket_id].deadline
    if deadline != 0 and deadline < block.timestamp:
        return False
    quote: RouteQuote = self._quote(self.tickets[ticket_id].line_id, self.tickets[ticket_id].max_repay, deadline)
    return quote.liquidatable and quote.seize >= self.tickets[ticket_id].min_seize and quote.profit_bps >= self.policy.min_profit_bps

@external
@view
def daily_capacity() -> uint256:
    day_index: uint256 = block.timestamp // 86_400
    if day_index != self.policy.day_index:
        return self.policy.max_daily_routes
    if self.policy.daily_routes >= self.policy.max_daily_routes:
        return 0
    return self.policy.max_daily_routes - self.policy.daily_routes
