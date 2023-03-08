// SPDX-FileCopyrightText: 2023 Nomadic Labs <contact@nomadic-labs.com>
//
// SPDX-License-Identifier: MIT
use host::path::PathError;

use host::runtime::RuntimeError;
use std::str::Utf8Error;

#[derive(Debug)]
pub enum TransferError {
    InvalidSignature,
    InvalidNonce,
    NotEnoughBalance,
}

#[derive(Debug)]
pub enum Error {
    Path(PathError),
    Runtime(RuntimeError),
    Transfer(TransferError),
    Generic,
}

impl From<PathError> for Error {
    fn from(e: PathError) -> Self {
        Self::Path(e)
    }
}
impl From<RuntimeError> for Error {
    fn from(e: RuntimeError) -> Self {
        Self::Runtime(e)
    }
}

impl From<Utf8Error> for Error {
    fn from(_: Utf8Error) -> Self {
        Self::Generic
    }
}
