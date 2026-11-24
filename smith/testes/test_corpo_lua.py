"""Roda o smith.lua de verdade (LuaJIT + luasocket) contra a ponte Python,
com a API do MoonLoader imitada em testes/lua/moonloader_falso.lua.

Pulado se luajit ou luasocket não estiverem instalados."""

import asyncio
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

from cerebro.ponte import Ponte  # noqa: E402
from cerebro.protocolo import como_lista  # noqa: E402


def _tem_luajit_com_socket() -> bool:
    if not shutil.which("luajit"):
        return False
    r = subprocess.run(["luajit", "-e", "require 'socket'"], capture_output=True)
    return r.returncode == 0


pytestmark = pytest.mark.skipif(not _tem_luajit_com_socket(), reason="precisa de luajit + lua-socket")


def test_smith_lua_contra_ponte(tmp_path):
    pasta = tmp_path / "moonloader"
    shutil.copytree(RAIZ / "corpo" / "moonloader", pasta)

    async def cenario():
        ponte = Ponte(porta=0, ping_s=0.2, intervalo_percepcao_ms=500, versao_cerebro="teste")
        msgs = []
        ponte.ao_receber(lambda m: msgs.append(m))
        await ponte.iniciar()
        proc = await asyncio.create_subprocess_exec(
            "luajit", str(RAIZ / "testes" / "lua" / "moonloader_falso.lua"),
            str(pasta), str(ponte.porta_real), "400",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        out, err = await asyncio.wait_for(proc.communicate(), 60)
        await asyncio.sleep(0.2)
        await ponte.parar()
        return proc.returncode, out.decode(), err.decode(), msgs, ponte

    rc, out, err, msgs, ponte = asyncio.run(cenario())
    log = (pasta / "smith_corpo.log").read_text(encoding="latin-1")
    assert rc == 0, f"saida={out}\nerro={err}\nlog={log}"
    assert "ERRO" not in log, log
    assert ponte.estatisticas["invalidas"] == 0

    tipos = [m.tipo for m in msgs]
    ola = [m for m in msgs if m.tipo == "ola"]
    assert len(ola) == 2, tipos  # conectou, F10 desligou, F10 religou
    assert como_lista(ola[0].dados["api_ausente"]) == []
    assert tipos.count("adeus") >= 2  # F10 e fim do script
    assert "pong" in tipos

    eventos = {m.dados["nome"]: m.dados for m in msgs if m.tipo == "evento"}
    assert eventos["tiro"]["autor"] == 512
    assert eventos["morte"]["vitima"] == 256 and eventos["morte"]["gangue"] == "grove"
    assert eventos["procurado_mudou"] == {"nome": "procurado_mudou", "de": 0, "para": 2}
    assert eventos["batida"]["dano"] == 300
    assert eventos["policia_chegou"]["quantos"] == 1
    assert eventos["jogador_mira_npc"]["alvo"] == 512
    assert eventos["jogador_observa_npc"]["alvo"] == 1024

    perc = [m.dados for m in msgs if m.tipo == "percepcao"]
    assert len(perc) >= 5
    p = perc[-1]
    assert p["mundo"]["zona"] == {"codigo": "GAN1", "nome": "Ganton"}
    assert p["mundo"]["hora"] == "21:37"
    assert p["jogador"]["dinheiro"] == 350
    peds = como_lista(p["entorno"]["pedestres"])
    ids = [x["id"] for x in peds]
    assert 1 not in ids  # o próprio jogador não aparece no entorno
    assert ids == sorted(ids, key=lambda i: next(x["dist"] for x in peds if x["id"] == i))
    civil = next(x for x in peds if x["id"] == 1024)
    assert civil["visibilidade"]["na_tela"] and civil["visibilidade"]["linha_de_visao"]
    veic = como_lista(p["entorno"]["veiculos"])
    assert veic[0]["policia"] is True and veic[0]["motorista"] == 768
