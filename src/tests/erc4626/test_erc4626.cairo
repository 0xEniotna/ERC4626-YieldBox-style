use core::traits::TryInto;
use erc4626::erc4626::interface::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use erc4626::utils::{pow_256};
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
    DeclareResultTrait
};
use core::num::traits::Bounded;
use openzeppelin::utils::serde::SerializedAppend;
use starknet::{ContractAddress, contract_address_const, get_contract_address};

fn OWNER() -> ContractAddress {
    'owner'.try_into().unwrap()
}

fn ALICE() -> ContractAddress {
    'alice'.try_into().unwrap()
}

fn BOB() -> ContractAddress {
    'bob'.try_into().unwrap()
}

fn INITIAL_SUPPLY() -> u256 {
    1000000000000000000000000000000
}

fn TOKEN_ADDRESS() -> ContractAddress {
    'token_address'.try_into().unwrap()
}

fn VAULT_ADDRESS() -> ContractAddress {
    'vault_address'.try_into().unwrap()
}

fn deploy_token() -> (ERC20ABIDispatcher, ContractAddress) {
    let token = declare("ERC20Token").unwrap().contract_class();
    let mut calldata = Default::default();
    Serde::serialize(@OWNER(), ref calldata);
    Serde::serialize(@INITIAL_SUPPLY(), ref calldata);

    let (address, _) = token.deploy_at(@calldata, TOKEN_ADDRESS()).unwrap();
    let dispatcher = ERC20ABIDispatcher { contract_address: address, };
    (dispatcher, address)
}

fn deploy_contract() -> (ERC20ABIDispatcher, IERC4626Dispatcher) {
    let (token, token_address) = deploy_token();
    let mut calldata = array![];
    let name: ByteArray = "Vault Mock Token";
    let symbol: ByteArray = "vltMCK";
    calldata.append_serde(token_address);
    calldata.append_serde(name);
    calldata.append_serde(symbol);
    calldata.append(0);
    let vault = declare("ERC4626").unwrap().contract_class();
    let (contract_address, _) = vault.deploy_at(@calldata, VAULT_ADDRESS()).unwrap();
    (token, IERC4626Dispatcher { contract_address })
}


#[test]
fn test_constructor() {
    let (asset, vault) = deploy_contract();
    assert(vault.asset() == asset.contract_address, 'invalid asset');
    assert(vault.decimals() == (18 + 0), 'invalid decimals');
    assert(vault.name() == "Vault Mock Token", 'invalid name');
    assert(vault.symbol() == "vltMCK", 'invalid symbol');
}
#[test]
fn convert_to_assets() {
    let (_asset, vault) = deploy_contract();
    let shares = pow_256(10, 2);
    // 10e10 * (0 + 1) / (0 + 10e8)
    assert(vault.convert_to_assets(shares) == 100, 'invalid assets');
}
#[test]
fn convert_to_shares() {
    let (_asset, vault) = deploy_contract();
    let assets = 10;
    // asset * shares / total assets
    // 10 * (0 + 10e8) / (0 + 1)
    assert(vault.convert_to_shares(assets) == pow_256(10, 1), 'invalid shares');
}

#[test]
fn max_deposit() {
    let (_asset, vault) = deploy_contract();
    assert(vault.max_deposit(get_contract_address()) == Bounded::<u256>::MAX, 'invalid max deposit');
}

#[test]
fn max_mint() {
    let (_asset, vault) = deploy_contract();
    assert(vault.max_mint(get_contract_address()) == Bounded::<u256>::MAX, 'invalid max mint');
}

#[test]
fn preview_deposit() {
    let (_asset, vault) = deploy_contract();
    assert(vault.preview_deposit(10) == pow_256(10, 1), 'invalid preview_deposit');
}

#[test]
fn preview_mint() {
    let (_asset, vault) = deploy_contract();
    assert(vault.preview_mint(pow_256(10, 2)) == 100, 'invalid preview_mint');
}

#[test]
fn preview_redeem() {
    let (_asset, vault) = deploy_contract();
    assert(vault.preview_redeem(pow_256(10, 2)) == 100, 'invalid preview_redeem');
}

