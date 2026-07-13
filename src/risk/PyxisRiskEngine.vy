# pragma version ^0.4.3

BPS: constant(uint256) = 10_000
MAX_SCORE: constant(uint256) = 10_000
MAX_APR: constant(uint256) = 6_000
MAX_SECTOR: constant(uint256) = 32
GRADE_A: constant(uint256) = 1
GRADE_B: constant(uint256) = 2
GRADE_C: constant(uint256) = 3
GRADE_D: constant(uint256) = 4
GRADE_WATCH: constant(uint256) = 5
STATUS_EMPTY: constant(uint256) = 0
STATUS_ACTIVE: constant(uint256) = 1
STATUS_WATCH: constant(uint256) = 2
STATUS_RESTRICTED: constant(uint256) = 3
STATUS_SUSPENDED: constant(uint256) = 4

struct BorrowerProfile:
    exists: bool
    borrower: address
    sector_id: uint256
    grade: uint256
    status: uint256
    base_limit: uint256
    maximum_limit: uint256
    outstanding: uint256
    committed_limit: uint256
    collateral_posted: uint256
    trailing_revenue: uint256
    cash_balance: uint256
    liabilities: uint256
    liquidity_score: uint256
    leverage_score: uint256
    payment_score: uint256
    covenant_score: uint256
    operator_score: uint256
    last_review_at: uint256
    next_review_at: uint256
    stale_after: uint256
    watchlist_reason: bytes32
    metadata: bytes32

struct SectorPolicy:
    exists: bool
    sector_id: uint256
    limit_cap: uint256
    outstanding_cap: uint256
    min_collateral_bps: uint256
    max_apr_bps: uint256
    max_tenor: uint256
    review_interval: uint256
    open_commitments: uint256
    active_outstanding: uint256
    defaulted_outstanding: uint256
    risk_weight_bps: uint256
    paused: bool
    metadata: bytes32

struct CovenantPack:
    min_cash_bps: uint256
    max_leverage_bps: uint256
    min_payment_score: uint256
    min_operator_score: uint256
    max_outstanding_bps: uint256
    collateral_buffer_bps: uint256
    review_grace: uint256
    enabled: bool

struct Assessment:
    allowed: bool
    grade: uint256
    max_limit: uint256
    apr_bps: uint256
    min_collateral_bps: uint256
    risk_weight_bps: uint256
    reason: bytes32

event OwnerChanged:
    old_owner: indexed(address)
    new_owner: indexed(address)

event OperatorChanged:
    operator: indexed(address)
    allowed: bool

event ProfileUpdated:
    borrower: indexed(address)
    grade: uint256
    status: uint256
    limit: uint256

event SectorPolicyUpdated:
    sector_id: indexed(uint256)
    limit_cap: uint256
    outstanding_cap: uint256

event CovenantUpdated:
    borrower: indexed(address)
    enabled: bool
    min_payment_score: uint256

event ExposureRecorded:
    borrower: indexed(address)
    principal: uint256
    committed: uint256

event WatchlistChanged:
    borrower: indexed(address)
    status: uint256
    reason: bytes32

owner: public(address)
protocol: public(address)
default_review_interval: public(uint256)
default_stale_after: public(uint256)
global_commitment_cap: public(uint256)
global_outstanding_cap: public(uint256)
global_commitments: public(uint256)
global_outstanding: public(uint256)
global_defaulted: public(uint256)
paused: public(bool)

profiles: public(HashMap[address, BorrowerProfile])
sector_policies: public(HashMap[uint256, SectorPolicy])
covenants: public(HashMap[address, CovenantPack])
operators: public(HashMap[address, bool])
sector_count: public(uint256)
profile_count: public(uint256)

@deploy
def __init__(_protocol: address):
    self.owner = msg.sender
    self.protocol = _protocol
    self.default_review_interval = 30 * 24 * 60 * 60
    self.default_stale_after = 45 * 24 * 60 * 60
    self.global_commitment_cap = max_value(uint256)
    self.global_outstanding_cap = max_value(uint256)
    self.operators[msg.sender] = True

@internal
@view
def _is_operator(account: address) -> bool:
    return account == self.owner or self.operators[account]

@internal
@view
def _grade_from_score(score: uint256) -> uint256:
    if score >= 8_500:
        return GRADE_A
    if score >= 7_000:
        return GRADE_B
    if score >= 5_500:
        return GRADE_C
    if score >= 4_000:
        return GRADE_D
    return GRADE_WATCH

