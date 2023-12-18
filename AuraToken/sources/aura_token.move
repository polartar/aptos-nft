/// A coin example using managed_fungible_asset to create a fungible "coin" and helper functions to only interact with
/// primary fungible stores only.
module admin_addr::aura_token {
    use aptos_framework::object;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object::Object;
    use admin_addr::managed_fungible_asset;
    use std::string::utf8;
    use admin_addr::creator;
    use admin_addr::utils;

    friend admin_addr::initialize;

    /// The object you passed in does not have the `Aura` resource.
    const E_NOT_AURA: u64 = 0;

    const AURA_TOKEN_NAME: vector<u8> = b"Aura Token";
    const ASSET_SYMBOL: vector<u8> = b"AURA";

    /// Initialize metadata object and store the refs to the `creator` object from creator.move
    public(friend) fun initialize(admin: &signer) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        let constructor_ref = &object::create_named_object(&creator, ASSET_SYMBOL);
        managed_fungible_asset::initialize(
            constructor_ref,
            0, /* maximum_supply. 0 means no maximum */
            utf8(AURA_TOKEN_NAME), /* name */
            utf8(ASSET_SYMBOL), /* symbol */
            8, /* decimals */
            utf8(b"https://ready.gg/wp-content/uploads/2022/09/doughnut.png"), /* icon */
            utf8(b"https://ready.gg"), /* project */
            vector[true, true, true], /* mint_ref, transfer_ref, burn_ref */
        );
    }

    #[view]
    /// Return the address of the metadata that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let creator_addr = creator::get_address();
        let metadata_address = object::create_object_address(&creator_addr, ASSET_SYMBOL);
        object::address_to_object<Metadata>(metadata_address)
    }

    /// Mint as the admin of this module
    public entry fun mint(admin: &signer, to: address, amount: u64) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        managed_fungible_asset::mint_to_primary_stores(&creator, get_metadata(), vector[to], vector[amount]);
    }

    /// Transfer as the admin of this module ignoring `frozen` field.
    public entry fun transfer(admin: &signer, from: address, to: address, amount: u64) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        managed_fungible_asset::transfer_between_primary_stores(
            &creator,
            get_metadata(),
            vector[from],
            vector[to],
            vector[amount]
        );
    }

    /// Burn fungible assets as the admin of this module.
    public entry fun burn(admin: &signer, from: address, amount: u64) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        managed_fungible_asset::burn_from_primary_stores(&creator, get_metadata(), vector[from], vector[amount]);
    }

    /// Freeze an account (as the admin of this module) so it cannot transfer or receive fungible assets.
    public entry fun freeze_account(admin: &signer, account: address) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        managed_fungible_asset::set_primary_stores_frozen_status(&creator, get_metadata(), vector[account], true);
    }

    /// Unfreeze an account (as the admin of this module) so it can transfer or receive fungible assets.
    public entry fun unfreeze_account(admin: &signer, account: address) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        managed_fungible_asset::set_primary_stores_frozen_status(&creator, get_metadata(), vector[account], false);
    }

    /// Withdraw as the admin of this module, ignoring `frozen` field.
    public fun withdraw(admin: &signer, from: address, amount: u64): FungibleAsset {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        managed_fungible_asset::withdraw_from_primary_stores(&creator, get_metadata(), vector[from], vector[amount])
    }

    /// Deposit as the admin of this module, ignoring `frozen` field.
    public fun deposit(admin: &signer, fa: FungibleAsset, to: address) {
        utils::assert_is_admin(admin);
        let creator = creator::get_signer();
        let amount = fungible_asset::amount(&fa);
        managed_fungible_asset::deposit_to_primary_stores(
            &creator,
            &mut fa,
            vector[to],
            vector[amount]
        );
        fungible_asset::destroy_zero(fa);
    }
}

#[test_only]
module admin_addr::aura_token_test {
    use std::signer;
    use admin_addr::initialize;
    use admin_addr::aura_token::{Self, freeze_account, unfreeze_account, transfer, mint, burn};
    use aptos_framework::primary_fungible_store::{is_frozen, balance};

    #[test(admin = @admin_addr, aptos_framework = @0x1)]
    fun test_basic_flow(admin: &signer, aptos_framework: &signer) {
        let admin_address = signer::address_of(admin);
        initialize::init_module_for_test(admin, aptos_framework);
        let aaron_address = @0xface;

        mint(admin, admin_address, 100);
        let metadata = aura_token::get_metadata();
        assert!(balance(admin_address, metadata) == 100, 4);
        freeze_account(admin, admin_address);
        assert!(is_frozen(admin_address, metadata), 5);
        transfer(admin, admin_address, aaron_address, 10);
        assert!(balance(aaron_address, metadata) == 10, 6);

        unfreeze_account(admin, admin_address);
        assert!(!is_frozen(admin_address, metadata), 7);
        burn(admin, admin_address, 90);
    }

    #[test(admin = @admin_addr, aptos_framework = @0x1, aaron = @0xface)]
    #[expected_failure(abort_code = 0x50000, location = admin_addr::utils)]
    fun test_permission_denied(admin: &signer, aptos_framework: &signer, aaron: &signer) {
        initialize::init_module_for_test(admin, aptos_framework);
        let admin_addr = signer::address_of(admin);
        mint(aaron, admin_addr, 100);
    }
}
