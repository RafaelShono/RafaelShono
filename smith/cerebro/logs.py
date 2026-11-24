"""Logs do cérebro: smith_cerebro.log (operacional) e smith_pensamentos.log (Fase 4+)."""

from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path


def configurar(pasta: Path, nivel: str = "INFO") -> None:
    pasta.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(name)s: %(message)s")

    raiz = logging.getLogger("smith")
    raiz.setLevel(nivel)
    raiz.handlers.clear()
    arq = RotatingFileHandler(pasta / "smith_cerebro.log", maxBytes=5_000_000, backupCount=3, encoding="utf-8")
    arq.setFormatter(fmt)
    raiz.addHandler(arq)

    pens = logging.getLogger("smith.pensamentos")
    pens.propagate = False
    pens.handlers.clear()
    h = RotatingFileHandler(pasta / "smith_pensamentos.log", maxBytes=5_000_000, backupCount=3, encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
    pens.addHandler(h)
