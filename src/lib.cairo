pub mod erc4626 {
    pub mod erc4626;
    pub mod interface;
}
mod preset {
    pub mod ERC4626;
}

#[cfg(test)]
mod tests;
mod utils;
mod mocks {
    mod ERC20;
}
