/******************************************************************************/
/*                                                                            */
/* SPDX-License-Identifier: MIT                                               */
/* Copyright (c) [2023] Serokell <hi@serokell.io>                             */
/*                                                                            */
/******************************************************************************/

use super::{Instruction, Stage, Value};

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum TypecheckedStage {}

impl Stage for TypecheckedStage {
    type AddMeta = overloads::Add;
    type PushValue = Value;
}

pub type TypecheckedInstruction = Instruction<TypecheckedStage>;

pub mod overloads {
    #[derive(Debug, PartialEq, Eq, Clone, Copy)]
    pub enum Add {
        IntInt,
        NatNat,
        MutezMutez,
    }
}
