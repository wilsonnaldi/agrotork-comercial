/**
 * Limites da síntese. Nenhum número aqui é chutado — cada um tem o motivo
 * escrito, porque limite sem motivo vira folclore e ninguém ousa mexer.
 */

/**
 * Evidências enviadas ao modelo. O retrieval devolve 10; a síntese usa no
 * máximo 5. Cinco trechos de fontes diferentes já dão uma resposta com
 * citação; acima disso o modelo começa a costurar coisas que só se parecem,
 * e o custo cresce sem a resposta melhorar.
 */
export const MAX_EVIDENCIAS_SINTESE = 5;

/**
 * Teto por evidência. O worker fatia em `MAX = 1400` caracteres
 * (`brain/worker/brain_worker/chunking.py`), então 2000 NÃO corta nenhum
 * trecho real — é uma cerca contra anomalia (uma tabela gigante que escapou
 * do fatiador), não um corte de rotina. Quando corta, a resposta avisa.
 */
export const MAX_CHARS_POR_EVIDENCIA = 2000;

/**
 * Teto do bloco de evidências inteiro: 5 × 2000 mais os cabeçalhos de cada
 * uma. Se estourar, sobram menos evidências — nunca um trecho pela metade
 * sem aviso.
 */
export const MAX_CHARS_CONTEXTO = 11_000;

/**
 * Teto da resposta. Uma resposta documental com citações cabe com folga; um
 * texto acima disso é sinal de que o modelo saiu do papel de sintetizar.
 */
export const MAX_CHARS_RESPOSTA = 4000;

/** Teto da pergunta — o mesmo do schema de entrada e o mesmo que o banco corta. */
export const MAX_CHARS_PERGUNTA = 1000;

/** Tempo máximo esperando o provedor. Acima disto a pessoa já desistiu. */
export const TIMEOUT_PROVIDER_MS = 30_000;
