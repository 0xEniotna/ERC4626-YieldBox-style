use starknet::ContractAddress;

#[starknet::component]
mod ERC4626Component {
    use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use openzeppelin::introspection::src5::SRC5Component;
    
    use erc4626::erc4626::interface::{
        IERC4626Additional, IERC4626Snake, IERC4626Camel, IERC4626Metadata
    };
    use erc4626::utils::{pow_256};
    use integer::BoundedU256;
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait,
    };
    use openzeppelin::token::erc20::{
        ERC20Component,
        ERC20HooksEmptyImpl, 
        ERC20Component::Errors as ERC20Errors
    };
    use openzeppelin::token::erc20::ERC20Component::InternalTrait as ERC20InternalTrait;

    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        asset: ContractAddress,
        underlying_decimals: u8,
        offset: u8,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        sender: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        sender: ContractAddress,
        #[key]
        receiver: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    mod Errors {
        const EXCEEDED_MAX_DEPOSIT: felt252 = 'ERC4626: exceeded max deposit';
        const EXCEEDED_MAX_MINT: felt252 = 'ERC4626: exceeded max mint';
        const EXCEEDED_MAX_REDEEM: felt252 = 'ERC4626: exceeded max redeem';
        const EXCEEDED_MAX_WITHDRAW: felt252 = 'ERC4626: exceeded max withdraw';
    }

    pub trait ERC4626HooksTrait<TContractState> {
        fn before_deposit(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
        );
        fn after_deposit(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
        );
        fn before_withdraw(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256
        );
        fn after_withdraw(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256
        );
    }

    #[embeddable_as(ERC4626AdditionalImpl)]
    impl ERC4626Additional<
        TContractState, +HasComponent<TContractState>,
        +ERC20Component::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +ERC4626HooksTrait<TContractState>,
        +Drop<TContractState>
    > of IERC4626Additional<ComponentState<TContractState>> {
        fn asset(self: @ComponentState<TContractState>) -> ContractAddress {
            self.asset.read()
        }

        fn convert_to_assets(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, false)
        }

        fn convert_to_shares(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, false)
        }

        fn deposit(ref self: ComponentState<TContractState>, assets: u256, receiver: ContractAddress) -> u256 {
            let max_assets = self.max_deposit(receiver);
            assert(max_assets >= assets, Errors::EXCEEDED_MAX_DEPOSIT);

            let caller = get_caller_address();
            let shares = self.preview_deposit(assets);
            self._deposit(caller, receiver, assets, shares);

            shares
        }

        fn max_deposit(self: @ComponentState<TContractState>, address: ContractAddress) -> u256 {
            BoundedU256::max()
        }

        fn max_mint(self: @ComponentState<TContractState>, receiver: ContractAddress) -> u256 {
            BoundedU256::max()
        }

        fn max_redeem(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            self.balance_of(owner)
        }

        fn max_withdraw(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            let balance = self.balance_of(owner);
            self._convert_to_assets(balance, false)
        }

        fn mint(ref self: ComponentState<TContractState>, shares: u256, receiver: ContractAddress) -> u256 {
            let max_shares = self.max_mint(receiver);
            assert(max_shares >= shares, Errors::EXCEEDED_MAX_MINT);

            let caller = get_caller_address();
            let assets = self.preview_mint(shares);
            self._deposit(caller, receiver, assets, shares);

            assets
        }

        fn preview_deposit(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, false)
        }

        fn preview_mint(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, true)
        }

        fn preview_redeem(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, false)
        }

        fn preview_withdraw(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, true)
        }

        fn redeem(
            ref self: ComponentState<TContractState>, shares: u256, receiver: ContractAddress, owner: ContractAddress
        ) -> u256 {
            let max_shares = self.max_redeem(owner);
            assert(shares <= max_shares, Errors::EXCEEDED_MAX_REDEEM);

            let caller = get_caller_address();
            let assets = self.preview_redeem(shares);
            self._withdraw(caller, receiver, owner, assets, shares);
            assets
        }

        fn total_assets(self: @ComponentState<TContractState>) -> u256 {
            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.balanceOf(get_contract_address())
        }

        fn withdraw(
            ref self: ComponentState<TContractState>, assets: u256, receiver: ContractAddress, owner: ContractAddress
        ) -> u256 {
            let max_assets = self.max_withdraw(owner);
            assert(assets <= max_assets, Errors::EXCEEDED_MAX_WITHDRAW);

            let caller = get_caller_address();
            let shares = self.preview_withdraw(assets);
            self._withdraw(caller, receiver, owner, assets, shares);

            shares
        }
    }


    #[embeddable_as(MetadataEntrypointsImpl)]
    impl MetadataEntrypoints<
        TContractState, +HasComponent<TContractState>,
        impl erc20: ERC20Component::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +ERC4626HooksTrait<TContractState>,
        +Drop<TContractState>
    > of IERC4626Metadata<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> ByteArray {
            let erc20_comp = get_dep_component!(ref self, erc20);
            erc20_comp.name()
        }
        fn symbol(self: @ComponentState<TContractState>) -> ByteArray {
            let erc20_comp = get_dep_component!(ref self, erc20);
            erc20_comp.symbol()
        }
        fn decimals(self: @ComponentState<TContractState>) -> u8 {
            self.underlying_decimals.read() + self._decimals_offset()
        }
    }

    #[embeddable_as(SnakeEntrypointsImpl)]
    impl SnakeEntrypoints<
        TContractState, +HasComponent<TContractState>,
        impl erc20: ERC20Component::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +ERC4626HooksTrait<TContractState>,
        +Drop<TContractState>
    > of IERC4626Snake<ComponentState<TContractState>> {
        fn total_supply(self: @ComponentState<TContractState>) -> u256 {
            let erc20_comp = get_dep_component!(ref self, erc20);
            erc20_comp.total_supply()
        }

        fn balance_of(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            let erc20_comp = get_dep_component!(ref self, erc20);
            erc20_comp.balance_of(account)
        }

        fn allowance(
            self: @ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            let erc20_comp = get_dep_component!(ref self, erc20);
            erc20_comp.allowance(owner, spender)
        }

        fn transfer(ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) -> bool {
            let mut erc20_comp_mut = get_dep_component_mut!(ref self, erc20);
            erc20_comp_mut.transfer(recipient, amount)
        }

        fn transfer_from(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let mut erc20_comp_mut = get_dep_component_mut!(ref self, erc20);
            erc20_comp_mut.transfer_from(sender, recipient, amount)
        }

        fn approve(ref self: ComponentState<TContractState>, spender: ContractAddress, amount: u256) -> bool {
            let mut erc20_comp_mut = get_dep_component_mut!(ref self, erc20);
            erc20_comp_mut.approve(spender, amount)
        }
    }

    #[embeddable_as(CamelEntrypointsImpl)]
    impl CamelEntrypoints<
        TContractState, +HasComponent<TContractState>,
        +ERC20Component::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +ERC4626HooksTrait<TContractState>,
        +Drop<TContractState>
    > of IERC4626Camel<ComponentState<TContractState>> {
        fn totalSupply(self: @ComponentState<TContractState>) -> u256 {
            self.total_supply()
        }
        fn balanceOf(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            self.transfer_from(sender, recipient, amount)
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
        impl erc20: ERC20Component::HasComponent<TContractState>,
        impl src5: SRC5Component::HasComponent<TContractState>,
        impl Hooks: ERC4626HooksTrait<TContractState>,
        +Drop<TContractState>
    > of InternalImplTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, asset: ContractAddress, name: ByteArray, symbol: ByteArray, offset: u8
        ) {
            let dispatcher = ERC20ABIDispatcher { contract_address: asset };
            self.offset.write(offset);
            let decimals = dispatcher.decimals();
            let mut erc20_comp_mut = get_dep_component_mut!(ref self, erc20);
            erc20_comp_mut.initializer(name, symbol);
            self.asset.write(asset);
            self.underlying_decimals.write(decimals);

            // ! To register interface
            // let mut src5_component = get_dep_component_mut!(ref self, src5);
            // src5_component.register_interface(interface::IERC721_ID);
            // src5_component.register_interface(interface::IERC721_METADATA_ID);
        }
        
        fn _convert_to_assets(self: @ComponentState<TContractState>, shares: u256, round: bool) -> u256 {
            let total_assets = self.total_assets() + 1;
            let total_shares = self.total_supply() + pow_256(10, self._decimals_offset());
            let assets = shares * total_assets / total_shares;
            if round && ((assets * total_shares) / total_assets < shares) {
                assets + 1
            } else {
                assets
            }
        }

        fn _convert_to_shares(self: @ComponentState<TContractState>, assets: u256, round: bool) -> u256 {
            let total_assets = self.total_assets() + 1;
            let total_shares = self.total_supply() + pow_256(10, self._decimals_offset());
            let share = assets * total_shares / total_assets;
            if round && ((share * total_assets) / total_shares < assets) {
                share + 1
            } else {
                share
            }
        }

        fn _deposit(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256
        ) {
            Hooks::before_deposit(ref self, caller, receiver, assets, shares); 

            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.transferFrom(caller, get_contract_address(), assets);
            let mut erc20_comp_mut = get_dep_component_mut!(ref self, erc20);
            erc20_comp_mut.mint(receiver, shares);
            self.emit(Deposit { sender: caller, owner: receiver, assets, shares });

            Hooks::after_deposit(ref self, caller, receiver, assets, shares);
        }

        fn _withdraw(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256
        ) {
            Hooks::before_withdraw(ref self, caller, receiver, owner, assets, shares);

            let mut erc20_comp_mut = get_dep_component_mut!(ref self, erc20);
            if (caller != owner) {
                let allowance = self.allowance(owner, caller);
                if (allowance != BoundedU256::max()) {
                    assert(allowance >= shares, ERC20Errors::APPROVE_FROM_ZERO);
                    erc20_comp_mut.ERC20_allowances.write((owner, caller), allowance - shares);
                }
            }

            erc20_comp_mut.burn(owner, shares);

            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.transfer(receiver, assets);

            self.emit(Withdraw { sender: caller, receiver, owner, assets, shares });

            Hooks::after_withdraw(ref self, caller, receiver, owner, assets, shares);
        }

        fn _decimals_offset(self: @ComponentState<TContractState>) -> u8 {
            self.offset.read()
        }
    }
}

impl ERC4626HooksEmptyImpl<TContractState> of ERC4626Component::ERC4626HooksTrait<TContractState> {
    fn before_deposit(
        ref self: ERC4626Component::ComponentState<TContractState>,
        caller: ContractAddress,
        receiver: ContractAddress,
        assets: u256,
        shares: u256
    ) {}
    fn after_deposit(
        ref self: ERC4626Component::ComponentState<TContractState>,
        caller: ContractAddress,
        receiver: ContractAddress,
        assets: u256,
        shares: u256
    ) {}

    fn before_withdraw(
        ref self: ERC4626Component::ComponentState<TContractState>,
        caller: ContractAddress,
        receiver: ContractAddress,
        owner: ContractAddress,
        assets: u256,
        shares: u256
    ) {}
    fn after_withdraw(
        ref self: ERC4626Component::ComponentState<TContractState>,
        caller: ContractAddress,
        receiver: ContractAddress,
        owner: ContractAddress,
        assets: u256,
        shares: u256
    ) {}
}