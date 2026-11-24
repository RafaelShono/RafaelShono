"""Corpo falso: imita o script do MoonLoader para testar o cérebro sem o jogo.

    python ferramentas/corpo_falso.py              # conecta em 127.0.0.1:8765
    python ferramentas/corpo_falso.py --vezes 3    # manda 3 percepções e sai
"""

from __future__ import annotations

import argparse
import asyncio
import json
import random

SEQ = 0


def envelope(tipo: str, dados: dict, t: int) -> bytes:
    global SEQ
    SEQ += 1
    return (json.dumps({"v": 1, "tipo": tipo, "seq": SEQ, "t": t, "dados": dados}) + "\n").encode()


def percepcao_falsa(t: int, rnd: random.Random) -> dict:
    jx, jy, jz = 2495.0 + rnd.uniform(-3, 3), -1687.0 + rnd.uniform(-3, 3), 13.5
    peds = []
    for i in range(rnd.randint(3, 8)):
        px, py = jx + rnd.uniform(-40, 40), jy + rnd.uniform(-40, 40)
        gangue = rnd.choice([None, "grove", "ballas"])
        peds.append({
            "id": 1000 + i * 256, "modelo": rnd.choice([7, 105, 102, 280]),
            "tipo": "gangue" if gangue else "civil", "gangue": gangue, "policial": False,
            "arma": 22 if gangue else 0, "armado": bool(gangue),
            "atividade": rnd.choice(["andando", "parado", "correndo"]),
            "pos": [round(px, 1), round(py, 1), 13.4],
            "dist": round(((px - jx) ** 2 + (py - jy) ** 2) ** 0.5, 1), "vida": 100,
            "visibilidade": {"na_tela": rnd.random() < 0.5, "linha_de_visao": rnd.random() < 0.5,
                             "angulo": round(rnd.uniform(0, 90), 1), "olhado_ms": 0},
        })
    peds.sort(key=lambda p: p["dist"])
    return {
        "mundo": {"hora": f"{(t // 60000) % 24:02d}:{(t // 1000) % 60:02d}", "clima": 0,
                  "zona": {"codigo": "GAN1", "nome": "Ganton"}, "territorio_dono": None,
                  "interior": 0, "procurado_jogador": 0,
                  "densidade": {"raio": 60, "pedestres": len(peds), "veiculos": 1}},
        "smith": None,
        "jogador": {"pos": [round(jx, 1), round(jy, 1), jz], "rumo": 180.0, "velocidade": 0.0,
                    "vida": 100, "colete": 0, "dinheiro": 350, "arma": 0, "procurado": 0,
                    "veiculo": None, "olhar": [0.0, -1.0, -0.1], "mirando_em": None},
        "entorno": {"pedestres": peds,
                    "veiculos": [{"id": 9000, "modelo": 596, "pos": [jx + 20, jy, 13.3], "dist": 20.0,
                                  "velocidade": 10.0, "motorista": 9100, "policia": True, "vida": 1000}]},
    }


async def rodar(host: str, porta: int, vezes: int | None, intervalo: float, semente: int) -> int:
    rnd = random.Random(semente)
    r, w = await asyncio.open_connection(host, porta)
    t = 8 * 3600 * 1000
    w.write(envelope("ola", {"jogo": "corpo_falso", "versao_corpo": "falso", "api_ausente": [],
                             "capacidades": ["percepcao", "eventos"]}, t))
    await w.drain()
    respostas = 0

    async def ler() -> None:
        nonlocal intervalo, respostas
        while linha := await r.readline():
            m = json.loads(linha)
            respostas += 1
            if m["tipo"] == "ping":
                w.write(envelope("pong", {"id": m["dados"]["id"]}, t))
                await w.drain()
            elif m["tipo"] in ("ola_ok", "config"):
                ms = m["dados"].get("intervalo_percepcao_ms")
                if ms:
                    intervalo = ms / 1000

    leitor = asyncio.create_task(ler())
    n = 0
    try:
        while vezes is None or n < vezes:
            await asyncio.sleep(min(intervalo, 0.05) if vezes else intervalo)
            t += int(intervalo * 1000)
            w.write(envelope("percepcao", percepcao_falsa(t, rnd), t))
            if rnd.random() < 0.3:
                w.write(envelope("evento", {"nome": "tiro", "autor": 1000, "pos": [2490.0, -1680.0, 13.4]}, t))
            await w.drain()
            n += 1
        w.write(envelope("adeus", {"motivo": "fim do teste"}, t))
        await w.drain()
        await asyncio.sleep(0.05)
    finally:
        leitor.cancel()
        w.close()
    return respostas


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--porta", type=int, default=8765)
    ap.add_argument("--vezes", type=int, default=None)
    ap.add_argument("--intervalo", type=float, default=2.0)
    ap.add_argument("--semente", type=int, default=1)
    a = ap.parse_args()
    asyncio.run(rodar(a.host, a.porta, a.vezes, a.intervalo, a.semente))


if __name__ == "__main__":
    main()
