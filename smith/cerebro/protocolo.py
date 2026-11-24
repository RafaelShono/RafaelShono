"""Envelope do protocolo corpo <-> cérebro (v1). Ver docs/protocolo.md."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

VERSAO_PROTOCOLO = 1
TAMANHO_MAX_LINHA = 1024 * 1024  # 1 MiB

# Tipos conhecidos em cada sentido. Tipo desconhecido não é erro fatal
# (versões futuras do corpo podem mandar mais coisas), mas é registrado.
TIPOS_DO_CORPO = {"ola", "percepcao", "evento", "estado", "adeus", "pong", "resultado"}
TIPOS_DO_CEREBRO = {"ola_ok", "ping", "config", "comando"}


class ErroProtocolo(ValueError):
    """Mensagem fora do formato do envelope."""


@dataclass
class Mensagem:
    tipo: str
    dados: dict[str, Any] = field(default_factory=dict)
    seq: int = 0
    t: int = 0
    v: int = VERSAO_PROTOCOLO

    def codificar(self) -> bytes:
        corpo = {"v": self.v, "tipo": self.tipo, "seq": self.seq, "t": self.t, "dados": self.dados}
        # ensure_ascii=True: o JSON do lado Lua lida melhor com ASCII puro.
        return (json.dumps(corpo, ensure_ascii=True, separators=(",", ":")) + "\n").encode("ascii")


def _normalizar(valor: Any) -> Any:
    """O encodeJson do Lua não distingue tabela vazia de lista vazia: `{}` pode
    chegar onde se esperava `[]`. Aqui só garantimos tipos JSON válidos; quem
    consome os dados usa `como_lista` para campos que são listas."""
    return valor


def como_lista(valor: Any) -> list:
    """Converte `{}` (tabela Lua vazia) ou `None` em `[]`."""
    if valor is None or valor == {}:
        return []
    if isinstance(valor, list):
        return valor
    raise ErroProtocolo(f"esperava lista, veio {type(valor).__name__}")


def decodificar(linha: bytes | str) -> Mensagem:
    if isinstance(linha, bytes):
        if len(linha) > TAMANHO_MAX_LINHA:
            raise ErroProtocolo("linha grande demais")
        try:
            linha = linha.decode("utf-8")
        except UnicodeDecodeError:
            # O Lua do jogo pode mandar texto em CP1252 (nomes de zona, por exemplo).
            linha = linha.decode("cp1252", errors="replace")
    linha = linha.strip()
    if not linha:
        raise ErroProtocolo("linha vazia")
    try:
        bruto = json.loads(linha)
    except json.JSONDecodeError as e:
        raise ErroProtocolo(f"JSON inválido: {e}") from None
    if not isinstance(bruto, dict):
        raise ErroProtocolo("mensagem não é objeto")

    v = bruto.get("v")
    if v != VERSAO_PROTOCOLO:
        raise ErroProtocolo(f"versão {v!r} não suportada (esperado {VERSAO_PROTOCOLO})")
    tipo = bruto.get("tipo")
    if not isinstance(tipo, str) or not tipo:
        raise ErroProtocolo("campo 'tipo' ausente")
    seq = bruto.get("seq", 0)
    t = bruto.get("t", 0)
    if not isinstance(seq, (int, float)) or not isinstance(t, (int, float)):
        raise ErroProtocolo("'seq' e 't' devem ser números")
    dados = bruto.get("dados", {})
    if dados is None or dados == []:
        dados = {}
    if not isinstance(dados, dict):
        raise ErroProtocolo("'dados' deve ser objeto")
    return Mensagem(tipo=tipo, dados=_normalizar(dados), seq=int(seq), t=int(t), v=v)
