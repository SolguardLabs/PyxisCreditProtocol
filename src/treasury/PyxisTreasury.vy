# pragma version ^0.4.3

interface IERC20:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

BPS: constant(uint256) = 10_000
MAX_BUCKETS: constant(uint256) = 12
ROLE_NONE: constant(uint256) = 0
ROLE_OPERATOR: constant(uint256) = 1
ROLE_CONTROLLER: constant(uint256) = 2
ROLE_GUARDIAN: constant(uint256) = 3
BUCKET_RESERVE: constant(uint256) = 1
BUCKET_RECOVERY: constant(uint256) = 2
BUCKET_FEES: constant(uint256) = 3
BUCKET_BUFFER: constant(uint256) = 4

struct Bucket:
    exists: bool
    balance: uint256
    lifetime_inflow: uint256
    lifetime_outflow: uint256
    max_daily_outflow: uint256
    outflow_today: uint256
    day_index: uint256
    recipient: address
    paused: bool
    metadata: bytes32

struct RecoveryAccount:
    borrower: address
    line_id: uint256
    expected: uint256
    recovered: uint256
    written_off: uint256
    last_recovery_at: uint256
    collector: address
    closed: bool
    metadata: bytes32

struct TreasurySnapshot:
    asset_balance: uint256
    reserve_balance: uint256
    recovery_balance: uint256
    fee_balance: uint256
    buffer_balance: uint256
    total_inflow: uint256
    total_outflow: uint256
    total_recovered: uint256
    total_written_off: uint256
    configured_buckets: uint256

event OwnerChanged:
    old_owner: indexed(address)
    new_owner: indexed(address)

event RoleChanged:
    account: indexed(address)
    role: uint256

event BucketConfigured:
    bucket_id: indexed(uint256)
    recipient: indexed(address)
    max_daily_outflow: uint256

event BucketFunded:
    bucket_id: indexed(uint256)
    payer: indexed(address)
    amount: uint256

event BucketPaid:
    bucket_id: indexed(uint256)
    recipient: indexed(address)
    amount: uint256

event RecoveryOpened:
    line_id: indexed(uint256)
    borrower: indexed(address)
    expected: uint256

event RecoveryRecorded:
    line_id: indexed(uint256)
    collector: indexed(address)
    recovered: uint256

event WriteoffRecorded:
    line_id: indexed(uint256)
    amount: uint256

asset: public(address)
owner: public(address)
protocol: public(address)
guardian: public(address)
paused: public(bool)
bucket_count: public(uint256)
total_inflow: public(uint256)
total_outflow: public(uint256)
total_recovered: public(uint256)
total_written_off: public(uint256)

buckets: public(HashMap[uint256, Bucket])
roles: public(HashMap[address, uint256])
recovery_accounts: public(HashMap[uint256, RecoveryAccount])

@deploy
def __init__(_asset: address, _protocol: address, _guardian: address):
    assert _asset != empty(address), "ASSET"
    assert _protocol != empty(address), "PROTOCOL"
    self.asset = _asset
    self.protocol = _protocol
    self.owner = msg.sender
    self.guardian = _guardian
    self.roles[msg.sender] = ROLE_CONTROLLER
    if _guardian != empty(address):
        self.roles[_guardian] = ROLE_GUARDIAN
    self._configure_bucket(BUCKET_RESERVE, msg.sender, max_value(uint256), keccak256("RESERVE"))
    self._configure_bucket(BUCKET_RECOVERY, msg.sender, max_value(uint256), keccak256("RECOVERY"))
    self._configure_bucket(BUCKET_FEES, msg.sender, max_value(uint256), keccak256("FEES"))
    self._configure_bucket(BUCKET_BUFFER, msg.sender, max_value(uint256), keccak256("BUFFER"))

@internal
@view
def _is_controller(account: address) -> bool:
    return account == self.owner or self.roles[account] == ROLE_CONTROLLER

@internal
@view
def _is_operator(account: address) -> bool:
    return self._is_controller(account) or self.roles[account] == ROLE_OPERATOR

@internal
def _configure_bucket(bucket_id: uint256, recipient: address, max_daily_outflow: uint256, metadata: bytes32):
    if not self.buckets[bucket_id].exists:
        self.bucket_count += 1
    self.buckets[bucket_id].exists = True
    self.buckets[bucket_id].recipient = recipient
    self.buckets[bucket_id].max_daily_outflow = max_daily_outflow
    self.buckets[bucket_id].metadata = metadata
    self.buckets[bucket_id].day_index = block.timestamp // 86_400
    log BucketConfigured(bucket_id=bucket_id, recipient=recipient, max_daily_outflow=max_daily_outflow)

