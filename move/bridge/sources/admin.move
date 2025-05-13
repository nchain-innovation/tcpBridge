module tcpbridge::admin;

public struct BridgeAdmin has key, store {
    id: UID,
}

fun init(ctx: &mut TxContext) {
    let bridge_admin_cap = BridgeAdmin { id: object::new(ctx) };
    transfer::public_transfer(bridge_admin_cap, ctx.sender());
}

#[test_only]
public(package) fun new_admin_cap(ctx: &mut TxContext) {
    let bridge_admin_cap = BridgeAdmin { id: object::new(ctx) };
    transfer::public_transfer(bridge_admin_cap, ctx.sender());
}
