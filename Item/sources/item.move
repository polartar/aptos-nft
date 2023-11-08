module admin_addr::item {
   use std::signer;
   use std::option::{Self};
   use std::error;
   // use std::vector;
   use std::string::{Self, String};
   use std::object::{Self, Object, TransferRef};
   use aptos_token_objects::royalty::{Royalty};
   use aptos_token_objects::token::{Self, Token, create_named_token, create_token_seed};
   use aptos_token_objects::collection;
   use aptos_framework::fungible_asset::Metadata;
   // use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
   use admin_addr::managed_fungible_asset;

   #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
   struct NextTokenId has key {
      id: u256
   }

   #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
   struct Refs has key {
      transfer_ref: TransferRef,
   }

    

   /// The account that calls this function must be the module's designated admin, as set in the `Move.toml` file.
   const ENOT_ADMIN: u64 = 0;

   // Collection configuration details
   const COLLECTION_NAME: vector<u8> = b"Infused Items";
   const COLLECTION_DESCRIPTION: vector<u8> = b"A collection of infused items";
   const COLLECTION_URI: vector<u8> = b"collection image uri";
   const TOKEN_URI: vector<u8> = b"https://picsum.photos/200/300?id=";
   const TOKEN_IDENTIFIER: vector<u8> = b"Infuse Item #";

   const ASSET_SYMBOL: vector<u8> = b"Item NFT";
   const TOKEN_NAME: vector<u8> = b"Item token";

   /// Ensure that the deployer is the @admin of the module, then create the collection.
   /// Note that `init_module` is automatically run when the contract is published.
   fun init_module(deployer: &signer) {
      assert!(signer::address_of(deployer) == @admin, error::permission_denied(ENOT_ADMIN));
      create_collection(deployer);

      publish_next_token_id(deployer);
      // publish_item_infos(deployer);
   }

   fun publish_next_token_id(account: &signer) {
      move_to(account, NextTokenId { id: 0 }) 
   }

   // fun publish_item_infos(account: &signer) {
   //    move_to(account, ItemInfos {
   //       infos: vector::empty() 
   //    });
   // }

   inline fun concat<T>(s: String, n: T): String {
       let n_str = aptos_std::string_utils::to_string(&n);
       string::append(&mut s, n_str);
       s
   }

   public entry fun mint_direct(
      admin: &signer,
      to: address,
      // uuid: String,
      amount: u64
   ) acquires  NextTokenId {
      let token_id = get_next_token_id();
      
      mint_to(admin, token_id, to);
      managed_fungible_asset::mint_to_primary_stores(admin, get_metadata(), vector[to], vector[amount]);
      
      // let new_item = ItemInfo {
      //    amount: aura_amount,
      //    item_nft_id: token_id,
      //    uuid: uuid
      // };

      // let item_infos = borrow_global_mut<ItemInfos>(@admin_addr);
      // vector::push_back(&mut item_infos.infos, new_item);

      store_next_token_id(token_id + 1);
   }

   fun get_next_token_id(): u256 acquires NextTokenId {
      borrow_global<NextTokenId>(@admin_addr).id
   }

   fun store_next_token_id(next_id: u256) acquires NextTokenId {
      let next_token_id = borrow_global_mut<NextTokenId>(@admin_addr);
      next_token_id.id = next_id;
   }

    

   /// This function handles creating the token, minting it to the specified `to` address,
   /// and storing the `TransferRef` for the Token in its `Refs` resource.
   /// This means every time we create a new Token, we create and move a Refs resource
   /// to its global address. This is how we can keep track of the TransferRef for each
   /// individual Token we create.
   /// @returns the address of the newly created Token Object
   public fun mint_to(
      admin: &signer,
      token_id: u256,
      to: address,
   ): address {
      // Need to replace token_id to firebaseId
      let token_uri = concat(string::utf8(TOKEN_URI), token_id);
      let token_name = concat(string::utf8(TOKEN_IDENTIFIER), token_id);

      // create the token and get back the &ConstructorRef to create the other Refs with
      let token_constructor_ref = token::create_named_token(
         admin,
         string::utf8(COLLECTION_NAME),
         string::utf8(COLLECTION_DESCRIPTION),
         token_name,
         option::none(),
         token_uri,
      );

      // create the TransferRef, the token's `&signer`, and the token's `&Object`
      let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
      let token_signer = object::generate_signer(&token_constructor_ref);
      let token_object = object::object_from_constructor_ref<Token>(&token_constructor_ref);

      // transfer the token to the receiving account
      object::transfer(admin, token_object, to);

      // create the Refs resource with the TransferRef we generated
      let refs = Refs {
        transfer_ref,
      };

      // Move the Refs resource to the Token's global resources
      move_to(
         &token_signer,
         refs,
      );

      signer::address_of(&token_signer)
   }

    /// This function requires elevated admin access, as it handles transferring the token
    /// to the specified `to` address regardless of who owns it.
   public entry fun transfer(
      admin: &signer,
      // token: Object<Token>,
      from: address,
      to: address,
      amount: u64
   )  {
      // Ensure that the caller is the @admin of the module
      assert!(signer::address_of(admin) == @admin, error::permission_denied(ENOT_ADMIN));

      // let refs = borrow_global<Refs>(object::object_address(&token));

      // let linear_transfer_ref = object::generate_linear_transfer_ref(&refs.transfer_ref);

      // 3. Transfer the token to the receiving `to` account
      // object::transfer_with_ref(linear_transfer_ref, to);
      managed_fungible_asset::transfer_between_primary_stores(
            admin,
            get_metadata(),
            vector[from],
            vector[to],
            vector[amount]
        );
   }

   /// Helper function to create the collection
   public fun create_collection(admin: &signer) {
      collection::create_unlimited_collection(
         admin,
         string::utf8(COLLECTION_DESCRIPTION),
         string::utf8(COLLECTION_NAME),
         option::none<Royalty>(),
         string::utf8(COLLECTION_URI),
      );
      
      let constructor_ref = &create_named_token(admin,
            string::utf8(COLLECTION_NAME),
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(TOKEN_NAME),
            option::none(),
            string::utf8(b"http://aptoslabs.com/token"),
        );

      managed_fungible_asset::initialize(
         constructor_ref,
         0, /* maximum_supply. 0 means no maximum */
         string::utf8(b"item amount"), /* name */
         string::utf8(ASSET_SYMBOL), /* symbol */
         0, /* decimals */
         string::utf8(b"http://example.com/favicon.ico"), /* icon */
         string::utf8(b"http://example.com"), /* project */
         vector[true, true, true], /* mint_ref, transfer_ref, burn_ref */
      );
   }

   #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    /// This function is optional as a helper function for offline applications.
    public fun get_metadata(): Object<Metadata> {
        let collection_name: String = string::utf8(COLLECTION_NAME);
        let token_name: String = string::utf8(TOKEN_NAME);
        let asset_address = object::create_object_address(
            &@admin_addr,
            create_token_seed(&collection_name, &token_name)
        );
        object::address_to_object<Metadata>(asset_address)
    }

   //            //
   // Unit tests //
   //            //

   // #[test_only]
   // use admin_addr::item::{Self};

   // #[test_only]
   // /// Helper function to initialize the test and create and return the three admin/owner accounts
   // fun init_for_test(
   //    admin: &signer,
   // ) {
   //    // Normally we might put some more complex logic in here if we regularly instantiate multiple
   //    // accounts and logistical things for each test

   //    // For this, we just need to call the initialization function by directly invoking it.
   //    // It would normally be automatically called upon publishing the module, but since this
   //    // is a unit test, we have to manually call it.
   //    item::init_module(admin);
   // }

   // #[test(admin = @admin, owner_1 = @0xA, owner_2 = @0xB)]
   // /// Tests creating a token and transferring it to multiple owners
   // fun test_happy_path(
   //    admin: &signer,
   //    owner_1: &signer,
   //    owner_2: &signer,
   // ) acquires Refs {
   //    init_for_test(admin);
   //    let admin_address = signer::address_of(admin);
   //    let owner_1_address = signer::address_of(owner_1);
   //    let owner_2_address = signer::address_of(owner_2);

   //    // Admin is now the owner of the collection, so let's mint a token to owner_1
   //    let token_address = item::mint_to(admin, string::utf8(b"Token #1"), owner_1_address);
   //    let token_object = object::address_to_object<Token>(token_address);

   //    assert!(object::is_owner(token_object, owner_1_address), 0);

   //    // Now let's transfer the token to owner_2, without owner_2's permission.
   //    item::transfer(admin, token_object, owner_2_address);
   //    assert!(object::is_owner(token_object, owner_2_address), 0);

   //    // Now let's transfer the token back to admin, without owner_2's permission.
   //    item::transfer(admin, token_object, admin_address);
   //    assert!(object::is_owner(token_object, admin_address), 0);
   // }

   // // Test to ensure the deployer must set to admin
   // // see error.move for more error codes
   // // PERMISSION_DENIED = 0x5; // turns into 0x50000 when emitted from error.move
   // // ENOT_ADMIN = 0x0;
   // // thus expected_failure = PERMISSION_DENIED + ENOT_ADMIN = 0x50000 + 0x0 = 0x50000
   // #[test(admin = @0xabcdef)] // not @admin
   // #[expected_failure(abort_code = 0x50000, location = Self)]
   // /// Tests creating a token and transferring it to multiple owners
   // fun test_not_admin_for_init(
   //    admin: &signer,
   // ) {
   //    item::init_module(admin);
   // }

   // // Test to ensure that the only account that can call `transfer` is the module's admin
   // #[test(admin = @admin, owner_1 = @0xA, owner_2 = @0xB)]
   // #[expected_failure(abort_code = 0x50000, location = Self)]
   // fun test_not_admin_for_transfer(
   //    admin: &signer,
   //    owner_1: &signer,
   //    owner_2: &signer,
   // ) acquires Refs {
   //    init_for_test(admin);
   //    let owner_1_address = signer::address_of(owner_1);
   //    let owner_2_address = signer::address_of(owner_2);
   //    let token_address = item::mint_to(admin, string::utf8(b"Token #1"), owner_1_address);
   //    let token_object = object::address_to_object<Token>(token_address);
   //    assert!(object::is_owner(token_object, owner_1_address), 0);

   //    // owner_2 tries to transfer the token to themself, but fails because they are not the admin
   //    item::transfer(owner_2, token_object, owner_2_address);
   // }


}