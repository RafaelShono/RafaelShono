import asyncio
import sys
from pathlib import Path

import pytest

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))
sys.path.insert(0, str(RAIZ / "ferramentas"))

from cerebro.apresentacao import resumo_evento, resumo_percepcao  # noqa: E402
from cerebro.ponte import Ponte  # noqa: E402
from cerebro.protocolo import ErroProtocolo, Mensagem, como_lista, decodificar  # noqa: E402
import corpo_falso  # noqa: E402


def test_envelope_ida_e_volta():
    m = Mensagem(tipo="ping", dados={"id": 3}, seq=7, t=100)
    d = decodificar(m.codificar())
    assert (d.tipo, d.dados, d.seq, d.t) == ("ping", {"id": 3}, 7, 100)


@pytest.mark.parametrize("linha", [
    b"", b"nao e json", b"[1,2]", b'{"v":2,"tipo":"x"}', b'{"v":1}',
    b'{"v":1,"tipo":"x","dados":5}', b'{"v":1,"tipo":"x","seq":"a"}',
])
def test_envelope_invalido(linha):
    with pytest.raises(ErroProtocolo):
        decodificar(linha)


def test_tabela_lua_vazia_vira_lista():
    assert como_lista({}) == []
    assert como_lista(None) == []
    assert decodificar(b'{"v":1,"tipo":"x","dados":[]}').dados == {}


def test_texto_cp1252_nao_derruba():
    d = decodificar('{"v":1,"tipo":"x","dados":{"zona":"Pra\xe7a"}}'.encode("cp1252"))
    assert d.dados["zona"] == "Praça"


def test_resumo_aguenta_percepcao_minima_e_completa():
    import random
    assert "?" in resumo_percepcao({})
    txt = resumo_percepcao(corpo_falso.percepcao_falsa(1000, random.Random(1)))
    assert "Ganton" in txt and "jogador" in txt
    assert "tiro" in resumo_evento({"nome": "tiro", "autor": 1})


def test_ponte_com_corpo_falso():
    async def cenario():
        ponte = Ponte(porta=0, ping_s=0.02, intervalo_percepcao_ms=700, versao_cerebro="teste")
        recebidas = []
        ponte.ao_receber(lambda m: recebidas.append(m))
        await ponte.iniciar()
        respostas = await corpo_falso.rodar("127.0.0.1", ponte.porta_real, vezes=5, intervalo=0.05, semente=2)
        await asyncio.sleep(0.1)
        await ponte.parar()
        return ponte, recebidas, respostas

    ponte, recebidas, respostas = asyncio.run(cenario())
    tipos = [m.tipo for m in recebidas]
    assert tipos[0] == "ola"
    assert tipos.count("percepcao") == 5
    assert "adeus" in tipos and tipos[-1] == "_desconectado"
    assert respostas >= 1  # recebeu ola_ok
    assert ponte.estatisticas["invalidas"] == 0


def test_segunda_conexao_recusada():
    async def cenario():
        ponte = Ponte(porta=0, ping_s=60)
        await ponte.iniciar()
        r1, w1 = await asyncio.open_connection("127.0.0.1", ponte.porta_real)
        await asyncio.wait_for(ponte.conectado.wait(), 1)
        r2, w2 = await asyncio.open_connection("127.0.0.1", ponte.porta_real)
        fechou = await asyncio.wait_for(r2.read(), 1)
        w1.close(); w2.close()
        await ponte.parar()
        return fechou

    assert asyncio.run(cenario()) == b""


def test_linha_invalida_nao_derruba_conexao():
    async def cenario():
        ponte = Ponte(porta=0, ping_s=60)
        recebidas = []
        ponte.ao_receber(lambda m: recebidas.append(m.tipo))
        await ponte.iniciar()
        r, w = await asyncio.open_connection("127.0.0.1", ponte.porta_real)
        w.write(b"lixo\n" + Mensagem(tipo="estado", dados={"pausado": True}).codificar())
        await w.drain()
        await asyncio.sleep(0.1)
        w.close()
        await asyncio.sleep(0.05)
        await ponte.parar()
        return ponte, recebidas

    ponte, recebidas = asyncio.run(cenario())
    assert "estado" in recebidas
    assert ponte.estatisticas["invalidas"] == 1
