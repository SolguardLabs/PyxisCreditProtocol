# pragma version ^0.4.3

interface IPyxisCoreAdmin:
    def set_reserve_factor(new_value: uint256): nonpayable
    def set_minimum_collateral(new_value: uint256): nonpayable
    def set_global_line_limit(new_value: uint256): nonpayable
    def set_global_borrower_limit(new_value: uint256): nonpayable
    def set_liquidation_discount(new_value: uint256): nonpayable
    def set_keeper_reward(new_value: uint256): nonpayable
    def set_paused(enabled: bool): nonpayable
    def set_keeper(account: address, allowed: bool): nonpayable
    def set_controller(account: address, allowed: bool): nonpayable

BPS: constant(uint256) = 10_000
MIN_DELAY: constant(uint256) = 6 * 60 * 60
MAX_DELAY: constant(uint256) = 14 * 24 * 60 * 60
MAX_ACTIONS: constant(uint256) = 10_000
ACTION_NONE: constant(uint256) = 0
ACTION_RESERVE_FACTOR: constant(uint256) = 1
ACTION_MIN_COLLATERAL: constant(uint256) = 2
ACTION_GLOBAL_LINE_LIMIT: constant(uint256) = 3
ACTION_GLOBAL_BORROWER_LIMIT: constant(uint256) = 4
ACTION_LIQUIDATION_DISCOUNT: constant(uint256) = 5
ACTION_KEEPER_REWARD: constant(uint256) = 6
ACTION_PAUSE: constant(uint256) = 7
ACTION_KEEPER: constant(uint256) = 8
ACTION_CONTROLLER: constant(uint256) = 9
STATUS_PENDING: constant(uint256) = 1
STATUS_EXECUTED: constant(uint256) = 2
STATUS_CANCELLED: constant(uint256) = 3

struct Action:
    exists: bool
    action_type: uint256
    target: address
    account: address
    numeric_value: uint256
    boolean_value: bool
    eta: uint256
    created_at: uint256
    executed_at: uint256
    cancelled_at: uint256
    proposer: address
    executor: address
    reason: bytes32
    status: uint256

struct GuardianState:
    allowed: bool
    veto_count: uint256
    last_veto_at: uint256
    metadata: bytes32

struct ConfigSnapshot:
    core: address
    owner: address
    delay: uint256
    action_count: uint256
    pending_count: uint256
    executed_count: uint256
    cancelled_count: uint256
    guardians: uint256
    paused: bool

event OwnerChanged:
    old_owner: indexed(address)
    new_owner: indexed(address)

event CoreChanged:
    old_core: indexed(address)
    new_core: indexed(address)

event GuardianChanged:
    guardian: indexed(address)
    allowed: bool

event DelayChanged:
    old_delay: uint256
    new_delay: uint256

event ActionQueued:
    action_id: indexed(uint256)
    action_type: uint256
    eta: uint256
    proposer: indexed(address)

event ActionExecuted:
    action_id: indexed(uint256)
    executor: indexed(address)

event ActionCancelled:
    action_id: indexed(uint256)
    guardian: indexed(address)
    reason: bytes32

owner: public(address)
core: public(address)
delay: public(uint256)
paused: public(bool)
action_count: public(uint256)
pending_count: public(uint256)
executed_count: public(uint256)
cancelled_count: public(uint256)
guardian_count: public(uint256)

actions: public(HashMap[uint256, Action])
guardians: public(HashMap[address, GuardianState])
proposer_nonces: public(HashMap[address, uint256])

@deploy
def __init__(_core: address, _delay: uint256):
    assert _core != empty(address), "CORE"
    assert _delay >= MIN_DELAY and _delay <= MAX_DELAY, "DELAY"
    self.owner = msg.sender
    self.core = _core
    self.delay = _delay
    self.guardians[msg.sender] = GuardianState(allowed=True, veto_count=0, last_veto_at=0, metadata=keccak256("OWNER"))
    self.guardian_count = 1

@internal
@view
def _can_propose(account: address) -> bool:
    return account == self.owner or self.guardians[account].allowed

@internal
@view
def _can_cancel(account: address) -> bool:
    return account == self.owner or self.guardians[account].allowed

@internal
@view
def _valid_action_type(action_type: uint256) -> bool:
    return action_type >= ACTION_RESERVE_FACTOR and action_type <= ACTION_CONTROLLER

@internal
@view
def _ready(action_id: uint256) -> bool:
    if not self.actions[action_id].exists:
        return False
    if self.actions[action_id].status != STATUS_PENDING:
        return False
    return block.timestamp >= self.actions[action_id].eta

