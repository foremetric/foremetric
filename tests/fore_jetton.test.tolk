import "fore_jetton.fc";
import "jetton_wallet.fc";

;; Test configuration
const int INITIAL_SUPPLY = 10000000000000000; ;; 100M FORE in nanoFORE
const int MAX_SUPPLY = 100000000000000000; ;; 1B FORE in nanoFORE
const int DECIMALS = 9;

;; Helper functions for testing
int equal_slices(slice a, slice b) inline {
    return equal_slices_bits(a, b) & (a.slice_refs() == b.slice_refs());
}

;; Test mint functionality
() test_mint() impure {
    ;; Setup
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice recipient = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    int mint_amount = 1000000000; ;; 1 FORE
    
    ;; Test successful mint
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    int result = mint_tokens(state, admin_address, recipient, mint_amount);
    throw_unless(100, result == 0); ;; Success
    
    ;; Test mint exceeding max supply
    int large_amount = MAX_SUPPLY;
    result = mint_tokens(state, admin_address, recipient, large_amount);
    throw_unless(101, result != 0); ;; Should fail
    
    ;; Test unauthorized mint
    slice unauthorized = "0:3333333333333333333333333333333333333333333333333333333333333333"a;
    result = mint_tokens(state, unauthorized, recipient, mint_amount);
    throw_unless(102, result != 0); ;; Should fail
}

;; Test burn functionality
() test_burn() impure {
    ;; Setup
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice holder = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    int burn_amount = 1000000000; ;; 1 FORE
    
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; First mint some tokens to burn
    mint_tokens(state, admin_address, holder, burn_amount * 2);
    
    ;; Test successful burn
    int result = burn_tokens(state, holder, burn_amount);
    throw_unless(200, result == 0); ;; Success
    
    ;; Test burn more than balance
    result = burn_tokens(state, holder, burn_amount * 10);
    throw_unless(201, result != 0); ;; Should fail
    
    ;; Test burn from empty wallet
    slice empty_holder = "0:4444444444444444444444444444444444444444444444444444444444444444"a;
    result = burn_tokens(state, empty_holder, burn_amount);
    throw_unless(202, result != 0); ;; Should fail
}

;; Test transfer functionality
() test_transfer() impure {
    ;; Setup
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice sender = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    slice recipient = "0:3333333333333333333333333333333333333333333333333333333333333333"a;
    int transfer_amount = 1000000000; ;; 1 FORE
    
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; First mint tokens to sender
    mint_tokens(state, admin_address, sender, transfer_amount * 2);
    
    ;; Test successful transfer
    int result = transfer_tokens(state, sender, recipient, transfer_amount, 0);
    throw_unless(300, result == 0); ;; Success
    
    ;; Test transfer more than balance
    result = transfer_tokens(state, sender, recipient, transfer_amount * 10, 0);
    throw_unless(301, result != 0); ;; Should fail
    
    ;; Test transfer to same address
    result = transfer_tokens(state, sender, sender, transfer_amount, 0);
    throw_unless(302, result != 0); ;; Should fail
    
    ;; Test zero amount transfer
    result = transfer_tokens(state, sender, recipient, 0, 0);
    throw_unless(303, result != 0); ;; Should fail
}

;; Test supply limits
() test_supply_limits() impure {
    ;; Setup
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice recipient = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; Test minting up to max supply
    int remaining_supply = MAX_SUPPLY - INITIAL_SUPPLY;
    int result = mint_tokens(state, admin_address, recipient, remaining_supply);
    throw_unless(400, result == 0); ;; Should succeed
    
    ;; Test minting beyond max supply
    result = mint_tokens(state, admin_address, recipient, 1);
    throw_unless(401, result != 0); ;; Should fail
    
    ;; Test burning reduces total supply
    int burn_amount = 1000000000;
    burn_tokens(state, recipient, burn_amount);
    
    ;; Should be able to mint again after burning
    result = mint_tokens(state, admin_address, recipient, burn_amount);
    throw_unless(402, result == 0); ;; Should succeed
}

