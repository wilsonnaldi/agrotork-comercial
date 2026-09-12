"""Porteiro do processamento externo.

Antes de QUALQUER byte de um documento sair do ambiente aprovado (OCR em
nuvem, embedding — Lote C —, sumarização), o worker pergunta ao banco:
`brain.external_processing_for(document_id)`. A resposta é a única regra:

  allowed                → pode ir para qualquer provedor configurado
  approved_provider_only → só para provedor da lista aprovada
  forbidden              → NÃO sai (commercial sem opt-in, admin sempre)
  None                   → documento invisível para este chamador: NÃO sai

Não existe bypass: nenhum provedor é chamado sem passar por `allow()`.
No Lote B nenhum provedor externo está configurado — o OCR é local
(tesseract) e não passa por aqui. O porteiro existe para o Lote C herdar a
regra pronta e testada, não para ser contornado depois.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .db import BrainDb


class ExternalProcessingDenied(PermissionError):
    pass


@dataclass
class ExternalGate:
    db: BrainDb
    approved_providers: frozenset[str] = field(default_factory=frozenset)   # vazio no Lote B

    def decision(self, document_id) -> str:
        return self.db.external_policy(document_id).value or "forbidden"

    def allow(self, document_id, provider: str) -> bool:
        """True só quando a política permite ESTE provedor para ESTE documento."""
        policy = self.decision(document_id)
        if policy == "forbidden":
            return False
        if policy == "allowed":
            return True
        return provider in self.approved_providers   # approved_provider_only

    def require(self, document_id, provider: str) -> None:
        if not self.allow(document_id, provider):
            raise ExternalProcessingDenied(
                f"processamento externo negado para o documento {document_id} (provedor {provider}, "
                f"politica {self.decision(document_id)})"
            )
