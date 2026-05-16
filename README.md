# RPGChain

Sistema de integridade narrativa para RPGs de mesa.  
Construído para **Vampiro: A Máscara — Idade das Trevas**.

---

## O problema que resolve

Em campanhas longas, fichas de personagem são editadas invisivamente. XP some ou aparece sem registro. O mestre perde tempo conferindo regras. Não existe histórico verificável de evolução do personagem.

RPGChain resolve isso sem criar burocracia, sem exigir servidor, sem tirar a autoridade do mestre.

---

## Filosofia

**O jogador possui a ficha.**  
Fica no dispositivo dele. Ele exporta quando quiser. Nenhum servidor guarda seus dados.

**O mestre possui a autoridade narrativa.**  
Nenhuma evolução é válida sem aprovação dele. O Gemini confere as regras — o mestre só decide.

**A blockchain prova o estado aprovado.**  
Não guarda a ficha. Não guarda lore. Guarda só o hash, a versão e o timestamp. Qualquer um pode verificar.

---

## Como funciona

### 1. Jogador cria a ficha
Abre `ficha_vtm.html` no navegador. Preenche atributos, perícias, disciplinas, qualidades, defeitos. Tudo salvo localmente via PouchDB. Nenhuma conta necessária.

### 2. Jogador exporta o JSON
Clica em **Exportar JSON**. Gera `ficha_nome_v1.json` com o hash canônico da ficha incluído. Manda pro mestre pelo canal que quiser — WhatsApp, Discord, email.

### 3. Mestre valida com Gemini
Abre `rpg-chain-mestre.html`, faz upload do JSON. O Gemini do mestre analisa automaticamente:

- **Prompt 1 — Ficha inicial:** verifica atributos 7/5/3, perícias 13/9/5, disciplinas de clã, geração, virtudes, pontos bônus
- **Prompt 2 — Pagamento de XP:** calcula o custo exato da melhoria, verifica se é disciplina fora de clã, checa o saldo, retorna aprovado ou reprovado

Cada narrador usa sua própria chave da API Gemini. Nenhuma chave sai do dispositivo.

### 4. Mestre aprova o hash
Se o Gemini validou e o mestre concordou, clica em **Aprovar Hash**. O hash é salvo no PouchDB local do mestre vinculado ao jogador.

### 5. Mestre autoriza onchain
Abre `rpgchain-deploy.html`, conecta o MetaMask na rede Sepolia e chama `aprovarFicha()` no contrato. Registra na blockchain:

```
hash     → SHA-256 canônico da ficha
versão   → número da versão
xpSaldo  → pode ser negativo (dívida narrativa)
cronicaId → ID do NFT da crônica
timestamp → bloco da aprovação
```

### 6. Jogador joga
Usa a ficha normalmente. No combate, clica para calcular o hash atual e cola o hash aprovado pelo mestre. O sistema compara:

- **✓ ÍNTEGRA** — hash bate, ficha está exatamente como o mestre aprovou
- **✕ ADULTERADA** — hash diverge, ficha foi modificada desde a última aprovação

A verificação é leitura pública na blockchain. Não precisa de carteira, não tem custo.

---

## Hash canônico

O hash representa o **estado da ficha**, não o arquivo.

Campos incluídos no cálculo:
```
info, attrs, skills, skillNames, virtues,
willpower, humanidade, bloodMax,
disciplines, merits, flaws, meta, versao
```

Campos excluídos:
```
exportadoEm, hashCanonico, timestamps
```

Exportar a ficha dez vezes gera o mesmo hash enquanto nada mudar. Mudar um ponto de atributo gera um hash diferente.

---

## Dívida Narrativa

Se o jogador evolui a ficha além do XP disponível, o sistema não bloqueia.  
O Gemini registra o saldo negativo. O mestre decide:

- aprovar mesmo assim
- esperar a próxima sessão
- negar

O estado de dívida fica salvo no PouchDB do mestre e pode ser registrado onchain com `xpSaldo` negativo. O jogo não para.

---

## O NFT da Crônica

O mestre minta um NFT que representa sua **autoridade narrativa**, não um personagem ou item.

```json
{
  "nome": "Praga Sombria",
  "narrador": "Arkan",
  "mestre": "0x..."
}
```

Cada ficha aprovada fica vinculada a esse NFT. Se o mestre transferir o NFT, o novo dono passa a ter autoridade sobre a crônica. Fichas já aprovadas continuam verificáveis mesmo após a crônica ser encerrada.

---

## O que fica onde

| Dado | Onde fica |
|---|---|
| Ficha completa | PouchDB do jogador |
| Anotações privadas | localStorage do jogador (não exportado) |
| Estado de combate | memória — não persiste entre sessões |
| Config e jogadores da crônica | PouchDB do mestre |
| Histórico de XP | PouchDB do mestre |
| Hash aprovado | PouchDB do mestre + Blockchain |
| Ficha completa em JSON | trânsito — sem servidor |

Nenhum dado sensível vai para a blockchain. A ficha do personagem nunca é pública.

---

## Arquivos

```
ficha_vtm.html          → ficha do jogador (offline, exporta JSON)
rpg-chain-mestre.html   → painel do narrador (Gemini + aprovação)
rpgchain-deploy.html    → gestão onchain (MetaMask + Sepolia)
RPGChain.sol            → contrato inteligente
RPGChain.abi.json       → ABI para integração
```

---

## Deploy do contrato

1. Acesse [remix.ethereum.org](https://remix.ethereum.org)
2. Crie `RPGChain.sol` e cole o código do contrato
3. Compile com Solidity `^0.8.20`
4. Na aba Deploy, selecione **Injected Provider (MetaMask)** e rede **Sepolia**
5. Clique em Deploy
6. Copie o endereço do contrato e cole no `rpgchain-deploy.html`

O contrato não tem dependências externas. Sem OpenZeppelin, sem bibliotecas.

---

## Stack

| Camada | Tecnologia |
|---|---|
| Armazenamento local | PouchDB + localStorage |
| Validação de regras | Gemini API (chave própria de cada usuário) |
| Hash | SHA-256 via Web Crypto API |
| Blockchain | Ethereum Sepolia (testnet) |
| Carteira | MetaMask |
| Interação onchain | ethers.js v6 |
| RPC leitura pública | Ankr Sepolia RPC |
| Frontend | HTML vanilla — sem framework, sem bundler |

---

## O que o sistema não faz

- Não hospeda nada
- Não tem backend
- Não tem conta de usuário
- Não vende NFT de personagem
- Não bloqueia o roleplay
- Não substitui o mestre
