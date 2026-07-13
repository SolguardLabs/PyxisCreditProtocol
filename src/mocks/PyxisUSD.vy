# pragma version ^0.4.3

MAX_UINT: constant(uint256) = max_value(uint256)

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    amount: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    amount: uint256

event MinterChanged:
    old_minter: indexed(address)
    new_minter: indexed(address)

event SupplyCapChanged:
    old_cap: uint256
    new_cap: uint256

name: public(String[64])
symbol: public(String[16])
decimals: public(uint256)
totalSupply: public(uint256)
owner: public(address)
minter: public(address)
supply_cap: public(uint256)
paused: public(bool)

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
nonces: public(HashMap[address, uint256])

@deploy
def __init__(_name: String[64], _symbol: String[16], _decimals: uint256):
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals
    self.owner = msg.sender
    self.minter = msg.sender
    self.supply_cap = max_value(uint256)

@internal
def _transfer(sender: address, receiver: address, amount: uint256):
    assert not self.paused, "PAUSED"
    assert sender != empty(address), "SENDER"
    assert receiver != empty(address), "RECEIVER"
    assert self.balanceOf[sender] >= amount, "BALANCE"
    self.balanceOf[sender] -= amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=sender, receiver=receiver, amount=amount)

@external
def transfer(receiver: address, amount: uint256) -> bool:
    self._transfer(msg.sender, receiver, amount)
    return True

@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "SPENDER"
    self.allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, amount=amount)
    return True

@external
def increaseAllowance(spender: address, added_value: uint256) -> bool:
    assert spender != empty(address), "SPENDER"
    new_allowance: uint256 = self.allowance[msg.sender][spender] + added_value
    self.allowance[msg.sender][spender] = new_allowance
    log Approval(owner=msg.sender, spender=spender, amount=new_allowance)
    return True

@external
def decreaseAllowance(spender: address, subtracted_value: uint256) -> bool:
    assert spender != empty(address), "SPENDER"
    current: uint256 = self.allowance[msg.sender][spender]
    assert current >= subtracted_value, "ALLOWANCE"
    new_allowance: uint256 = current - subtracted_value
    self.allowance[msg.sender][spender] = new_allowance
    log Approval(owner=msg.sender, spender=spender, amount=new_allowance)
    return True

@external
def transferFrom(sender: address, receiver: address, amount: uint256) -> bool:
    current_allowance: uint256 = self.allowance[sender][msg.sender]
    if current_allowance != MAX_UINT:
        assert current_allowance >= amount, "ALLOWANCE"
        self.allowance[sender][msg.sender] = current_allowance - amount
        log Approval(owner=sender, spender=msg.sender, amount=current_allowance - amount)
    self._transfer(sender, receiver, amount)
    return True

@external
def mint(receiver: address, amount: uint256):
    assert msg.sender == self.owner or msg.sender == self.minter, "MINTER"
    assert receiver != empty(address), "RECEIVER"
    assert self.totalSupply + amount <= self.supply_cap, "CAP"
    self.totalSupply += amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=empty(address), receiver=receiver, amount=amount)

@external
def burn(amount: uint256):
    assert self.balanceOf[msg.sender] >= amount, "BALANCE"
    self.balanceOf[msg.sender] -= amount
    self.totalSupply -= amount
    log Transfer(sender=msg.sender, receiver=empty(address), amount=amount)

@external
def burnFrom(account: address, amount: uint256):
    current_allowance: uint256 = self.allowance[account][msg.sender]
    if current_allowance != MAX_UINT:
        assert current_allowance >= amount, "ALLOWANCE"
        self.allowance[account][msg.sender] = current_allowance - amount
        log Approval(owner=account, spender=msg.sender, amount=current_allowance - amount)
    assert self.balanceOf[account] >= amount, "BALANCE"
    self.balanceOf[account] -= amount
    self.totalSupply -= amount
    log Transfer(sender=account, receiver=empty(address), amount=amount)

@external
def set_minter(new_minter: address):
    assert msg.sender == self.owner, "OWNER"
    old_minter: address = self.minter
    self.minter = new_minter
    log MinterChanged(old_minter=old_minter, new_minter=new_minter)

@external
def set_supply_cap(new_cap: uint256):
    assert msg.sender == self.owner, "OWNER"
    assert new_cap >= self.totalSupply, "SUPPLY"
    old_cap: uint256 = self.supply_cap
    self.supply_cap = new_cap
    log SupplyCapChanged(old_cap=old_cap, new_cap=new_cap)

@external
def set_paused(enabled: bool):
    assert msg.sender == self.owner, "OWNER"
    self.paused = enabled

@external
def transfer_ownership(new_owner: address):
    assert msg.sender == self.owner, "OWNER"
    assert new_owner != empty(address), "OWNER_ZERO"
    self.owner = new_owner

@external
@view
def circulating_supply() -> uint256:
    return self.totalSupply - self.balanceOf[empty(address)]

@external
@view
def spendable_balance(account: address) -> uint256:
    return self.balanceOf[account]

@external
@view
def allowance_remaining(account: address, spender: address) -> uint256:
    return self.allowance[account][spender]
