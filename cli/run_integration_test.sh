#!/bin/bash

# Automate full evm_demo workflow

TEST_SUI=1
TEST_ETH=1


# Parse command-line flags
for arg in "$@"; do
  case $arg in
    --skip-sui)    TEST_SUI=0 ;;
    --skip-eth)    TEST_ETH=0 ;;
    *) ;;
  esac
done

if [[ $TEST_SUI -eq 1 ]]; then
    echo "Start testing SUI-BSV bridge..."

    # Step 1: Setup
    python3 -m sui_demo setup --network regtest

    # Step 2: Pegin (deposit)   
    python3 -m sui_demo pegin --user alice --pegin-amount 42000000000 --network regtest

    # Step 3: Transfer
    python3 -m sui_demo transfer --sender alice --receiver bob --token-index 0 --network regtest

    # Step 4: Burn
    python3 -m sui_demo burn --user bob --token-index 0 --network regtest

    # Step 5: Pegout (withdrawal)
    python3 -m sui_demo pegout --user bob --token-index 0 --network regtest --update

    echo "SUI-BSV bridge test completed!"
fi

if [[ $TEST_ETH -eq 1 ]]; then
    echo "Start testing ETH-BSV bridge..."

    # Step 1: Setup
    python3 -m evm_demo setup

    # Step 2: Pegin (deposit)
    python3 -m evm_demo pegin --user alice --pegin-amount 10 --network regtest

    # Step 3: Transfer
    python3 -m evm_demo transfer --sender alice --receiver bob --token-index 0 --network regtest

    # Step 4: Burn
    python3 -m evm_demo burn --user bob --token-index 0 --network regtest

    # Step 5: Pegout (withdrawal)
    python3 -m evm_demo pegout

    echo "ETH-BSV bridge test completed!"
fi