@internal
def _queue(
    action_type: uint256,
    target: address,
    account: address,
    numeric_value: uint256,
    boolean_value: bool,
    reason: bytes32
) -> uint256:
    assert not self.paused, "PAUSED"
    assert self._can_propose(msg.sender), "PROPOSER"
    assert self._valid_action_type(action_type), "ACTION"
    assert self.action_count < MAX_ACTIONS, "MAX_ACTIONS"
    self.action_count += 1
    action_id: uint256 = self.action_count
    eta: uint256 = block.timestamp + self.delay
    self.actions[action_id] = Action(
        exists=True,
        action_type=action_type,
        target=target,
        account=account,
        numeric_value=numeric_value,
        boolean_value=boolean_value,
        eta=eta,
        created_at=block.timestamp,
        executed_at=0,
        cancelled_at=0,
        proposer=msg.sender,
        executor=empty(address),
        reason=reason,
        status=STATUS_PENDING
    )
    self.pending_count += 1
    self.proposer_nonces[msg.sender] += 1
    log ActionQueued(action_id=action_id, action_type=action_type, eta=eta, proposer=msg.sender)
    return action_id

@internal
def _execute_core_action(action_id: uint256):
    action: Action = self.actions[action_id]
    target: address = self.core
    if action.target != empty(address):
        target = action.target
    if action.action_type == ACTION_RESERVE_FACTOR:
        extcall IPyxisCoreAdmin(target).set_reserve_factor(action.numeric_value)
    elif action.action_type == ACTION_MIN_COLLATERAL:
        extcall IPyxisCoreAdmin(target).set_minimum_collateral(action.numeric_value)
    elif action.action_type == ACTION_GLOBAL_LINE_LIMIT:
        extcall IPyxisCoreAdmin(target).set_global_line_limit(action.numeric_value)
    elif action.action_type == ACTION_GLOBAL_BORROWER_LIMIT:
        extcall IPyxisCoreAdmin(target).set_global_borrower_limit(action.numeric_value)
    elif action.action_type == ACTION_LIQUIDATION_DISCOUNT:
        extcall IPyxisCoreAdmin(target).set_liquidation_discount(action.numeric_value)
    elif action.action_type == ACTION_KEEPER_REWARD:
        extcall IPyxisCoreAdmin(target).set_keeper_reward(action.numeric_value)
    elif action.action_type == ACTION_PAUSE:
        extcall IPyxisCoreAdmin(target).set_paused(action.boolean_value)
    elif action.action_type == ACTION_KEEPER:
        extcall IPyxisCoreAdmin(target).set_keeper(action.account, action.boolean_value)
    elif action.action_type == ACTION_CONTROLLER:
        extcall IPyxisCoreAdmin(target).set_controller(action.account, action.boolean_value)
    else:
        raise "ACTION"