@internal
@view
def _apr_for_grade(grade: uint256, sector_id: uint256) -> uint256:
    cap: uint256 = self.sector_policies[sector_id].max_apr_bps
    if cap == 0:
        cap = MAX_APR
    base: uint256 = 650
    if grade == GRADE_A:
        base = 700
    elif grade == GRADE_B:
        base = 1_050
    elif grade == GRADE_C:
        base = 1_650
    elif grade == GRADE_D:
        base = 2_500
    else:
        base = 3_500
    if base > cap:
        return cap
    return base

@internal
@view
def _weighted_score(borrower: address) -> uint256:
    profile: BorrowerProfile = self.profiles[borrower]
    liquidity: uint256 = profile.liquidity_score * 25 // 100
    leverage: uint256 = profile.leverage_score * 25 // 100
    payment: uint256 = profile.payment_score * 30 // 100
    covenant: uint256 = profile.covenant_score * 10 // 100
    operator: uint256 = profile.operator_score * 10 // 100
    return liquidity + leverage + payment + covenant + operator

@internal
@view
def _cash_ratio_bps(borrower: address) -> uint256:
    liabilities: uint256 = self.profiles[borrower].liabilities
    if liabilities == 0:
        return BPS
    cash: uint256 = self.profiles[borrower].cash_balance
    if cash >= liabilities:
        return BPS
    return cash * BPS // liabilities

@internal
@view
def _leverage_bps(borrower: address) -> uint256:
    revenue: uint256 = self.profiles[borrower].trailing_revenue
    if revenue == 0:
        return max_value(uint256)
    liabilities: uint256 = self.profiles[borrower].liabilities + self.profiles[borrower].outstanding
    return liabilities * BPS // revenue

@internal
@view
def _outstanding_bps(borrower: address) -> uint256:
    maximum: uint256 = self.profiles[borrower].maximum_limit
    if maximum == 0:
        return 0
    return self.profiles[borrower].outstanding * BPS // maximum

@internal
@view
def _collateral_bps(borrower: address) -> uint256:
    outstanding: uint256 = self.profiles[borrower].outstanding
    if outstanding == 0:
        return BPS
    collateral: uint256 = self.profiles[borrower].collateral_posted
    return collateral * BPS // outstanding

@internal
@view
def _profile_is_stale(borrower: address) -> bool:
    profile: BorrowerProfile = self.profiles[borrower]
    if not profile.exists:
        return True
    if profile.stale_after == 0:
        return False
    return block.timestamp > profile.stale_after

@internal
@view
def _available_limit(borrower: address) -> uint256:
    if not self.profiles[borrower].exists:
        return 0
    maximum: uint256 = self.profiles[borrower].maximum_limit
    committed: uint256 = self.profiles[borrower].committed_limit
    if committed >= maximum:
        return 0
    return maximum - committed

@internal
@view
def _sector_available(sector_id: uint256, requested_limit: uint256) -> bool:
    policy: SectorPolicy = self.sector_policies[sector_id]
    if not policy.exists or policy.paused:
        return False
    if policy.limit_cap > 0 and policy.open_commitments + requested_limit > policy.limit_cap:
        return False
    if policy.outstanding_cap > 0 and policy.active_outstanding > policy.outstanding_cap:
        return False
    return True

@internal
@view
def _covenants_clear(borrower: address, requested_limit: uint256) -> bool:
    pack: CovenantPack = self.covenants[borrower]
    if not pack.enabled:
        return True
    if self._cash_ratio_bps(borrower) < pack.min_cash_bps:
        return False
    if self._leverage_bps(borrower) > pack.max_leverage_bps:
        return False
    if self.profiles[borrower].payment_score < pack.min_payment_score:
        return False
    if self.profiles[borrower].operator_score < pack.min_operator_score:
        return False
    projected: uint256 = self.profiles[borrower].outstanding + requested_limit
    maximum: uint256 = self.profiles[borrower].maximum_limit
    if maximum > 0 and projected * BPS // maximum > pack.max_outstanding_bps:
        return False
    return True

