"""Worker de ingestão do AGROTORK BRAIN — Fase 2, Lote B.

arquivo → sha256 → versão → páginas → chunks → metadados. Sem vetor.

O worker não tem regra de negócio sobre o que pode ser lido: ele só
transforma bytes em linhas e chama a API SQL (`brain.register_version`,
`brain.ingestion_*`). Checksum, idempotência, página obrigatória, contagens
e estado são conferidos pelo banco.
"""

PIPELINE_VERSION = "lote-b.1"
