module admin_addr::initialize {
    use admin_addr::aura_token;
    use admin_addr::fuse_block;
    use admin_addr::item;
    use admin_addr::creator;

    #[test_only]
    use std::features;

    fun init_module(admin: &signer) {
        creator::initialize(admin);
        aura_token::initialize(admin);
        fuse_block::initialize(admin);
        item::initialize(admin);
    }

    #[test_only]
    public fun enable_features_for_test(aptos_framework: &signer) {
        let auids = features::get_auids();
        let module_events = features::get_module_event_feature();
        features::change_feature_flags(aptos_framework, vector[auids, module_events], vector[]);
    }

    #[test_only]
    public fun init_module_for_test(admin: &signer, aptos_framework: &signer) {
        enable_features_for_test(aptos_framework);
        init_module(admin);
    }
}
