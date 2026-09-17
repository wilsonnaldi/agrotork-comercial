/**
 * Limites da síntese. Nenhum número aqui é chutado — cada um tem o motivo
 * escrito, porque limite sem motivo vira folclore e ninguém ousa mexer.
 *
 * Revisados em 17/09/2026, depois de uma medição do corpus em produção que
 * derrubou a premissa em que os números anteriores se apoiavam. Está contada
 * em `MAX_CHARS_POR_EVIDENCIA`.
 */

/**
 * Teto por evidência.
 *
 * O NÚMERO ANTERIOR ERA 2000, E A JUSTIFICATIVA ESTAVA ERRADA. Ela dizia que
 * o worker fatia em `MAX = 1400` caracteres, então 2000 nunca cortaria um
 * trecho real. Isso vale para TEXTO. Tabela não é fatiada: o chunker corta
 * parágrafo, e uma tabela entra inteira, do jeito que o documento a traz.
 *
 * Medido em produção (17/09/2026), com os dois documentos ativos:
 *
 *   780 trechos no total
 *    56 acima de 2000 caracteres — TODOS tabelas
 *   6.614 caracteres no trecho da p.20 do Catálogo Magnojet
 *  16.754 caracteres no maior trecho do corpus
 *
 * Naquele trecho da p.20, a linha do MJ981CAP a 40 psi começa no caractere
 * 1401 — passava por pouco. A do MJ985CAP começa depois do 5.000: com o teto
 * antigo, perguntar pelo MJ985CAP entregava ao modelo uma tabela cortada
 * antes da resposta, e ele responderia, com toda a razão, que a documentação
 * não permite concluir — com a evidência inteira na tela e ninguém
 * entendendo por quê.
 *
 * 20.000 cobre o maior trecho de hoje (16.754) com folga de ~19%. Não é um
 * número eterno: se o corpus crescer com tabelas maiores, a medição tem de
 * ser refeita. O que o teto faz agora é DESCARTAR a evidência que não cabe,
 * nunca mandar metade dela — ver `assessEvidence`.
 */
export const MAX_CHARS_POR_EVIDENCIA = 20_000;

/**
 * Evidências enviadas ao modelo. Caiu de 5 para 3 porque cada uma pode agora
 * ser dez vezes maior: três tabelas inteiras já são um contexto grande, e
 * acima disso o modelo começa a costurar linhas de tabelas diferentes que só
 * se parecem. O retrieval continua devolvendo 10 e a tela mostra todas — o
 * corte é só do que vai ao provedor.
 */
export const MAX_EVIDENCIAS_SINTESE = 3;

/**
 * Teto do bloco de evidências inteiro: 3 × (20.000 + ~200 de cabeçalho), com
 * uma margem. Com os dois tetos acima ele nunca é o limite que morde
 * primeiro — é cinto e suspensório, e está aqui para o dia em que alguém
 * mexer num dos outros dois sem olhar para este.
 */
export const MAX_CHARS_CONTEXTO = 62_000;

/**
 * Teto da resposta. Uma resposta documental com citações cabe com folga; um
 * texto acima disso é sinal de que o modelo saiu do papel de sintetizar.
 */
export const MAX_CHARS_RESPOSTA = 4000;

/** Teto da pergunta — o mesmo do schema de entrada e o mesmo que o banco corta. */
export const MAX_CHARS_PERGUNTA = 1000;

/** Tempo máximo esperando o provedor. Acima disto a pessoa já desistiu. */
export const TIMEOUT_PROVIDER_MS = 30_000;