@internal
def _roll_day(bucket_id: uint256):
    day_index: uint256 = block.timestamp // 86_400
    if self.buckets[bucket_id].day_index != day_index:
        self.buckets[bucket_id].day_index = day_index
        self.buckets[bucket_id].outflow_today = 0

@internal
def _debit_bucket(bucket_id: uint256, amount: uint256):
    assert self.buckets[bucket_id].exists, "BUCKET"
    assert not self.buckets[bucket_id].paused, "BUCKET_PAUSED"
    assert self.buckets[bucket_id].balance >= amount, "BALANCE"
    self._roll_day(bucket_id)
    assert self.buckets[bucket_id].outflow_today + amount <= self.buckets[bucket_id].max_daily_outflow, "DAILY"
    self.buckets[bucket_id].balance -= amount
    self.buckets[bucket_id].lifetime_outflow += amount
    self.buckets[bucket_id].outflow_today += amount
    self.total_outflow += amount

@internal
def _credit_bucket(bucket_id: uint256, amount: uint256):
    assert self.buckets[bucket_id].exists, "BUCKET"
    self.buckets[bucket_id].balance += amount
    self.buckets[bucket_id].lifetime_inflow += amount
    self.total_inflow += amount

@external
def transfer_owner(new_owner: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_owner != empty(address), "OWNER_ZERO"
    old_owner: address = self.owner
    self.owner = new_owner
    self.roles[new_owner] = ROLE_CONTROLLER
    log OwnerChanged(old_owner=old_owner, new_owner=new_owner)

@external
def set_role(account: address, role: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert account != empty(address), "ACCOUNT"
    assert role <= ROLE_GUARDIAN, "ROLE"
    self.roles[account] = role
    log RoleChanged(account=account, role=role)

@external
def set_protocol(new_protocol: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_protocol != empty(address), "PROTOCOL"
    self.protocol = new_protocol

@external
def set_guardian(new_guardian: address):
    assert msg.sender == self.owner, "OWNER"
    self.guardian = new_guardian
    if new_guardian != empty(address):
        self.roles[new_guardian] = ROLE_GUARDIAN

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner or msg.sender == self.guardian, "AUTH"
    self.paused = enabled

@external
def configure_bucket(bucket_id: uint256, recipient: address, max_daily_outflow: uint256, metadata: bytes32):
    assert self._is_controller(msg.sender), "AUTH"
    assert bucket_id > 0 and bucket_id <= MAX_BUCKETS, "BUCKET"
    assert recipient != empty(address), "RECIPIENT"
    self._configure_bucket(bucket_id, recipient, max_daily_outflow, metadata)

@external
def set_bucket_paused(bucket_id: uint256, enabled: bool):
    assert self._is_controller(msg.sender) or msg.sender == self.guardian, "AUTH"
    assert self.buckets[bucket_id].exists, "BUCKET"
    self.buckets[bucket_id].paused = enabled

@external
def fund_bucket(bucket_id: uint256, amount: uint256):
    assert not self.paused, "PAUSED"
    assert amount > 0, "AMOUNT"
    assert self.buckets[bucket_id].exists, "BUCKET"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self._credit_bucket(bucket_id, amount)
    log BucketFunded(bucket_id=bucket_id, payer=msg.sender, amount=amount)

@external
def move_between_buckets(source_bucket: uint256, target_bucket: uint256, amount: uint256):
    assert self._is_operator(msg.sender), "AUTH"
    assert amount > 0, "AMOUNT"
    assert source_bucket != target_bucket, "SAME"
    self._debit_bucket(source_bucket, amount)
    self._credit_bucket(target_bucket, amount)

@external
def pay_from_bucket(bucket_id: uint256, recipient: address, amount: uint256):
    assert not self.paused, "PAUSED"
    assert self._is_operator(msg.sender), "AUTH"
    assert recipient != empty(address), "RECIPIENT"
    assert amount > 0, "AMOUNT"
    self._debit_bucket(bucket_id, amount)
    assert extcall IERC20(self.asset).transfer(recipient, amount), "TRANSFER"
    log BucketPaid(bucket_id=bucket_id, recipient=recipient, amount=amount)

@external
def sweep_bucket(bucket_id: uint256):
    assert not self.paused, "PAUSED"
    assert self._is_controller(msg.sender), "AUTH"
    assert self.buckets[bucket_id].exists, "BUCKET"
    recipient: address = self.buckets[bucket_id].recipient
    assert recipient != empty(address), "RECIPIENT"
    amount: uint256 = self.buckets[bucket_id].balance
    assert amount > 0, "AMOUNT"
    self._debit_bucket(bucket_id, amount)
    assert extcall IERC20(self.asset).transfer(recipient, amount), "TRANSFER"
    log BucketPaid(bucket_id=bucket_id, recipient=recipient, amount=amount)

@external
def open_recovery(line_id: uint256, borrower: address, expected: uint256, collector: address, metadata: bytes32):
    assert self._is_operator(msg.sender) or msg.sender == self.protocol, "AUTH"
    assert line_id > 0, "LINE"
    assert borrower != empty(address), "BORROWER"
    assert expected > 0, "EXPECTED"
    self.recovery_accounts[line_id] = RecoveryAccount(
        borrower=borrower,
        line_id=line_id,
        expected=expected,
        recovered=0,
        written_off=0,
        last_recovery_at=0,
        collector=collector,
        closed=False,
        metadata=metadata
    )
    log RecoveryOpened(line_id=line_id, borrower=borrower, expected=expected)

@external
def record_recovery(line_id: uint256, amount: uint256):
    assert not self.paused, "PAUSED"
    assert amount > 0, "AMOUNT"
    account: RecoveryAccount = self.recovery_accounts[line_id]
    assert account.line_id != 0, "RECOVERY"
    assert not account.closed, "CLOSED"
    assert msg.sender == account.collector or self._is_operator(msg.sender), "AUTH"
    assert extcall IERC20(self.asset).transferFrom(msg.sender, self, amount), "TRANSFER_FROM"
    self.recovery_accounts[line_id].recovered += amount
    self.recovery_accounts[line_id].last_recovery_at = block.timestamp
    self.total_recovered += amount
    self._credit_bucket(BUCKET_RECOVERY, amount)
    if self.recovery_accounts[line_id].recovered + self.recovery_accounts[line_id].written_off >= self.recovery_accounts[line_id].expected:
        self.recovery_accounts[line_id].closed = True
    log RecoveryRecorded(line_id=line_id, collector=msg.sender, recovered=amount)

@external
def record_writeoff(line_id: uint256, amount: uint256):
    assert self._is_controller(msg.sender), "AUTH"
    assert amount > 0, "AMOUNT"
    assert self.recovery_accounts[line_id].line_id != 0, "RECOVERY"
    assert not self.recovery_accounts[line_id].closed, "CLOSED"
    self.recovery_accounts[line_id].written_off += amount
    self.total_written_off += amount
    if self.recovery_accounts[line_id].recovered + self.recovery_accounts[line_id].written_off >= self.recovery_accounts[line_id].expected:
        self.recovery_accounts[line_id].closed = True
    log WriteoffRecorded(line_id=line_id, amount=amount)

@external
def close_recovery(line_id: uint256):
    assert self._is_controller(msg.sender), "AUTH"
    assert self.recovery_accounts[line_id].line_id != 0, "RECOVERY"
    self.recovery_accounts[line_id].closed = True

@external
@view
def bucket_available(bucket_id: uint256) -> uint256:
    if not self.buckets[bucket_id].exists or self.buckets[bucket_id].paused:
        return 0
    day_index: uint256 = block.timestamp // 86_400
    if day_index != self.buckets[bucket_id].day_index:
        if self.buckets[bucket_id].balance < self.buckets[bucket_id].max_daily_outflow:
            return self.buckets[bucket_id].balance
        return self.buckets[bucket_id].max_daily_outflow
    remaining_day: uint256 = 0
    if self.buckets[bucket_id].max_daily_outflow > self.buckets[bucket_id].outflow_today:
        remaining_day = self.buckets[bucket_id].max_daily_outflow - self.buckets[bucket_id].outflow_today
    if self.buckets[bucket_id].balance < remaining_day:
        return self.buckets[bucket_id].balance
    return remaining_day

@external
@view
def recovery_remaining(line_id: uint256) -> uint256:
    expected: uint256 = self.recovery_accounts[line_id].expected
    accounted: uint256 = self.recovery_accounts[line_id].recovered + self.recovery_accounts[line_id].written_off
    if accounted >= expected:
        return 0
    return expected - accounted

@external
@view
def asset_balance() -> uint256:
    return staticcall IERC20(self.asset).balanceOf(self)

@external
@view
def snapshot() -> TreasurySnapshot:
    return TreasurySnapshot(
        asset_balance=staticcall IERC20(self.asset).balanceOf(self),
        reserve_balance=self.buckets[BUCKET_RESERVE].balance,
        recovery_balance=self.buckets[BUCKET_RECOVERY].balance,
        fee_balance=self.buckets[BUCKET_FEES].balance,
        buffer_balance=self.buckets[BUCKET_BUFFER].balance,
        total_inflow=self.total_inflow,
        total_outflow=self.total_outflow,
        total_recovered=self.total_recovered,
        total_written_off=self.total_written_off,
        configured_buckets=self.bucket_count
    )
