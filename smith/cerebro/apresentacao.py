"""Formata percepções para leitura humana no terminal.

Só usa as chaves neutras do protocolo; os valores (nomes de zona, modelos)
são impressos como vêm, sem interpretação específica do jogo.
"""

from __future__ import annotations

from typing import Any

from .protocolo import como_lista


def _pos(p: Any) -> str:
    try:
        return f"({p[0]:.0f}, {p[1]:.0f}, {p[2]:.0f})"
    except (TypeError, IndexError, KeyError):
        return "(?)"


def resumo_percepcao(d: dict) -> str:
    mundo = d.get("mundo") or {}
    jog = d.get("jogador") or {}
    ent = d.get("entorno") or {}
    peds = como_lista(ent.get("pedestres"))
    veics = como_lista(ent.get("veiculos"))
    zona = mundo.get("zona") or {}
    dens = mundo.get("densidade") or {}

    linhas = []
    linhas.append(
        f"[{mundo.get('hora', '?')}] {zona.get('nome') or zona.get('codigo') or '?'}"
        f" | clima {mundo.get('clima', '?')} | interior {mundo.get('interior', '?')}"
        f" | procurado {mundo.get('procurado_jogador', '?')}"
        f" | densidade {dens.get('pedestres', '?')} ped / {dens.get('veiculos', '?')} veic"
        f" em {dens.get('raio', '?')} m")
    v = jog.get("veiculo")
    veic_txt = f"veículo {v.get('modelo')} a {v.get('velocidade', 0):.0f}" if isinstance(v, dict) else "a pé"
    linhas.append(
        f"  jogador {_pos(jog.get('pos'))} rumo {jog.get('rumo', 0):.0f}° vida {jog.get('vida')}"
        f" colete {jog.get('colete')} ${jog.get('dinheiro')} arma {jog.get('arma')} {veic_txt}"
        + (f" MIRANDO em {jog['mirando_em']}" if jog.get("mirando_em") else ""))
    smith = d.get("smith")
    linhas.append(f"  smith: {smith if smith else '(sem corpo — Fase 2)'}")

    for p in peds[:8]:
        vis = p.get("visibilidade") or {}
        olho = ""
        if vis.get("na_tela"):
            olho = " 👁" if vis.get("linha_de_visao") else " (tela, sem LOS)"
            if vis.get("olhado_ms"):
                olho += f" olhado {vis['olhado_ms'] / 1000:.1f}s"
        grupo = p.get("gangue") or p.get("tipo")
        linhas.append(
            f"    ped {p.get('id')} m{p.get('modelo')} {grupo}"
            f"{' POLÍCIA' if p.get('policial') else ''}{' armado' if p.get('armado') else ''}"
            f" {p.get('atividade')} a {p.get('dist', 0):.0f} m{olho}")
    if len(peds) > 8:
        linhas.append(f"    ... +{len(peds) - 8} pedestres")
    for c in veics[:4]:
        linhas.append(
            f"    veic {c.get('id')} m{c.get('modelo')}{' POLÍCIA' if c.get('policia') else ''}"
            f" a {c.get('dist', 0):.0f} m, {c.get('velocidade', 0):.0f} u/s")
    if len(veics) > 4:
        linhas.append(f"    ... +{len(veics) - 4} veículos")
    return "\n".join(linhas)


def resumo_evento(d: dict) -> str:
    nome = d.get("nome", "?")
    resto = ", ".join(f"{k}={v}" for k, v in d.items() if k != "nome")
    return f"  ** EVENTO {nome}: {resto}"