@internal
@view
def _assessment_reason(borrower: address, requested_limit: uint256) -> bytes32:
    profile: BorrowerProfile = self.profiles[borrower]
    if self.paused:
        return keccak256("PAUSED")
    if not profile.exists:
        return keccak256("NO_PROFILE")
    if profile.status == STATUS_SUSPENDED:
        return keccak256("SUSPENDED")
    if profile.status == STATUS_RESTRICTED:
        return keccak256("RESTRICTED")
    if self._profile_is_stale(borrower):
        return keccak256("STALE_PROFILE")
    if not self._sector_available(profile.sector_id, requested_limit):
        return keccak256("SECTOR_LIMIT")
    if not self._covenants_clear(borrower, requested_limit):
        return keccak256("COVENANT")
    if self.global_commitments + requested_limit > self.global_commitment_cap:
        return keccak256("GLOBAL_COMMITMENT")
    if self.global_outstanding > self.global_outstanding_cap:
        return keccak256("GLOBAL_OUTSTANDING")
    if requested_limit > self._available_limit(borrower):
        return keccak256("BORROWER_LIMIT")
    return empty(bytes32)

@external
def transfer_owner(new_owner: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_owner != empty(address), "OWNER_ZERO"
    old_owner: address = self.owner
    self.owner = new_owner
    self.operators[new_owner] = True
    log OwnerChanged(old_owner=old_owner, new_owner=new_owner)

@external
def set_operator(operator: address, allowed: bool):
    assert msg.sender == self.owner, "OWNER"
    assert operator != empty(address), "OPERATOR"
    self.operators[operator] = allowed
    log OperatorChanged(operator=operator, allowed=allowed)

@external
def set_protocol(new_protocol: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_protocol != empty(address), "PROTOCOL"
    self.protocol = new_protocol

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner, "OWNER"
    self.paused = enabled

@external
def set_global_caps(commitment_cap: uint256, outstanding_cap: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert commitment_cap > 0, "COMMITMENT"
    assert outstanding_cap > 0, "OUTSTANDING"
    self.global_commitment_cap = commitment_cap
    self.global_outstanding_cap = outstanding_cap

@external
def set_default_reviews(review_interval: uint256, stale_after_delta: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert review_interval >= 1 * 24 * 60 * 60, "REVIEW"
    assert stale_after_delta >= review_interval, "STALE"
    self.default_review_interval = review_interval
    self.default_stale_after = stale_after_delta

@external
def configure_sector(
    sector_id: uint256,
    limit_cap: uint256,
    outstanding_cap: uint256,
    min_collateral_bps: uint256,
    max_apr_bps: uint256,
    max_tenor: uint256,
    risk_weight_bps: uint256,
    metadata: bytes32
):
    assert self._is_operator(msg.sender), "AUTH"
    assert sector_id > 0 and sector_id <= MAX_SECTOR, "SECTOR"
    assert max_apr_bps <= MAX_APR, "APR"
    assert min_collateral_bps <= 20_000, "COLLATERAL"
    assert risk_weight_bps >= BPS and risk_weight_bps <= 25_000, "RISK"
    if not self.sector_policies[sector_id].exists:
        self.sector_count += 1
    self.sector_policies[sector_id].exists = True
    self.sector_policies[sector_id].sector_id = sector_id
    self.sector_policies[sector_id].limit_cap = limit_cap
    self.sector_policies[sector_id].outstanding_cap = outstanding_cap
    self.sector_policies[sector_id].min_collateral_bps = min_collateral_bps
    self.sector_policies[sector_id].max_apr_bps = max_apr_bps
    self.sector_policies[sector_id].max_tenor = max_tenor
    self.sector_policies[sector_id].review_interval = self.default_review_interval
    self.sector_policies[sector_id].risk_weight_bps = risk_weight_bps
    self.sector_policies[sector_id].metadata = metadata
    log SectorPolicyUpdated(sector_id=sector_id, limit_cap=limit_cap, outstanding_cap=outstanding_cap)

@external
def pause_sector(sector_id: uint256, enabled: bool):
    assert self._is_operator(msg.sender), "AUTH"
    assert self.sector_policies[sector_id].exists, "SECTOR"
    self.sector_policies[sector_id].paused = enabled

@external
def set_sector_review_interval(sector_id: uint256, review_interval: uint256):
    assert self._is_operator(msg.sender), "AUTH"
    assert self.sector_policies[sector_id].exists, "SECTOR"
    assert review_interval >= 1 * 24 * 60 * 60, "REVIEW"
    self.sector_policies[sector_id].review_interval = review_interval

@external
def update_profile(
    borrower: address,
    sector_id: uint256,
    base_limit: uint256,
    maximum_limit: uint256,
    trailing_revenue: uint256,
    cash_balance: uint256,
    liabilities: uint256,
    metadata: bytes32
):
    assert self._is_operator(msg.sender), "AUTH"
    assert borrower != empty(address), "BORROWER"
    assert self.sector_policies[sector_id].exists, "SECTOR"
    assert maximum_limit >= base_limit, "LIMIT"
    if not self.profiles[borrower].exists:
        self.profile_count += 1
        self.profiles[borrower].borrower = borrower
        self.profiles[borrower].status = STATUS_ACTIVE
    self.profiles[borrower].exists = True
    self.profiles[borrower].sector_id = sector_id
    self.profiles[borrower].base_limit = base_limit
    self.profiles[borrower].maximum_limit = maximum_limit
    self.profiles[borrower].trailing_revenue = trailing_revenue
    self.profiles[borrower].cash_balance = cash_balance
    self.profiles[borrower].liabilities = liabilities
    self.profiles[borrower].metadata = metadata
    self.profiles[borrower].last_review_at = block.timestamp
    self.profiles[borrower].next_review_at = block.timestamp + self.sector_policies[sector_id].review_interval
    self.profiles[borrower].stale_after = block.timestamp + self.default_stale_after
    score: uint256 = self._weighted_score(borrower)
    self.profiles[borrower].grade = self._grade_from_score(score)
    log ProfileUpdated(borrower=borrower, grade=self.profiles[borrower].grade, status=self.profiles[borrower].status, limit=maximum_limit)

@external
def update_scores(
    borrower: address,
    liquidity_score: uint256,
    leverage_score: uint256,
    payment_score: uint256,
    covenant_score: uint256,
    operator_score: uint256
):
    assert self._is_operator(msg.sender), "AUTH"
    assert self.profiles[borrower].exists, "PROFILE"
    assert liquidity_score <= MAX_SCORE and leverage_score <= MAX_SCORE, "SCORE_A"
    assert payment_score <= MAX_SCORE and covenant_score <= MAX_SCORE, "SCORE_B"
    assert operator_score <= MAX_SCORE, "SCORE_C"
    self.profiles[borrower].liquidity_score = liquidity_score
    self.profiles[borrower].leverage_score = leverage_score
    self.profiles[borrower].payment_score = payment_score
    self.profiles[borrower].covenant_score = covenant_score
    self.profiles[borrower].operator_score = operator_score
    score: uint256 = self._weighted_score(borrower)
    self.profiles[borrower].grade = self._grade_from_score(score)
    log ProfileUpdated(borrower=borrower, grade=self.profiles[borrower].grade, status=self.profiles[borrower].status, limit=self.profiles[borrower].maximum_limit)

@external
def set_covenants(
    borrower: address,
    min_cash_bps: uint256,
    max_leverage_bps: uint256,
    min_payment_score: uint256,
    min_operator_score: uint256,
    max_outstanding_bps: uint256,
    collateral_buffer_bps: uint256,
    review_grace: uint256,
    enabled: bool
):
    assert self._is_operator(msg.sender), "AUTH"
    assert self.profiles[borrower].exists, "PROFILE"
    assert min_cash_bps <= BPS, "CASH"
    assert max_outstanding_bps <= BPS, "OUTSTANDING"
    assert collateral_buffer_bps <= BPS, "COLLATERAL"
    self.covenants[borrower] = CovenantPack(
        min_cash_bps=min_cash_bps,
        max_leverage_bps=max_leverage_bps,
        min_payment_score=min_payment_score,
        min_operator_score=min_operator_score,
        max_outstanding_bps=max_outstanding_bps,
        collateral_buffer_bps=collateral_buffer_bps,
        review_grace=review_grace,
        enabled=enabled
    )
    log CovenantUpdated(borrower=borrower, enabled=enabled, min_payment_score=min_payment_score)

@external
def set_watchlist(borrower: address, status: uint256, reason: bytes32):
    assert self._is_operator(msg.sender), "AUTH"
    assert self.profiles[borrower].exists, "PROFILE"
    assert status >= STATUS_ACTIVE and status <= STATUS_SUSPENDED, "STATUS"
    self.profiles[borrower].status = status
    self.profiles[borrower].watchlist_reason = reason
    log WatchlistChanged(borrower=borrower, status=status, reason=reason)

@external
def record_exposure(
    borrower: address,
    committed_limit: uint256,
    outstanding: uint256,
    collateral_posted: uint256,
    defaulted_delta: uint256
):
    assert self._is_operator(msg.sender) or msg.sender == self.protocol, "AUTH"
    assert self.profiles[borrower].exists, "PROFILE"
    previous_commitment: uint256 = self.profiles[borrower].committed_limit
    previous_outstanding: uint256 = self.profiles[borrower].outstanding
    sector_id: uint256 = self.profiles[borrower].sector_id
    if committed_limit >= previous_commitment:
        delta_commitment: uint256 = committed_limit - previous_commitment
        self.global_commitments += delta_commitment
        self.sector_policies[sector_id].open_commitments += delta_commitment
    else:
        delta_commitment: uint256 = previous_commitment - committed_limit
        self.global_commitments -= delta_commitment
        self.sector_policies[sector_id].open_commitments -= delta_commitment
    if outstanding >= previous_outstanding:
        delta_outstanding: uint256 = outstanding - previous_outstanding
        self.global_outstanding += delta_outstanding
        self.sector_policies[sector_id].active_outstanding += delta_outstanding
    else:
        delta_outstanding: uint256 = previous_outstanding - outstanding
        self.global_outstanding -= delta_outstanding
        self.sector_policies[sector_id].active_outstanding -= delta_outstanding
    if defaulted_delta > 0:
        self.global_defaulted += defaulted_delta
        self.sector_policies[sector_id].defaulted_outstanding += defaulted_delta
    self.profiles[borrower].committed_limit = committed_limit
    self.profiles[borrower].outstanding = outstanding
    self.profiles[borrower].collateral_posted = collateral_posted
    log ExposureRecorded(borrower=borrower, principal=outstanding, committed=committed_limit)

@external
@view
def available_limit(borrower: address) -> uint256:
    return self._available_limit(borrower)

@external
@view
def assessment_for(borrower: address, requested_limit: uint256) -> Assessment:
    reason: bytes32 = self._assessment_reason(borrower, requested_limit)
    if reason != empty(bytes32):
        return Assessment(
            allowed=False,
            grade=GRADE_WATCH,
            max_limit=0,
            apr_bps=0,
            min_collateral_bps=0,
            risk_weight_bps=0,
            reason=reason
        )
    profile: BorrowerProfile = self.profiles[borrower]
    sector: SectorPolicy = self.sector_policies[profile.sector_id]
    grade: uint256 = profile.grade
    available: uint256 = self._available_limit(borrower)
    if requested_limit < available:
        available = requested_limit
    collateral_bps: uint256 = sector.min_collateral_bps + self.covenants[borrower].collateral_buffer_bps
    return Assessment(
        allowed=True,
        grade=grade,
        max_limit=available,
        apr_bps=self._apr_for_grade(grade, profile.sector_id),
        min_collateral_bps=collateral_bps,
        risk_weight_bps=sector.risk_weight_bps,
        reason=empty(bytes32)
    )

@external
@view
def can_open_line(borrower: address, requested_limit: uint256) -> bool:
    return self._assessment_reason(borrower, requested_limit) == empty(bytes32)

@external
@view
def borrower_ratios(borrower: address) -> (uint256, uint256, uint256, uint256):
    return (
        self._cash_ratio_bps(borrower),
        self._leverage_bps(borrower),
        self._outstanding_bps(borrower),
        self._collateral_bps(borrower)
    )

@external
@view
def weighted_score(borrower: address) -> uint256:
    if not self.profiles[borrower].exists:
        return 0
    return self._weighted_score(borrower)

@external
@view
def is_review_due(borrower: address) -> bool:
    if not self.profiles[borrower].exists:
        return True
    return block.timestamp >= self.profiles[borrower].next_review_at

@external
@view
def is_profile_stale(borrower: address) -> bool:
    return self._profile_is_stale(borrower)

@external
@view
def sector_utilization_bps(sector_id: uint256) -> uint256:
    policy: SectorPolicy = self.sector_policies[sector_id]
    if not policy.exists or policy.limit_cap == 0:
        return 0
    if policy.open_commitments >= policy.limit_cap:
        return BPS
    return policy.open_commitments * BPS // policy.limit_cap

@external
@view
def global_utilization_bps() -> uint256:
    if self.global_commitment_cap == 0:
        return 0
    if self.global_commitments >= self.global_commitment_cap:
        return BPS
    return self.global_commitments * BPS // self.global_commitment_cap
