module admin_addr::item {
    use admin_addr::utils;

    friend admin_addr::initialize;

    public(friend) fun initialize(admin: &signer) {
        utils::assert_is_admin(admin);
    }
}
