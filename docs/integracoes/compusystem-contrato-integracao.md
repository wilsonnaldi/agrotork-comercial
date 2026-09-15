# Compusystem — contrato de integração (pedido técnico)

**O que este documento é:** a lista do que a AGROTORK precisa saber e receber
da Compusystem para construir a leitura de dados do ERP. É um documento para
**enviar ao fornecedor** e receber preenchido.

**O que este documento não é:** descrição da API da Compusystem. Nada aqui
afirma como o sistema deles funciona. Cada linha é uma pergunta ou um pedido.
Nenhum campo, endpoint ou estrutura foi inventado a partir de suposição — e
nenhum schema de integração será criado no Supabase antes destas respostas.

**Estado em 15/09/2026:** não existe integração. Não há credencial, endpoint,
chamada, tabela-espelho ou código de sincronização no sistema da AGROTORK.

O que já foi informado pela Compusystem e orienta o pedido abaixo: não há
acesso direto ao banco; não há API genérica pronta; o backup do banco pode ser
fornecido; é possível construir uma API **somente leitura** com os dados que
forem solicitados; a integração não grava no ERP; já existem integrações com
Mercado Livre e com e-commerce Tray.

---

## Bloco A — Contrato da API

Antes das entidades, o contrato. Sem estas respostas, qualquer desenho de
sincronização é chute.

| Item | Por que precisamos |
| --- | --- |
| URL base, por ambiente | Separar homologação de produção desde o primeiro dia |
| Ambientes disponíveis (sandbox/homologação) | Testar sem tocar em dado real |
| Forma de autenticação (token, chave, OAuth, usuário/senha) | Guardar o segredo do jeito certo |
| Validade do token e como renovar | Uma sincronização que roda sozinha não pode parar por expiração silenciosa |
| Exige liberação de IP (allowlist)? | O servidor que consulta é na nuvem e tem IP próprio |
| Limite de requisições (por minuto/hora/dia) | Dimensionar a frequência e o tamanho da página |
| Paginação: parâmetros, tamanho máximo, cursor ou offset | Ler 30 mil registros sem derrubar o serviço |
| Filtro por data/hora de alteração (`alterado_desde`) | **O item mais importante.** Sem ele, toda sincronização relê tudo |
| Ordenação garantida | Paginar sem pular nem repetir registro |
| Campo de última alteração em todo registro | Saber o que mudou desde a última leitura |
| Como aparecem exclusões e cancelamentos (flag, data, endpoint próprio) | Registro apagado no ERP não pode ficar vivo no espelho |
| Identificador interno estável de cada registro | Chave que não muda nem é reaproveitada — é ela que liga os dois lados |
| Fuso horário das datas e formato (ISO 8601?) | Evitar erro de um dia inteiro em relatório |
| Existe webhook/callback de alteração? | Se existir, reduz atraso; não é requisito |
| Comportamento em erro: códigos HTTP e corpo do erro | Distinguir "falhou" de "não existe", e tratar cada caso como merece |
| Repetir a mesma requisição é seguro? | Se a rede cair no meio, a nossa rotina repete — e não pode duplicar nem ser bloqueada por isso |
| Política de nova tentativa recomendada (intervalo, número de tentativas) | Repetir sem incomodar o serviço de vocês |
| Versionamento da API, changelog e aviso prévio de mudança | Uma alteração de campo não pode chegar como surpresa numa madrugada |
| Documentação em OpenAPI/Swagger, coleção Postman ou PDF | Acelera o trabalho dos dois lados |
| Prazo de atendimento e canal de suporte técnico (SLA) | Quando a sincronização parar, saber a quem perguntar e em quanto tempo |

---

## O que vale para toda entidade (blocos B a F)

Antes dos campos de cada entidade, oito perguntas que se repetem em todas — e
que a resposta pode dar uma vez só, se valer para todas:

