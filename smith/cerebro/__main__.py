"""Fase 1: o cérebro só escuta e imprime o que o corpo percebe.

Uso:
    python -m cerebro            resumo legível no terminal
    python -m cerebro --json     cada mensagem em JSON cru
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
import time

from . import VERSAO
from .apresentacao import resumo_evento, resumo_percepcao
from .config import carregar
from .logs import configurar
from .ponte import Ponte
from .protocolo import Mensagem

log = logging.getLogger("smith.main")


async def rodar(json_cru: bool) -> None:
    cfg = carregar()
    configurar(cfg.logs.pasta, cfg.logs.nivel)
    ponte = Ponte(cfg.ponte.host, cfg.ponte.porta, cfg.ponte.ping_s,
                  cfg.ponte.intervalo_percepcao_ms, VERSAO)

    arquivo_jsonl = None
    if cfg.logs.gravar_percepcoes:
        arquivo_jsonl = open(cfg.logs.pasta / "percepcoes.jsonl", "a", encoding="utf-8")

    def tratar(msg: Mensagem) -> None:
        if arquivo_jsonl and not msg.tipo.startswith("_"):
            arquivo_jsonl.write(json.dumps({"recebido": time.time(), "tipo": msg.tipo, "seq": msg.seq,
                                            "t": msg.t, "dados": msg.dados}, ensure_ascii=False) + "\n")
            arquivo_jsonl.flush()
        if json_cru:
            if not msg.tipo.startswith("_"):
                print(json.dumps({"tipo": msg.tipo, "seq": msg.seq, "t": msg.t, "dados": msg.dados},
                                 ensure_ascii=False, indent=2), flush=True)
            return
        if msg.tipo == "ola":
            d = msg.dados
            print(f"\n=== corpo conectado: {d.get('jogo')} (corpo {d.get('versao_corpo')}) ===", flush=True)
            ausentes = d.get("api_ausente") or []
            if ausentes:
                print(f"  ATENÇÃO: funções do MoonLoader ausentes: {', '.join(ausentes)}", flush=True)
            else:
                print("  todas as funções do MoonLoader esperadas existem", flush=True)
        elif msg.tipo == "percepcao":
            print(resumo_percepcao(msg.dados), flush=True)
        elif msg.tipo == "evento":
            print(resumo_evento(msg.dados), flush=True)
        elif msg.tipo == "estado":
            print(f"  [estado] {msg.dados}", flush=True)
        elif msg.tipo == "adeus":
            print(f"=== corpo se despediu: {msg.dados.get('motivo')} ===", flush=True)
        elif msg.tipo == "_desconectado":
            print("=== corpo desconectado; aguardando reconexão ===", flush=True)

    ponte.ao_receber(tratar)
    await ponte.iniciar()
    print(f"Cérebro de Smith {VERSAO} — ouvindo em {cfg.ponte.host}:{cfg.ponte.porta}", flush=True)
    print(f"Logs em {cfg.logs.pasta}. Ctrl+C para sair. Aguardando o jogo...", flush=True)
    try:
        await asyncio.Event().wait()
    finally:
        await ponte.parar()
        if arquivo_jsonl:
            arquivo_jsonl.close()
        log.info("estatísticas: %s", ponte.estatisticas)


def main() -> None:
    ap = argparse.ArgumentParser(prog="cerebro", description="Cérebro de Smith (Fase 1: ouvir e imprimir)")
    ap.add_argument("--json", action="store_true", help="imprime cada mensagem em JSON cru")
    args = ap.parse_args()
    if sys.platform == "win32":
        # Terminal do Windows: garantir acentos.
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass
    try:
        asyncio.run(rodar(args.json))
    except KeyboardInterrupt:
        print("\nencerrado.")


if __name__ == "__main__":
    main()
