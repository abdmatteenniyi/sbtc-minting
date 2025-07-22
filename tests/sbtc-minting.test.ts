// Cl is available globally through the clarinet environment

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const deployer = accounts.get("deployer")!;

describe("sBTC Minting Contract Tests", () => {
  beforeEach(() => {
    simnet.setEpoch("3.1");
  });

  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("should set BTC price by contract owner", () => {
    const { result } = simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    expect(result).toBeOk(Cl.uint(60000));
  });

  it("should reject BTC price setting by non-owner", () => {
    const { result } = simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], address1);
    expect(result).toBeErr(Cl.uint(100)); // ERR_UNAUTHORIZED
  });

  it("should get BTC price", () => {
    // First set the price
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    
    const { result } = simnet.callReadOnlyFn("sbtc-minting", "get-btc-price", [], address1);
    expect(result).toBeOk(Cl.uint(60000));
  });

  it("should lock collateral and mint tokens", () => {
    // Set BTC price first
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    
    // Lock 1 BTC (100000000 satoshis) and mint 30000 sUSD
    const { result } = simnet.callPublicFn("sbtc-minting", "lock-and-mint", 
      [Cl.uint(100000000), Cl.uint(30000)], address1);
    expect(result).toBeOk(Cl.uint(30000));
  });

  it("should reject insufficient collateral", () => {
    // Set BTC price first
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    
    // Try to mint too much with insufficient collateral
    const { result } = simnet.callPublicFn("sbtc-minting", "lock-and-mint", 
      [Cl.uint(100000000), Cl.uint(50000)], address1);
    expect(result).toBeErr(Cl.uint(101)); // ERR_INSUFFICIENT_COLLATERAL
  });

  it("should get user vault information", () => {
    // Set BTC price and create vault
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    simnet.callPublicFn("sbtc-minting", "lock-and-mint", 
      [Cl.uint(100000000), Cl.uint(30000)], address1);
    
    const { result } = simnet.callReadOnlyFn("sbtc-minting", "get-user-vault", [Cl.principal(address1)], address1);
    expect(result).toBeTuple({
      collateral: Cl.uint(100000000),
      debt: Cl.uint(30000)
    });
  });

  it("should calculate collateral ratio correctly", () => {
    const { result } = simnet.callReadOnlyFn("sbtc-minting", "get-collateral-ratio", 
      [Cl.uint(100000000), Cl.uint(30000)], address1);
    // With BTC at $60,000, 1 BTC = $60,000, debt = $30,000
    // Ratio should be 200% (20000 in basis points)
    expect(result).toBeOk(Cl.uint(20000));
  });

  it("should burn tokens and unlock collateral", () => {
    // Set BTC price and create vault
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    simnet.callPublicFn("sbtc-minting", "lock-and-mint", 
      [Cl.uint(100000000), Cl.uint(30000)], address1);
    
    // Burn half the debt
    const { result } = simnet.callPublicFn("sbtc-minting", "burn-and-unlock", 
      [Cl.uint(15000)], address1);
    expect(result).toBeOk(Cl.uint(25000000)); // Should unlock some BTC
  });

  it("should check if vault is safe", () => {
    // Set BTC price and create vault
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    simnet.callPublicFn("sbtc-minting", "lock-and-mint", 
      [Cl.uint(100000000), Cl.uint(30000)], address1);
    
    const { result } = simnet.callReadOnlyFn("sbtc-minting", "is-vault-safe", [Cl.principal(address1)], address1);
    expect(result).toBeOk(Cl.bool(true));
  });

  it("should calculate maximum mint amount", () => {
    // Set BTC price first
    simnet.callPublicFn("sbtc-minting", "set-btc-price", [Cl.uint(60000)], deployer);
    
    const { result } = simnet.callReadOnlyFn("sbtc-minting", "calculate-max-mint", 
      [Cl.uint(100000000)], address1);
    // With 1 BTC at $60,000 and 150% collateral ratio, max mint = $40,000
    expect(result).toBeOk(Cl.uint(40000));
  });
});