| Pergunta | Por que |
| --- | --- |
| Qual é a **chave primária** do registro no ERP? | É o que identifica a linha do lado de vocês |
| Ela é **estável e nunca reaproveitada**? | Se um código puder ser reciclado, o vínculo entre os sistemas quebra silenciosamente |
| Existe um **código "humano"** além dela (código do produto, número do pedido)? | É o que aparece na tela e na conversa; guardamos os dois |
| Quais são **todos os campos** disponíveis no endpoint? | Preferimos ver a lista inteira e escolher, a descobrir depois que faltou um |
| Quais são os **valores possíveis de situação/status**, e o que cada um significa? | "Situação 3" não diz nada sem a legenda |
| Quais **datas** o registro carrega (criação, alteração, e as próprias do documento)? | Sem data de alteração não há sincronização incremental |
| Como esse registro se **liga aos outros** (cliente ↔ venda ↔ item ↔ produto ↔ filial)? | É o que permite montar a visão completa sem adivinhar |
| Como aparecem **exclusão, inativação e cancelamento**, e como pedimos **só o que mudou** desde certa data? | Os dois lados do mesmo problema: não perder mudança e não trazer o que não mudou |

Os blocos abaixo listam os campos que interessam a cada entidade. Onde o ERP
tiver mais do que o listado, queremos saber; onde tiver menos, também.

---

## Bloco B — Clientes

Endpoint, e para cada cliente:

identificador interno; CPF/CNPJ; tipo (pessoa física/jurídica); nome ou razão
social; nome fantasia; inscrição estadual; e-mail; telefone e WhatsApp;
endereço completo com município, UF e CEP; **vendedor responsável**;
grupo/segmento, se houver; situação (ativo/inativo/bloqueado); limite de
crédito e bloqueio, se existirem; data de cadastro; data de última alteração;
como aparece um cliente inativado ou excluído.

Interessa também, se o ERP souber responder: data da primeira e da última
compra, e total comprado por período — evita a AGROTORK recalcular o que o
ERP já sabe.

---

## Bloco C — Produtos

Endpoint, e para cada produto:

identificador interno; código; descrição; descrição complementar; marca;
grupo e subgrupo (ou categoria); unidade; NCM; CEST, se houver; GTIN/EAN;
código do fabricante ou referência; fornecedor principal; **custo** (último e
médio, com a data a que se referem); **preço de venda** por tabela ou condição
de pagamento, com vigência; situação (ativo/inativo); se controla número de
série ou lote; peso e dimensões, se existirem; data de cadastro; data de
última alteração.

E a lista dos cadastros de apoio como entidades próprias — marcas, grupos,
subgrupos, unidades, tabelas de preço, condições de pagamento — para o
de-para com os cadastros da AGROTORK.

---

## Bloco D — Estoque

Endpoint(s), e para cada produto:

saldo por filial e por local/depósito; quantidade reservada; disponível; em
trânsito, se o ERP controlar; custo médio da posição; localização física;
data/hora da última alteração da posição.

E as **movimentações**: identificador; produto; filial; data/hora; tipo
(entrada, saída, ajuste, transferência, devolução, inventário); quantidade;
custo; documento de origem (nota, pedido, ajuste); lote ou número de série
quando houver; usuário responsável, se registrado.

Interessa também: data da última venda e da última compra por produto e
filial — é o que responde "o que está parado".

---

## Bloco E — Vendas e pedidos

Endpoint(s), e para cada documento:

identificador interno; número; tipo (orçamento, pedido, nota); **situação**
(aberto, faturado, cancelado, devolvido); data de emissão; data de
faturamento; **filial**; **vendedor**; cliente; **canal ou origem da venda**
(balcão, Mercado Livre, Tray, telefone…) e o número do pedido na origem quando
vier de marketplace; condição de pagamento; frete; desconto do cabeçalho;
total; data de última alteração.

