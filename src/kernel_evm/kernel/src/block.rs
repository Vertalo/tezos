// SPDX-FileCopyrightText: 2023 Nomadic Labs <contact@nomadic-labs.com>
//
// SPDX-License-Identifier: MIT

use crate::blueprint::Queue;
use crate::error::{Error, TransferError};
use crate::helpers::address_to_hash;
use crate::inbox::Transaction;
use crate::storage;
use host::path::OwnedPath;
use host::rollup_core::RawRollupCore;
use host::runtime::Runtime;
use tezos_ethereum::eth_gen::{L2Level, OwnedHash, Quantity, RawTransaction, TransactionHash};
use tezos_ethereum::wei::Wei;

use debug::debug_msg;

// Used by Transaction.nonce.to_u64, the trait must be in scope for the function
// to be available
use num_traits::ToPrimitive;

pub struct L2Block {
    // This choice of a L2 block representation is totally
    // arbitrarily based on what is an Ethereum block and is
    // subject to change.
    pub number: L2Level,
    pub hash: OwnedHash, // 32 bytes
    pub parent_hash: OwnedHash,
    pub nonce: Quantity,
    pub sha3_uncles: OwnedHash,
    pub logs_bloom: Option<OwnedHash>,
    pub transactions_root: OwnedHash,
    pub state_root: OwnedHash,
    pub receipts_root: OwnedHash,
    pub miner: OwnedHash,
    pub difficulty: Quantity,
    pub total_difficulty: Quantity,
    pub extra_data: OwnedHash,
    pub size: Quantity,
    pub gas_limit: Quantity,
    pub gas_used: Quantity,
    pub timestamp: Quantity,
    pub transactions: Vec<TransactionHash>,
    pub uncles: Vec<OwnedHash>,
}

impl L2Block {
    // dead code is allowed in this implementation because the following constants
    // are not used outside the scope of L2Block
    #![allow(dead_code)]

    const DUMMY_QUANTITY: Quantity = 0;
    const DUMMY_HASH: &str = "0000000000000000000000000000000000000000";

    fn dummy_hash() -> OwnedHash {
        L2Block::DUMMY_HASH.into()
    }

    pub fn new(number: L2Level, transactions: Vec<TransactionHash>) -> Self {
        L2Block {
            number,
            hash: L2Block::dummy_hash(),
            parent_hash: L2Block::dummy_hash(),
            nonce: L2Block::DUMMY_QUANTITY,
            sha3_uncles: L2Block::dummy_hash(),
            logs_bloom: None,
            transactions_root: L2Block::dummy_hash(),
            state_root: L2Block::dummy_hash(),
            receipts_root: L2Block::dummy_hash(),
            miner: L2Block::dummy_hash(),
            difficulty: L2Block::DUMMY_QUANTITY,
            total_difficulty: L2Block::DUMMY_QUANTITY,
            extra_data: L2Block::dummy_hash(),
            size: L2Block::DUMMY_QUANTITY,
            gas_limit: L2Block::DUMMY_QUANTITY,
            gas_used: L2Block::DUMMY_QUANTITY,
            timestamp: L2Block::DUMMY_QUANTITY,
            transactions,
            uncles: Vec::new(),
        }
    }
}

fn get_tx_sender(tx: &RawTransaction) -> Result<(OwnedHash, OwnedPath), Error> {
    match tx.sender() {
        // We reencode in hexadecimal, since the accounts hash are encoded in
        // hexadecimal in the storage.
        Ok(address) => {
            let hash = address_to_hash(address);
            let path = storage::account_path(&hash)?;
            Ok((hash, path))
        }
        Err(_) => Err(Error::Generic),
    }
}

// A transaction is valid if the signature is valid, its nonce is valid and it
// can pay for the gas
fn validate_transaction<Host: Runtime + RawRollupCore>(
    host: &mut Host,
    transaction: &Transaction,
) -> Result<(), Error> {
    let tx = &transaction.tx;
    let (_, src) = get_tx_sender(tx)?;
    let src_balance = storage::read_account_balance(host, &src).unwrap_or_else(|_| Wei::zero());
    let src_nonce = storage::read_account_nonce(host, &src).unwrap_or(0u64);
    let nonce = tx.nonce.to_u64().ok_or(Error::Generic)?;
    // For now, we consider there's no gas to pay
    let gas = Wei::zero();

    if !tx.is_valid() {
        Err(Error::Transfer(TransferError::InvalidSignature))
    } else if src_nonce != nonce {
        Err(Error::Transfer(TransferError::InvalidNonce))
    } else if src_balance < gas {
        Err(Error::Transfer(TransferError::NotEnoughBalance))
    } else {
        Ok(())
    }
}

fn validate<Host: Runtime + RawRollupCore>(
    host: &mut Host,
    block: L2Block,
    transactions: &[Transaction],
) -> Result<L2Block, Error> {
    transactions
        .iter()
        .try_for_each(|tx| validate_transaction(host, tx))?;
    Ok(block)
}

pub fn produce<Host: Runtime + RawRollupCore>(host: &mut Host, queue: Queue) {
    for proposal in queue.proposals.iter() {
        let current_level = storage::read_current_block_number(host);
        let next_level = match current_level {
            Ok(current_level) => current_level + 1,
            Err(_) => 0,
        };

        let transaction_hashes = proposal.transactions.iter().map(|tx| tx.tx_hash).collect();
        let candidate_block = L2Block::new(next_level, transaction_hashes);

        match validate(host, candidate_block, &proposal.transactions) {
            Ok(valid_block) => {
                storage::store_current_block(host, valid_block).unwrap_or_else(|_| {
                    panic!("Error while storing the current block: stopping the daemon.")
                });
            }
            Err(e) => debug_msg!(host; "Blueprint is invalid: {:?}\n", e),
        }
    }
}
