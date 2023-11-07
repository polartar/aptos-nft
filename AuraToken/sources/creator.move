/// This module is used to create an automated signer for the contract,
/// facilitating automatic minting without the admin having to manually do it.
/// Only friended modules can call `get_signer()`
module admin_addr::creator {
    use std::signer;
    use aptos_framework::object::{Self, ExtendRef};
    use admin_addr::utils;

    friend admin_addr::aura_token;
    friend admin_addr::item;
    friend admin_addr::fuse_block;
    friend admin_addr::initialize;
    #[test_only]
    friend admin_addr::aura_token_test;

    struct Creator has key {
        extend_ref: ExtendRef,
    }

    public(friend) fun initialize(admin: &signer) {
        utils::assert_is_admin(admin);
        let admin_addr = signer::address_of(admin);
        let constructor_ref = object::create_object(admin_addr);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        // move the Creator's extend ref to the contract's address space in global storage
        // so we can easily use/access it
        move_to<Creator>(
            admin,
            Creator {
                extend_ref: extend_ref,
            },
        );
    }

    // only callable by friended modules, declared above. These do not need to be in the package
    public(friend) fun get_signer(): signer acquires Creator {
        let extend_ref = &borrow_global<Creator>(@admin_addr).extend_ref;
        object::generate_signer_for_extending(extend_ref)
    }

    public(friend) fun get_address(): address acquires Creator {
        let extend_ref = &borrow_global<Creator>(@admin_addr).extend_ref;
        object::address_from_extend_ref(extend_ref)
    }
}