#[test]
fn preview_withdraw() {
    let (_asset, vault) = deploy_contract();
    assert(vault.preview_redeem(pow_256(10, 2)) == 100, 'invalid preview_withdraw');
}
#[test]
fn test_deposit() {
    let (asset, vault) = deploy_contract();
    let amount = asset.balanceOf(OWNER());
    start_cheat_caller_address(asset.contract_address, OWNER());
    asset.approve(vault.contract_address, amount);
    stop_cheat_caller_address(asset.contract_address);
    let result = vault.preview_deposit(amount);
    start_cheat_caller_address(vault.contract_address, OWNER());
    assert(vault.deposit(amount, OWNER()) == result, 'invalid shares');
    assert(vault.balanceOf(OWNER()) == result, 'invalid balance');
}

#[test]
fn test_max_redeem() {
    let (asset, vault) = deploy_contract();
    let amount = asset.balanceOf(OWNER());
    start_cheat_caller_address(asset.contract_address, OWNER());
    asset.approve(vault.contract_address, amount);
    stop_cheat_caller_address(asset.contract_address);
    let _result = vault.preview_deposit(amount);
    start_cheat_caller_address(vault.contract_address, OWNER());
    let shares = vault.deposit(amount, OWNER());
    assert(vault.max_redeem(OWNER()) == shares, 'invalid max redeem');
}
#[test]
fn max_withdraw() {
    let (asset, vault) = deploy_contract();
    let amount = asset.balanceOf(OWNER());
    start_cheat_caller_address(asset.contract_address, OWNER());
    asset.approve(vault.contract_address, amount);
    stop_cheat_caller_address(asset.contract_address);
    let _result = vault.preview_deposit(amount);
    start_cheat_caller_address(vault.contract_address, OWNER());
    let _shares = vault.deposit(amount, OWNER());
    let value = vault.convert_to_assets(vault.balanceOf(OWNER()));
    assert(vault.max_withdraw(OWNER()) == value, 'invalid max withdraw');
}
#[test]
fn mint() {
    let (asset, vault) = deploy_contract();
    let amount = asset.balanceOf(OWNER());
    start_cheat_caller_address(asset.contract_address, OWNER());
    asset.approve(vault.contract_address, amount);
    stop_cheat_caller_address(asset.contract_address);
    let _result = vault.preview_deposit(amount);
    let minted = vault.preview_mint(1);
    start_cheat_caller_address(vault.contract_address, OWNER());
    let _shares = vault.mint(1, OWNER());
    assert(vault.balanceOf(OWNER()) == minted, 'invalid mint shares');
}
#[test]
fn test_redeem() {
    let (asset, vault) = deploy_contract();
    let amount = asset.balanceOf(OWNER());
    start_cheat_caller_address(asset.contract_address, OWNER());
    asset.approve(vault.contract_address, amount);
    stop_cheat_caller_address(asset.contract_address);
    let _result = vault.preview_deposit(amount);
    start_cheat_caller_address(vault.contract_address, OWNER());
    let shares = vault.deposit(amount, OWNER());
    assert(vault.balanceOf(OWNER()) == shares, 'invalid balance before');
    let _preview = vault.preview_redeem(shares);
    start_cheat_caller_address(vault.contract_address, OWNER());
    let _redeemed = vault.redeem(shares, OWNER(), OWNER());
    assert(vault.balanceOf(OWNER()) == 0, 'invalid balance after');
}

#[test]
fn test_withdraw() {
    let (asset, vault) = deploy_contract();
    let amount = asset.balanceOf(OWNER());
    start_cheat_caller_address(asset.contract_address, OWNER());
    asset.approve(vault.contract_address, amount);
    stop_cheat_caller_address(asset.contract_address);
    let _result = vault.preview_deposit(amount);
    start_cheat_caller_address(vault.contract_address, OWNER());
    let shares = vault.deposit(amount, OWNER());
    assert(vault.balanceOf(OWNER()) == shares, 'invalid balance before');

    start_cheat_caller_address(vault.contract_address, OWNER());
    let _shares = vault.withdraw(amount, OWNER(), OWNER());
    assert(vault.balanceOf(OWNER()) == 0, 'invalid balance after');
}

