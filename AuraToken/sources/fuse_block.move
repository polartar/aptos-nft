module admin_addr::fuse_block {
   use std::signer;
   use std::option::{Self};
   use std::error;
   use std::string::{Self, String};
   use std::object::{Self, Object, TransferRef, ExtendRef};
   use aptos_token_objects::royalty::{Royalty};
   use aptos_token_objects::token::{Self, Token, BurnRef};
   use aptos_token_objects::collection;
   use aptos_framework::fungible_asset::{Metadata};
   use aptos_framework::primary_fungible_store;
   use aptos_framework::fungible_asset::{Self, FungibleStore};

   use admin_addr::aura_token;
   use admin_addr::utils;
   use admin_addr::creator;

   friend admin_addr::initialize;

   /// You don't have enough Aura to perform this action.
   const E_INSUFFICIENT_AURA: u64 = 0;
   /// That object is not a FuseBlock.
   const E_NOT_FUSE_BLOCK: u64 = 1;
   /// The aura amount specified is below the minimum required to mint a FuseBlock.
   const E_BELOW_MINIMUM_AURA: u64 = 2;
   /// You are not the owner of that object.
   const E_NOT_OWNER: u64 = 3;

   const MINIMUM_AURA: u64 = 100;

   struct Counter has key {
      count: u256,
   }

   #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
   struct FuseBlock has key {
      primary_aura_store: address, // the address of the Object<Metadata>/Object<Aura> that the FuseBlock holds
      meets_requirement: bool,
   }

   #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
   struct Refs has key {
      extend_ref: ExtendRef, // to facilitate the FuseBlock transferring their Aura 
      transfer_ref: TransferRef,
      burn_ref: BurnRef,
   }

   /// The account that calls this function must be the module's designated admin, as set in the `Move.toml` file.
   const ENOT_ADMIN: u64 = 0;
   const ENOT_MEET_REQUIREMENT:u64 = 1;

   // Collection configuration details
   const COLLECTION_NAME: vector<u8> = b"Fuse Block";
   const COLLECTION_DESCRIPTION: vector<u8> = b"A collection of Fuse Blocks";
   const COLLECTION_URI: vector<u8> = b"https://ready.gg/wp-content/uploads/2022/11/Screen-Shot-2022-11-02-at-21.38.01.png";
   const BASE_TOKEN_URI: vector<u8> = b"https://assets.wenmint.com/images/farmacyfantoms/";
   const BASE_TOKEN_NAME: vector<u8> = b"FuseBlock #";

   /// Ensure that the deployer is the @admin of the module, then create the collection.
   /// Note that `init_module` is automatically run when the contract is published.
   public(friend) fun initialize(admin: &signer) {
      utils::assert_is_admin(admin);
      let collection_creator = creator::get_signer();
      collection::create_unlimited_collection(
         &collection_creator,
         string::utf8(COLLECTION_DESCRIPTION),
         string::utf8(COLLECTION_NAME),
         option::none<Royalty>(),
         string::utf8(COLLECTION_URI),
      );

      move_to(
         admin,
         Counter {
            count: 1,
         },
      );
   }

   /// This function is NOT gated by admin access.
   /// Anyone can call it as long as they have the Aura to do so.
   /// It mints a FuseBlock NFT to the `minter` and exchanges the specified amount of Aura for the FuseBlock's Aura.
   /// The `minter` must at least have `MINIMUM_AURA` Aura to mint a FuseBlock.
   public entry fun mint_to(
      minter: &signer,
      aura_amount: u64,
   ) acquires Refs, Counter {
      assert!(aura_amount >= MINIMUM_AURA, error::permission_denied(E_BELOW_MINIMUM_AURA));

      // mint the FuseBlock NFT to the minter
      let minter_addr = signer::address_of(minter);
      let token_obj = internal_mint_to(minter_addr);

      // transfer the Aura from the minter to the token and get the primary store address back
      let primary_aura_store = infuse_block_with_aura(minter, token_obj, aura_amount);
      let token_signer = internal_get_fuse_block_signer(token_obj);

      move_to(
         &token_signer,
         FuseBlock {
            primary_aura_store: primary_aura_store,
            meets_requirement: false,
         },
      );
      internal_increment();

      // signer::address_of(&token_signer)
   }

   public entry fun set_meets_requirement(
      admin: &signer,
      fuse_block_obj: Object<FuseBlock>,
   ) acquires FuseBlock {
      utils::assert_is_admin(admin);
      let fuse_block_addr = object::object_address(&fuse_block_obj);
      assert!(exists<FuseBlock>(fuse_block_addr), error::invalid_argument(E_NOT_FUSE_BLOCK));

      borrow_global_mut<FuseBlock>(fuse_block_addr).meets_requirement = true;
   }

   /// This function requires elevated admin access, as it handles transferring the token
   /// to the specified `to` address regardless of who owns it.
   public entry fun transfer(
      admin: &signer,
      fuse_block: Object<FuseBlock>,
      to: address,
   ) acquires Refs, FuseBlock {
      utils::assert_is_admin(admin);
      assert!(meets_requirement(fuse_block), error::permission_denied(ENOT_MEET_REQUIREMENT));
      let fuse_block_addr = object::object_address(&fuse_block);
      let transfer_ref = &borrow_global<Refs>(fuse_block_addr).transfer_ref;
      let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
      object::transfer_with_ref(linear_transfer_ref, to);
   }

   // Users can call this to burn the FuseBlock and extract the aura within it
   public entry fun burn_and_extract_aura(
      owner: &signer,
      fuse_block_obj: Object<FuseBlock>,
   ) acquires Refs, FuseBlock {
      // gate by the virtue of the owner giving their permission
      let owner_addr = signer::address_of(owner);
      // assert that the signer is the owner of the FuseBlock
      assert!(object::is_owner(fuse_block_obj, owner_addr), error::permission_denied(E_NOT_OWNER));

      // extract the Aura from the FuseBlock and transfer it to the owner
      let aura_metadata = aura_token::get_metadata();
      let fuse_block_addr = object::object_address(&fuse_block_obj);
      let balance = primary_fungible_store::balance(fuse_block_addr, aura_metadata);
      let fuse_block_signer = internal_get_fuse_block_signer(fuse_block_obj);
      primary_fungible_store::transfer(&fuse_block_signer, aura_metadata, owner_addr, balance);

      // then burn the FuseBlock
      internal_burn_fuse_block(fuse_block_obj);
   }

   /// This function transfers the specified amount of Aura from the `from` account to the `to` object.
   /// The `to` object is a FuseBlock.
   /// Anyone can call this function as long as they have the Aura to do so.
   public fun infuse_block_with_aura(
      from: &signer,
      token_fuse_block_obj: Object<Token>,
      amount: u64,
   ): address {
      let aura_metadata: Object<Metadata> = aura_token::get_metadata();
      let token_fuse_block_addr = object::object_address(&token_fuse_block_obj);
      // get the Aura primary store address for the Token
      let primary_aura_store = primary_fungible_store::primary_store_address(token_fuse_block_addr, aura_metadata);

      let from_addr = signer::address_of(from);
      let balance = primary_fungible_store::balance(from_addr, aura_metadata);
      assert!(balance >= amount, error::permission_denied(E_INSUFFICIENT_AURA));
      // transfer the Aura from the `from` account to the Token
      primary_fungible_store::transfer(from, aura_metadata, token_fuse_block_addr, amount);

      // return the address of the primary store in case this is being called from `mint_to`
      primary_aura_store
   }

   // --------------------------------------------------------
   //  internal functions that shouldn't be exposed publicly
   // --------------------------------------------------------

   inline fun internal_mint_to(
      to: address,
   ): Object<Token> {
      // get the automated creator for this contract
      let creator = creator::get_signer();

      // get the token name and token uri based on the current Counter.count
      let (token_name, token_uri) = get_token_name_and_uri();
      // create the token and get back the &ConstructorRef to create the other Refs with
      let token_constructor_ref = token::create(
         &creator,
         string::utf8(COLLECTION_NAME),
         string::utf8(COLLECTION_DESCRIPTION),
         token_name,
         option::none(),
         token_uri,
      );

      // create the TransferRef, ExtendRef, BurnRef, the token's `&signer`, and the token's `&Object`
      let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
      let extend_ref = object::generate_extend_ref(&token_constructor_ref);
      let burn_ref = token::generate_burn_ref(&token_constructor_ref);
      let token_signer = object::generate_signer(&token_constructor_ref);
      let token_object = object::object_from_constructor_ref<Token>(&token_constructor_ref);

      // transfer the token to the receiving account
      object::transfer(&creator, token_object, to);
      object::disable_ungated_transfer(&transfer_ref);

      // Move the Refs resource to the Token's global resources
      move_to(
         &token_signer,
         Refs {
            transfer_ref,
            extend_ref,
            burn_ref,
         },
      );

      token_object
   }

   inline fun internal_burn_fuse_block(
      fuse_block_obj: Object<FuseBlock>,
   ) {
      let fuse_block_addr = object::object_address(&fuse_block_obj);
      // deconstruct the fuse block object into its Refs fields
      let Refs {
         extend_ref: _,
         transfer_ref: _,
         burn_ref: burn_ref,
      } = move_from<Refs>(fuse_block_addr);

      // deconstruct the FuseBlock object into its fields
      let FuseBlock {
         primary_aura_store: primary_aura_store,
         meets_requirement: _,
      } = move_from<FuseBlock>(fuse_block_addr);
      let primary_aura_store_obj = object::address_to_object<FungibleStore>(primary_aura_store);
      let any_remaining_balance = fungible_asset::balance(primary_aura_store_obj) > 0;
      // this should be redundant if the contract is written correctly
      assert!(!any_remaining_balance, 0);

      // burn the underlying Token and ObjectCore
      token::burn(burn_ref);
   }

   // this is a private, non-entry function, so we don't need to implement access control.
   inline fun internal_increment() acquires Counter {
      let counter = borrow_global_mut<Counter>(@admin_addr);
      counter.count = counter.count + 1; 
   }

   inline fun internal_get_fuse_block_signer<T: key>(
      obj: Object<T>,
   ): signer {
      let obj_addr = object::object_address<T>(&obj);
      let extend_ref = &borrow_global<Refs>(obj_addr).extend_ref;

      object::generate_signer_for_extending(extend_ref)
   }

   // --------------------------------------------------------
   //                  getters/view functions
   // --------------------------------------------------------

   inline fun get_fuse_block(
      fuse_block_obj: Object<FuseBlock>
   ): &FuseBlock {
      let fuse_block_addr = object::object_address(&fuse_block_obj);
      assert!(exists<FuseBlock>(fuse_block_addr), error::invalid_argument(E_NOT_FUSE_BLOCK));
      borrow_global<FuseBlock>(fuse_block_addr)
   }

   // gets the token name and token uri based on current Counter.count
   inline fun get_token_name_and_uri(): (String, String) acquires Counter {
      let count = get_count();
      let token_name = utils::concat(string::utf8(BASE_TOKEN_NAME), count);
      let token_uri = utils::concat(string::utf8(BASE_TOKEN_URI), count);
      string::append(&mut token_uri, string::utf8(b".png"));

      (token_name, token_uri)
   }

   #[view]
   public fun get_count(): u256 acquires Counter {
      borrow_global<Counter>(@admin_addr).count
   }

   #[view]
   public fun meets_requirement(fuse_block_obj: Object<FuseBlock>): bool acquires FuseBlock {
      let fuse_block_addr = object::object_address(&fuse_block_obj);
      assert!(exists<FuseBlock>(fuse_block_addr), error::invalid_argument(E_NOT_FUSE_BLOCK));
      let fuse_block = get_fuse_block(fuse_block_obj);
      fuse_block.meets_requirement
   }

   #[view]
   public fun get_aura_amount(fuse_block_obj: Object<FuseBlock>): u64 acquires FuseBlock {
      let primary_aura_store = get_fuse_block(fuse_block_obj).primary_aura_store;
      // You could do an `is_frozen()` check here too, if you ever want to add that
      let primary_aura_store_obj = object::address_to_object<FungibleStore>(primary_aura_store);
      fungible_asset::balance(primary_aura_store_obj)
   }
}