@external
def transfer_owner(new_owner: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_owner != empty(address), "OWNER_ZERO"
    old_owner: address = self.owner
    self.owner = new_owner
    if not self.guardians[new_owner].allowed:
        self.guardian_count += 1
    self.guardians[new_owner].allowed = True
    log OwnerChanged(old_owner=old_owner, new_owner=new_owner)

@external
def set_core(new_core: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_core != empty(address), "CORE"
    old_core: address = self.core
    self.core = new_core
    log CoreChanged(old_core=old_core, new_core=new_core)

@external
def set_delay(new_delay: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_delay >= MIN_DELAY and new_delay <= MAX_DELAY, "DELAY"
    old_delay: uint256 = self.delay
    self.delay = new_delay
    log DelayChanged(old_delay=old_delay, new_delay=new_delay)

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner, "OWNER"
    self.paused = enabled

@external
def set_guardian(guardian: address, allowed: bool, metadata: bytes32):
    assert msg.sender == self.owner, "OWNER"
    assert guardian != empty(address), "GUARDIAN"
    if allowed and not self.guardians[guardian].allowed:
        self.guardian_count += 1
    if not allowed and self.guardians[guardian].allowed and self.guardian_count > 0:
        self.guardian_count -= 1
    self.guardians[guardian].allowed = allowed
    self.guardians[guardian].metadata = metadata
    log GuardianChanged(guardian=guardian, allowed=allowed)

@external
def queue_numeric(action_type: uint256, numeric_value: uint256, reason: bytes32) -> uint256:
    return self._queue(action_type, empty(address), empty(address), numeric_value, False, reason)

@external
def queue_numeric_for_target(action_type: uint256, target: address, numeric_value: uint256, reason: bytes32) -> uint256:
    assert target != empty(address), "TARGET"
    return self._queue(action_type, target, empty(address), numeric_value, False, reason)

@external
def queue_boolean(action_type: uint256, enabled: bool, reason: bytes32) -> uint256:
    assert action_type == ACTION_PAUSE, "ACTION"
    return self._queue(action_type, empty(address), empty(address), 0, enabled, reason)

@external
def queue_role(action_type: uint256, account: address, allowed: bool, reason: bytes32) -> uint256:
    assert action_type == ACTION_KEEPER or action_type == ACTION_CONTROLLER, "ACTION"
    assert account != empty(address), "ACCOUNT"
    return self._queue(action_type, empty(address), account, 0, allowed, reason)

@external
def cancel_action(action_id: uint256, reason: bytes32):
    assert self._can_cancel(msg.sender), "AUTH"
    assert self.actions[action_id].exists, "ACTION"
    assert self.actions[action_id].status == STATUS_PENDING, "STATUS"
    self.actions[action_id].status = STATUS_CANCELLED
    self.actions[action_id].cancelled_at = block.timestamp
    if self.pending_count > 0:
        self.pending_count -= 1
    self.cancelled_count += 1
    if self.guardians[msg.sender].allowed:
        self.guardians[msg.sender].veto_count += 1
        self.guardians[msg.sender].last_veto_at = block.timestamp
    log ActionCancelled(action_id=action_id, guardian=msg.sender, reason=reason)

@external
def execute_action(action_id: uint256):
    assert not self.paused, "PAUSED"
    assert self._ready(action_id), "NOT_READY"
    self._execute_core_action(action_id)
    self.actions[action_id].status = STATUS_EXECUTED
    self.actions[action_id].executed_at = block.timestamp
    self.actions[action_id].executor = msg.sender
    if self.pending_count > 0:
        self.pending_count -= 1
    self.executed_count += 1
    log ActionExecuted(action_id=action_id, executor=msg.sender)

@external
def emergency_cancel_many(a: uint256, b: uint256, c: uint256, d: uint256):
    assert self._can_cancel(msg.sender), "AUTH"
    if a != 0 and self.actions[a].status == STATUS_PENDING:
        self.actions[a].status = STATUS_CANCELLED
        self.actions[a].cancelled_at = block.timestamp
        self.cancelled_count += 1
        if self.pending_count > 0:
            self.pending_count -= 1
        log ActionCancelled(action_id=a, guardian=msg.sender, reason=keccak256("EMERGENCY_BATCH"))
    if b != 0 and self.actions[b].status == STATUS_PENDING:
        self.actions[b].status = STATUS_CANCELLED
        self.actions[b].cancelled_at = block.timestamp
        self.cancelled_count += 1
        if self.pending_count > 0:
            self.pending_count -= 1
        log ActionCancelled(action_id=b, guardian=msg.sender, reason=keccak256("EMERGENCY_BATCH"))
    if c != 0 and self.actions[c].status == STATUS_PENDING:
        self.actions[c].status = STATUS_CANCELLED
        self.actions[c].cancelled_at = block.timestamp
        self.cancelled_count += 1
        if self.pending_count > 0:
            self.pending_count -= 1
        log ActionCancelled(action_id=c, guardian=msg.sender, reason=keccak256("EMERGENCY_BATCH"))
    if d != 0 and self.actions[d].status == STATUS_PENDING:
        self.actions[d].status = STATUS_CANCELLED
        self.actions[d].cancelled_at = block.timestamp
        self.cancelled_count += 1
        if self.pending_count > 0:
            self.pending_count -= 1
        log ActionCancelled(action_id=d, guardian=msg.sender, reason=keccak256("EMERGENCY_BATCH"))

@external
@view
def ready_at(action_id: uint256) -> uint256:
    if not self.actions[action_id].exists:
        return 0
    return self.actions[action_id].eta

@external
@view
def is_ready(action_id: uint256) -> bool:
    return self._ready(action_id)

@external
@view
def action_digest(action_id: uint256) -> bytes32:
    action: Action = self.actions[action_id]
    return keccak256(
        concat(
            convert(action.action_type, bytes32),
            convert(action.target, bytes32),
            convert(action.account, bytes32),
            convert(action.numeric_value, bytes32),
            convert(action.boolean_value, bytes32),
            action.reason
        )
    )

@external
@view
def action_status(action_id: uint256) -> (bool, uint256, uint256, uint256, address):
    action: Action = self.actions[action_id]
    return (
        action.exists,
        action.status,
        action.action_type,
        action.eta,
        action.proposer
    )

@external
@view
def action_payload(action_id: uint256) -> (address, address, uint256, bool, bytes32):
    action: Action = self.actions[action_id]
    return (
        action.target,
        action.account,
        action.numeric_value,
        action.boolean_value,
        action.reason
    )

@external
@view
def guardian_summary(guardian: address) -> (bool, uint256, uint256, bytes32):
    state: GuardianState = self.guardians[guardian]
    return (
        state.allowed,
        state.veto_count,
        state.last_veto_at,
        state.metadata
    )

@external
@view
def can_propose(account: address) -> bool:
    return self._can_propose(account)

@external
@view
def can_cancel(account: address) -> bool:
    return self._can_cancel(account)

@external
@view
def pending_ratio_bps() -> uint256:
    if self.action_count == 0:
        return 0
    return self.pending_count * BPS // self.action_count

@external
@view
def snapshot() -> ConfigSnapshot:
    return ConfigSnapshot(
        core=self.core,
        owner=self.owner,
        delay=self.delay,
        action_count=self.action_count,
        pending_count=self.pending_count,
        executed_count=self.executed_count,
        cancelled_count=self.cancelled_count,
        guardians=self.guardian_count,
        paused=self.paused
    )
