# Capturas de tela

Verificação de responsividade feita em 29/08/2026 (Chromium, build de produção).
Nenhuma das telas apresenta rolagem horizontal.

| Arquivo | Largura | Observação |
| --- | --- | --- |
| `painel-celular.png` | 360 px | Barra inferior com FAB "Novo orçamento" |
| `painel-tablet.png` | 768 px | Grade de indicadores em 2 colunas |
| `painel-desktop.png` | 1440 px | Sidebar fixa |
| `login-desktop.png` | 1440 px | Tela de entrada com painel de marca |
| `perfil-celular.png` | 360 px | Perfil do usuário |
| `perfil-desktop.png` | 1440 px | Perfil do usuário |
| `painel-vendedor-rls.png` | 1280 px | Painel logado como **vendedor**, com dados reais do banco: 1 orçamento (dos 3 existentes), sem o menu Configurações e com o aviso de permissão. Gerado por `supabase/db-tests/auth-double/e2e-autenticacao.mjs`. |
| `clientes-lista-celular.png` | 390 px | Listagem de clientes no celular: busca, filtros lado a lado e cartões |
| `clientes-lista-desktop.png` | 1440 px | Listagem em tabela |
| `clientes-ficha-celular.png` | 390 px | Ficha do cliente com histórico comercial |
| `clientes-form-desktop.png` | 1440 px | Formulário de cadastro |
| `produtos-lista-desktop.png` | 1440 px | Catálogo com custo e margem (visão do administrador) |
| `produtos-lista-celular-vendedor.png` | 390 px | Mesmo catálogo pelo **vendedor**: sem custo, sem margem |
| `produtos-ficha-desktop.png` | 1440 px | Ficha do produto |
| `produtos-form-celular.png` | 360 px | Formulário de cadastro no celular |
| `produtos-procedencia.png` | 1440 px | Ficha de um produto vindo de catálogo de fabricante: código de fábrica, catálogo de origem, versão e dados técnicos |
| `configuracoes-desktop.png` | 1440 px | Configurações → Cadastros: marcas, categorias e unidades |
| `cadastros-marcas-desktop.png` | 1440 px | Listagem de marcas em tabela, com situação |
| `cadastros-marcas-celular.png` | 360 px | A mesma listagem no celular, em lista tocável |
| `cadastros-form-celular.png` | 360 px | Formulário de nova unidade no celular |
| `kits-lista-desktop.png` | 1440 px | Listagem de kits com contagem de obrigatórios, opcionais e preço-base |
| `kits-ficha-desktop.png` | 1440 px | Ficha do kit: composição separada em obrigatórios e opcionais |
| `kits-ficha-celular.png` | 360 px | A mesma ficha no celular |
| `kits-editor-celular.png` | 360 px | Editor de composição no celular |
| `kits-lista-celular-vendedor.png` | 390 px | Listagem pelo **vendedor**: só kits ativos, sem botões de escrita |
| `orcamentos-lista-desktop.png` | 1440 px | Listagem de orçamentos: número, cliente, vendedor, total e situação |
| `orcamentos-lista-celular.png` | 360 px | A mesma listagem em cartões |
| `orcamentos-editor-desktop.png` | 1440 px | Montagem: itens, composição do kit, totais e desconto |
| `orcamentos-editor-celular.png` | 360 px | Montagem no celular |
| `orcamentos-ficha-desktop.png` | 1440 px | Orçamento salvo, com a composição congelada de cada kit |
| `orcamentos-ficha-celular.png` | 360 px | Ficha pelo **vendedor**, sem custo |
| `orcamentos-compartilhamento.png` | 1440 px | Ficha com o painel de link público: endereço, expiração e revogação |
| `orcamento-publico-desktop.png` | 1440 px | Página pública do orçamento, aberta sem login |
| `orcamento-publico-celular.png` | 390 px | A mesma página no celular |

As capturas de Clientes, Produtos, Cadastros, Kits, Orçamentos e do link público são geradas pelos respectivos
`e2e-*.mjs` em `supabase/db-tests/auth-double/`.

O painel foi capturado com dados de demonstração a partir de uma rota temporária,
removida em seguida. Os componentes são exatamente os de `src/app/(app)/dashboard`.