// --------------------------------------------------------
//                       test module
// --------------------------------------------------------
#[test_only]
module admin_addr::fuse_block_tests {
   use std::signer;
   use aptos_framework::object;
   use aptos_framework::primary_fungible_store;
   use admin_addr::fuse_block::{Self, FuseBlock};
   use admin_addr::aura_token;
   use admin_addr::initialize;

   const TEST_STARTING_AURA: u64 = 211;
   const MINIMUM_AURA: u64 = 100;

   #[test(admin = @admin_addr, owner_1 = @0xA, owner_2 = @0xB, aptos_framework = @0x1)]
   /// Tests creating a token and transferring it to multiple owners
   fun test_happy_path(
      admin: &signer,
      owner_1: &signer,
      owner_2: &signer,
      aptos_framework: &signer,
   ) {
      initialize::init_module_for_test(admin, aptos_framework);
      let admin_address = signer::address_of(admin);
      let owner_1_address = signer::address_of(owner_1);
      let owner_2_address = signer::address_of(owner_2);

      aura_token::mint(admin, owner_1_address, TEST_STARTING_AURA);
      let aura_metadata = aura_token::get_metadata();

      // Withdraw 100 aura from owner 1 and infuse it into the FuseBlock
      let token_address = fuse_block::mint_to(owner_1,  MINIMUM_AURA);
      let token_object = object::address_to_object<FuseBlock>(token_address);
      assert!(primary_fungible_store::balance(owner_1_address, aura_metadata) == TEST_STARTING_AURA - MINIMUM_AURA, 0);
      assert!(primary_fungible_store::balance(token_address, aura_metadata) == MINIMUM_AURA, 0);

      assert!(object::is_owner(token_object, owner_1_address), 0);

      // Now let's transfer the token to owner_2, without owner_2's permission.
      fuse_block::set_meets_requirement(admin, token_object);
      fuse_block::transfer(admin, token_object, owner_2_address);
      assert!(object::is_owner(token_object, owner_2_address), 0);

      // Now let's transfer the token back to admin, without owner_2's permission.
      fuse_block::set_meets_requirement(admin, token_object);
      fuse_block::transfer(admin, token_object, admin_address);
      assert!(object::is_owner(token_object, admin_address), 0);

      // Now let's burn the token and extract the aura
      fuse_block::burn_and_extract_aura(admin, token_object);
      assert!(primary_fungible_store::balance(owner_1_address, aura_metadata) == TEST_STARTING_AURA - MINIMUM_AURA, 0);
      assert!(!object::is_object(token_address), 0);
   }