;; Test jetton data getters
() test_jetton_data() impure {
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; Test get_jetton_data
    (int total_supply, int mintable, slice admin, cell content, cell wallet_code) = get_jetton_data(state);
    
    throw_unless(500, total_supply == INITIAL_SUPPLY);
    throw_unless(501, mintable == -1); ;; True
    throw_unless(502, equal_slices(admin, admin_address));
    
    ;; Test metadata content
    slice content_slice = content.begin_parse();
    int content_type = content_slice~load_uint(8);
    throw_unless(503, content_type == 0); ;; On-chain content
    
    ;; Test get_wallet_address
    slice user_address = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    slice wallet_addr = get_wallet_address(state, user_address);
    throw_unless(504, wallet_addr.slice_bits() == 267); ;; Valid address format
}

;; Test wallet operations
() test_wallet_operations() impure {
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice user_address = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    
    cell jetton_state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    cell wallet_state = init_wallet_state(user_address, jetton_state);
    
    ;; Test wallet data
    (int balance, slice owner, slice jetton) = get_wallet_data(wallet_state);
    throw_unless(600, balance == 0);
    throw_unless(601, equal_slices(owner, user_address));
    
    ;; Test wallet balance updates
    int mint_amount = 1000000000;
    mint_tokens(jetton_state, admin_address, user_address, mint_amount);
    
    ;; Update wallet state and check balance
    (balance, owner, jetton) = get_wallet_data(wallet_state);
    throw_unless(602, balance == mint_amount);
}

;; Test edge cases
() test_edge_cases() impure {
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice user_address = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; Test maximum single mint
    int max_single_mint = MAX_SUPPLY - INITIAL_SUPPLY;
    int result = mint_tokens(state, admin_address, user_address, max_single_mint);
    throw_unless(700, result == 0);
    
    ;; Test minimum transfer (1 nanoFORE)
    result = transfer_tokens(state, user_address, admin_address, 1, 0);
    throw_unless(701, result == 0);
    
    ;; Test burn entire balance
    (int balance, , ) = get_wallet_data(get_wallet_state(user_address, state));
    result = burn_tokens(state, user_address, balance);
    throw_unless(702, result == 0);
    
    ;; Test operations with zero total supply
    burn_tokens(state, admin_address, INITIAL_SUPPLY - 1); ;; Burn remaining initial supply
    
    ;; Should still be able to mint
    result = mint_tokens(state, admin_address, user_address, 1000000000);
    throw_unless(703, result == 0);
}

;; Test admin operations
() test_admin_operations() impure {
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice new_admin = "0:3333333333333333333333333333333333333333333333333333333333333333"a;
    slice user_address = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; Test admin change
    int result = change_admin(state, admin_address, new_admin);
    throw_unless(800, result == 0);
    
    ;; Test old admin can't mint
    result = mint_tokens(state, admin_address, user_address, 1000000000);
    throw_unless(801, result != 0); ;; Should fail
    
    ;; Test new admin can mint
    result = mint_tokens(state, new_admin, user_address, 1000000000);
    throw_unless(802, result == 0); ;; Should succeed
    
    ;; Test unauthorized admin change
    slice unauthorized = "0:4444444444444444444444444444444444444444444444444444444444444444"a;
    result = change_admin(state, unauthorized, admin_address);
    throw_unless(803, result != 0); ;; Should fail
}

;; Test gas consumption limits
() test_gas_limits() impure {
    slice admin_address = "0:1111111111111111111111111111111111111111111111111111111111111111"a;
    slice user_address = "0:2222222222222222222222222222222222222222222222222222222222222222"a;
    
    cell state = init_jetton_state(admin_address, INITIAL_SUPPLY, MAX_SUPPLY);
    
    ;; Test operations complete within gas limits
    int gas_before = gas_consumed();
    
    mint_tokens(state, admin_address, user_address, 1000000000);
    transfer_tokens(state, user_address, admin_address, 500000000, 0);
    burn_tokens(state, admin_address, 500000000);
    
    int gas_after = gas_consumed();
    int gas_used = gas_after - gas_before;
    
    ;; Should complete within reasonable gas limits (adjust as needed)
    throw_unless(900, gas_used < 50000); ;; 50k gas units
}

;; Main test runner
() main() impure {
    test_mint();
    test_burn();
    test_transfer();
    test_supply_limits();
    test_jetton_data();
    test_wallet_operations();
    test_edge_cases();
    test_admin_operations();
    test_gas_limits();
}