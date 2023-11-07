module admin_addr::utils {
    use std::signer;
    use std::error;
    use std::string::{Self, String};
    use aptos_std::string_utils;

    /// You are not authorized to perform this operation.
    const E_NOT_ADMIN: u64 = 0;

    public fun assert_is_admin(admin: &signer) {
        assert!(signer::address_of(admin) == @admin_addr, error::permission_denied(E_NOT_ADMIN));
    }

    public inline fun concat<T>(s: String, n: T): String {
       let n_str = string_utils::to_string(&n);
       string::append(&mut s, n_str);
       s
   }
}