   // Test to ensure the deployer must set to admin
   // see error.move for more error codes
   // PERMISSION_DENIED = 0x5; // turns into 0x50000 when emitted from error.move
   // ENOT_ADMIN = 0x0;
   // thus expected_failure = PERMISSION_DENIED + ENOT_ADMIN = 0x50000 + 0x0 = 0x50000
   #[test(admin = @0xabcdef, aptos_framework = @0x1)] // not @admin
   #[expected_failure(abort_code = 0x50000, location = admin_addr::utils)]
   /// Tests creating a token and transferring it to multiple owners
   fun test_not_admin_for_init(
      admin: &signer,
      aptos_framework: &signer,
   ) {
      initialize::init_module_for_test(admin, aptos_framework);
   }

   // Test to ensure that the only account that can call `transfer` is the module's admin
   #[test(admin = @admin_addr, owner_1 = @0xA, owner_2 = @0xB, aptos_framework = @0x1)]
   #[expected_failure(abort_code = 0x50000, location = admin_addr::utils)]
   fun test_not_admin_for_transfer(
      admin: &signer,
      owner_1: &signer,
      owner_2: &signer,
      aptos_framework: &signer,
   ) {
      initialize::init_module_for_test(admin, aptos_framework);
      let owner_1_address = signer::address_of(owner_1);
      let owner_2_address = signer::address_of(owner_2);
      let aura_metadata = aura_token::get_metadata();

      aura_token::mint(admin, owner_1_address, TEST_STARTING_AURA);
      let token_address = fuse_block::mint_to(owner_1,  MINIMUM_AURA);
      assert!(primary_fungible_store::balance(owner_1_address, aura_metadata) == TEST_STARTING_AURA - MINIMUM_AURA, 0);
      let token_object = object::address_to_object<FuseBlock>(token_address);
      assert!(object::is_owner(token_object, owner_1_address), 0);

      // owner_2 tries to transfer the token to themself, but fails because they are not the admin
      fuse_block::transfer(owner_2, token_object, owner_2_address);
   }
}
