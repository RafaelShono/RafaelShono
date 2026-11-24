"""Leitura do config.toml."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent


@dataclass
class ConfigPonte:
    host: str = "127.0.0.1"
    porta: int = 8765
    intervalo_percepcao_ms: int = 2000
    ping_s: float = 5.0


@dataclass
class ConfigLogs:
    pasta: Path = RAIZ / "logs"
    nivel: str = "INFO"
    gravar_percepcoes: bool = True


@dataclass
class Config:
    ponte: ConfigPonte
    logs: ConfigLogs


def carregar(caminho: Path | None = None) -> Config:
    caminho = caminho or RAIZ / "config.toml"
    bruto: dict = {}
    if caminho.exists():
        with open(caminho, "rb") as f:
            bruto = tomllib.load(f)
    p = bruto.get("ponte", {})
    lg = bruto.get("logs", {})
    ponte = ConfigPonte(
        host=str(p.get("host", "127.0.0.1")),
        porta=int(p.get("porta", 8765)),
        intervalo_percepcao_ms=max(500, min(10000, int(p.get("intervalo_percepcao_ms", 2000)))),
        ping_s=float(p.get("ping_s", 5)),
    )
    if ponte.host not in ("127.0.0.1", "localhost", "::1"):
        raise ValueError("ponte.host deve ser local (127.0.0.1): Smith é só single-player offline")
    pasta = Path(lg.get("pasta", "logs"))
    if not pasta.is_absolute():
        pasta = caminho.parent / pasta
    logs = ConfigLogs(pasta=pasta, nivel=str(lg.get("nivel", "INFO")).upper(),
                      gravar_percepcoes=bool(lg.get("gravar_percepcoes", True)))
    return Config(ponte=ponte, logs=logs)