Itens: produto; quantidade; preço unitário; desconto do item; **custo do item
no momento da venda**; impostos, se compuserem o valor; total do item.

E ainda: como aparecem devoluções e cancelamentos; chave e número da NF-e de
saída, quando houver; e — para registro, sem pedido de implementação agora —
se existe ou existiria a possibilidade futura de **criar** pedido via API, e
sob que contrato.

---

## Bloco F — Financeiro e compras

Se a Compusystem é o financeiro oficial da AGROTORK:

**Contas a receber e a pagar:** identificador; cliente ou fornecedor; origem
(venda, compra, avulso); número da parcela e total de parcelas; vencimento;
valor; valor liquidado; data de liquidação; forma de pagamento; situação;
data de última alteração.

**Compras:** identificador; fornecedor; número e chave da NF-e de entrada;
data de emissão e de entrada; filial; itens com produto, quantidade, custo
unitário e total; situação. E os **fornecedores** como entidade: identificador,
CNPJ, razão social, situação.

**Filiais e vendedores** como entidades próprias: identificador, nome, CNPJ
(filial), situação — é o que permite medir resultado por filial e por vendedor.

---

## Bloco G — Backup e exemplar de referência

Além da API, a AGROTORK pede **um exemplar real de backup ou exportação**,
para entender o modelo antes de desenhar a integração. Em ordem de
preferência: dump SQL ou backup nativo do banco; exportação CSV por tabela;
planilha oficial de exportação.

Junto com ele:

- dicionário de dados: nome de cada tabela e de cada coluna, com significado;
- chaves primárias e estrangeiras, e como as tabelas se ligam;
- listas de valores fixos (situações, tipos, status) com o significado de cada código;
- alguns registros reais de exemplo, anonimizados se necessário;
- qual o banco de dados e a versão.

Serve para conferir o que a API devolve contra o que o ERP guarda, e para a
carga inicial de histórico — que por API costuma ser lenta.

---

## Bloco H — Segurança e operação

Do lado da AGROTORK, assumido como regra e informado aqui por transparência:

- a credencial fica **apenas no servidor**, nunca no navegador, no aplicativo ou no repositório de código;
- o acesso é **somente leitura**, e nenhuma rotina da AGROTORK grava no ERP;
- os registros de execução não guardam segredo;
- a credencial é rotacionável e a AGROTORK avisa antes de trocar.

Do lado da Compusystem, pedimos:

- usuário/credencial dedicado à integração, com permissão mínima de leitura;
- possibilidade de revogar sem afetar os usuários do ERP;
- aviso prévio de mudança de contrato, campo ou endereço.

---

## Bloco I — O que a AGROTORK **não** está pedindo agora

Para o escopo ficar claro e o orçamento também:

- nenhuma escrita no ERP (criar cliente, pedido, produto, título) — se um dia houver, será contrato à parte;
- nenhuma sincronização bidirecional;
- nenhuma alteração no ERP para acomodar o sistema da AGROTORK;
- nenhuma integração com Mercado Livre ou Tray feita pela AGROTORK — o que existe hoje entre a Compusystem e essas plataformas continua como está.

Sobre esse último ponto, três perguntas, para decidir se a AGROTORK lê o
e-commerce **pela Compusystem** em vez de falar com as plataformas:

1. O que as integrações Compusystem↔Mercado Livre e Compusystem↔Tray sincronizam hoje (produto, SKU, estoque, preço, pedido, cliente, nota, status, frete, rastreio) e em que sentido?
2. O pedido do marketplace vira venda na Compusystem com o número do pedido de origem e um campo que identifica o canal?
3. O cliente do marketplace vira cliente cadastrado na Compusystem, ou fica anônimo/genérico?

---

## Como responder

O formato ideal é este mesmo documento devolvido com as respostas, ou a
documentação técnica equivalente. Se algum item não existir hoje, "não existe"
é uma resposta útil — ela muda o desenho da integração, e é melhor saber antes.
