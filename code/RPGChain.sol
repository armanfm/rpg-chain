// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * RPGChain — Sistema de Integridade Narrativa
 *
 * Filosofia:
 *   - O NFT representa autoridade narrativa da crônica, não personagem
 *   - On-chain armazena APENAS: hash, versão, xpSaldo, timestamp, cronicaId
 *   - A ficha completa fica LOCAL (PouchDB do jogador / mestre)
 *   - Qualquer um pode verificar se um hash foi aprovado pelo mestre
 *
 * Fluxo:
 *   1. Mestre chama criarCronica() → minta NFT da crônica
 *   2. Jogador envia ficha.json ao mestre
 *   3. Gemini do mestre valida → mestre aprova
 *   4. Mestre chama aprovarFicha() → hash fica on-chain
 *   5. Jogador verifica integridade no combate via verificarFicha()
 */

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}

contract RPGChain is IERC721 {

    // ─── NFT state ────────────────────────────────────────────────────────────
    string public name   = "RPGChain Cronica";
    string public symbol = "RPGC";

    uint256 private _nextId = 1;

    mapping(uint256 => address) private _owner;
    mapping(uint256 => address) private _approved;
    mapping(address => uint256) private _balance;

    // ─── Crônica ──────────────────────────────────────────────────────────────
    struct Cronica {
        string  nome;
        string  narrador;
        address mestre;
        uint256 criadaEm;
        bool    ativa;
    }

    mapping(uint256 => Cronica) public cronicas;

    // ─── Ficha aprovada ───────────────────────────────────────────────────────
    struct FichaState {
        uint256 cronicaId;   // qual crônica aprovou
        uint256 versao;      // versão da ficha
        int256  xpSaldo;     // pode ser negativo (dívida narrativa)
        uint256 aprovadaEm;  // timestamp
        bool    existe;
    }

    // hash (bytes32) → estado aprovado
    mapping(bytes32 => FichaState) public fichas;

    // crônica → lista de hashes aprovados
    mapping(uint256 => bytes32[]) private _cronicaHashes;

    // ─── Eventos ──────────────────────────────────────────────────────────────
    event CronicaCriada(
        uint256 indexed cronicaId,
        string  nome,
        address indexed mestre
    );

    event FichaAprovada(
        uint256 indexed cronicaId,
        bytes32 indexed fichaHash,
        uint256 versao,
        int256  xpSaldo
    );

    event FichaRevogada(
        uint256 indexed cronicaId,
        bytes32 indexed fichaHash
    );

    event CronicaEncerrada(uint256 indexed cronicaId);

    // ─── Modifiers ────────────────────────────────────────────────────────────
    modifier apenasOwner(uint256 cronicaId) {
        require(ownerOf(cronicaId) == msg.sender, "RPGChain: nao e o dono da cronica");
        _;
    }

    modifier cronicaAtiva(uint256 cronicaId) {
        require(cronicas[cronicaId].ativa, "RPGChain: cronica encerrada");
        _;
    }

    // ─── ERC-721 mínimo ───────────────────────────────────────────────────────
    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owner[tokenId];
        require(owner != address(0), "RPGChain: token inexistente");
        return owner;
    }

    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "RPGChain: endereco zero");
        return _balance[owner];
    }

    function approve(address to, uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "RPGChain: sem permissao");
        _approved[tokenId] = to;
        emit Approval(msg.sender, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owner[tokenId] != address(0), "RPGChain: token inexistente");
        return _approved[tokenId];
    }

    function transferFrom(address from, address to, uint256 tokenId) external override {
        require(
            ownerOf(tokenId) == msg.sender ||
            getApproved(tokenId) == msg.sender,
            "RPGChain: sem permissao"
        );
        require(to != address(0), "RPGChain: endereco zero");
        _balance[from]--;
        _balance[to]++;
        _owner[tokenId] = to;
        delete _approved[tokenId];
        // Atualiza mestre na crônica ao transferir NFT
        cronicas[tokenId].mestre = to;
        emit Transfer(from, to, tokenId);
    }

    // supportsInterface básico
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x80ac58cd; // ERC721
    }

    // ─── Crônica ──────────────────────────────────────────────────────────────

    /**
     * @dev Cria uma nova crônica e minta o NFT de autoridade narrativa.
     * @param nome        Nome da crônica (ex: "Praga Sombria")
     * @param narrador    Nome do narrador
     * @return cronicaId  ID do NFT criado
     */
    function criarCronica(
        string calldata nome,
        string calldata narrador
    ) external returns (uint256 cronicaId) {
        require(bytes(nome).length > 0, "RPGChain: nome vazio");

        cronicaId = _nextId++;

        _owner[cronicaId]   = msg.sender;
        _balance[msg.sender]++;

        cronicas[cronicaId] = Cronica({
            nome:      nome,
            narrador:  narrador,
            mestre:    msg.sender,
            criadaEm:  block.timestamp,
            ativa:     true
        });

        emit Transfer(address(0), msg.sender, cronicaId);
        emit CronicaCriada(cronicaId, nome, msg.sender);
    }

    /**
     * @dev Encerra a crônica (não queima o NFT, apenas marca inativa).
     */
    function encerrarCronica(uint256 cronicaId)
        external
        apenasOwner(cronicaId)
    {
        cronicas[cronicaId].ativa = false;
        emit CronicaEncerrada(cronicaId);
    }

    // ─── Fichas ───────────────────────────────────────────────────────────────

    /**
     * @dev Aprova o hash de uma ficha, vinculando à crônica do mestre.
     *
     *      O hash deve ser o SHA-256 do JSON da ficha (normalizado com chaves
     *      ordenadas), convertido para bytes32 pelo frontend.
     *
     * @param cronicaId  ID do NFT da crônica
     * @param fichaHash  SHA-256 do JSON da ficha (bytes32)
     * @param versao     Número de versão da ficha
     * @param xpSaldo    Saldo de XP (pode ser negativo = dívida narrativa)
     */
    function aprovarFicha(
        uint256 cronicaId,
        bytes32 fichaHash,
        uint256 versao,
        int256  xpSaldo
    )
        external
        apenasOwner(cronicaId)
        cronicaAtiva(cronicaId)
    {
        require(fichaHash != bytes32(0), "RPGChain: hash invalido");

        fichas[fichaHash] = FichaState({
            cronicaId:  cronicaId,
            versao:     versao,
            xpSaldo:    xpSaldo,
            aprovadaEm: block.timestamp,
            existe:     true
        });

        _cronicaHashes[cronicaId].push(fichaHash);

        emit FichaAprovada(cronicaId, fichaHash, versao, xpSaldo);
    }

    /**
     * @dev Revoga a aprovação de uma ficha (ex: jogador saiu da campanha).
     */
    function revogarFicha(uint256 cronicaId, bytes32 fichaHash)
        external
        apenasOwner(cronicaId)
    {
        require(fichas[fichaHash].existe, "RPGChain: ficha nao aprovada");
        require(fichas[fichaHash].cronicaId == cronicaId, "RPGChain: cronica errada");

        delete fichas[fichaHash];
        emit FichaRevogada(cronicaId, fichaHash);
    }

    // ─── Views públicas ───────────────────────────────────────────────────────

    /**
     * @dev Verifica se um hash de ficha foi aprovado.
     *      Pode ser chamado SEM carteira (leitura pública).
     *
     * @return aprovada    true se existe e aprovada
     * @return cronicaId   ID da crônica que aprovou
     * @return versao      Versão da ficha
     * @return xpSaldo     Saldo de XP no momento da aprovação
     * @return aprovadaEm  Timestamp da aprovação
     * @return nomeCronica Nome da crônica
     * @return mestre      Endereço do mestre que aprovou
     */
    function verificarFicha(bytes32 fichaHash)
        external
        view
        returns (
            bool    aprovada,
            uint256 cronicaId,
            uint256 versao,
            int256  xpSaldo,
            uint256 aprovadaEm,
            string  memory nomeCronica,
            address mestre
        )
    {
        FichaState memory s = fichas[fichaHash];
        aprovada   = s.existe;
        cronicaId  = s.cronicaId;
        versao     = s.versao;
        xpSaldo    = s.xpSaldo;
        aprovadaEm = s.aprovadaEm;

        if (s.existe) {
            Cronica memory c = cronicas[s.cronicaId];
            nomeCronica = c.nome;
            mestre      = c.mestre;
        }
    }

    /**
     * @dev Retorna todos os hashes aprovados de uma crônica.
     */
    function hashsDaCronica(uint256 cronicaId)
        external
        view
        returns (bytes32[] memory)
    {
        return _cronicaHashes[cronicaId];
    }

    /**
     * @dev Retorna dados básicos de uma crônica.
     */
    function dadosDaCronica(uint256 cronicaId)
        external
        view
        returns (
            string  memory nome,
            string  memory narrador,
            address mestre,
            uint256 criadaEm,
            bool    ativa,
            uint256 totalFichas
        )
    {
        Cronica memory c = cronicas[cronicaId];
        return (
            c.nome,
            c.narrador,
            c.mestre,
            c.criadaEm,
            c.ativa,
            _cronicaHashes[cronicaId].length
        );
    }

    /**
     * @dev Retorna o total de crônicas criadas.
     */
    function totalCronicas() external view returns (uint256) {
        return _nextId - 1;
    }
}
