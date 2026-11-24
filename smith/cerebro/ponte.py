"""Servidor TCP local que conversa com o corpo (MoonLoader).

Uma mensagem JSON por linha. Só um corpo por vez: uma segunda conexão é
recusada, para nunca haver dois jogos mandando ordens para o mesmo cérebro.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import Awaitable, Callable

from .protocolo import TAMANHO_MAX_LINHA, TIPOS_DO_CORPO, ErroProtocolo, Mensagem, decodificar

log = logging.getLogger("smith.ponte")

Tratador = Callable[[Mensagem], Awaitable[None] | None]


class Ponte:
    def __init__(self, host: str = "127.0.0.1", porta: int = 8765, ping_s: float = 5.0,
                 intervalo_percepcao_ms: int = 2000, versao_cerebro: str = "?") -> None:
        self.host = host
        self.porta = porta
        self.ping_s = ping_s
        self.intervalo_percepcao_ms = intervalo_percepcao_ms
        self.versao_cerebro = versao_cerebro
        self._tratadores: list[Tratador] = []
        self._conexao: tuple[asyncio.StreamReader, asyncio.StreamWriter] | None = None
        self._servidor: asyncio.base_events.Server | None = None
        self._seq = 0
        self._ping_id = 0
        self.conectado = asyncio.Event()
        self.estatisticas = {"recebidas": 0, "invalidas": 0, "enviadas": 0, "conexoes": 0}

    # ---- API pública -------------------------------------------------------

    def ao_receber(self, tratador: Tratador) -> None:
        """Registra uma função chamada para cada mensagem válida do corpo."""
        self._tratadores.append(tratador)

    async def iniciar(self) -> None:
        self._servidor = await asyncio.start_server(
            self._atender, self.host, self.porta, limit=TAMANHO_MAX_LINHA + 1)
        enderecos = ", ".join(str(s.getsockname()) for s in self._servidor.sockets)
        log.info("ponte ouvindo em %s", enderecos)

    @property
    def porta_real(self) -> int:
        assert self._servidor is not None
        return self._servidor.sockets[0].getsockname()[1]

    async def parar(self) -> None:
        if self._conexao:
            _, w = self._conexao
            w.close()
            with contextlib.suppress(Exception):
                await w.wait_closed()
        if self._servidor:
            self._servidor.close()
            await self._servidor.wait_closed()

    async def enviar(self, tipo: str, dados: dict | None = None) -> bool:
        if not self._conexao:
            return False
        _, w = self._conexao
        self._seq += 1
        msg = Mensagem(tipo=tipo, dados=dados or {}, seq=self._seq)
        try:
            w.write(msg.codificar())
            await w.drain()
        except (ConnectionError, OSError) as e:
            log.warning("falha ao enviar %s: %s", tipo, e)
            return False
        self.estatisticas["enviadas"] += 1
        log.debug("-> %s %s", tipo, dados)
        return True

    # ---- interno -----------------------------------------------------------

    async def _atender(self, r: asyncio.StreamReader, w: asyncio.StreamWriter) -> None:
        peer = w.get_extra_info("peername")
        if self._conexao is not None:
            log.warning("recusando segunda conexão de %s (já há um corpo conectado)", peer)
            w.close()
            return
        self._conexao = (r, w)
        self.estatisticas["conexoes"] += 1
        self.conectado.set()
        log.info("corpo conectado: %s", peer)
        pinger = asyncio.create_task(self._pingar())
        try:
            while True:
                try:
                    linha = await r.readline()
                except asyncio.LimitOverrunError:
                    log.error("linha maior que %d bytes; derrubando conexão", TAMANHO_MAX_LINHA)
                    break
                except ValueError:  # limite estourado (StreamReader converte para ValueError)
                    log.error("linha maior que %d bytes; derrubando conexão", TAMANHO_MAX_LINHA)
                    break
                if not linha:
                    break
                if not linha.strip():
                    continue
                try:
                    msg = decodificar(linha)
                except ErroProtocolo as e:
                    self.estatisticas["invalidas"] += 1
                    log.error("mensagem inválida (%s): %.200r", e, linha)
                    continue
                self.estatisticas["recebidas"] += 1
                if msg.tipo not in TIPOS_DO_CORPO:
                    log.warning("tipo desconhecido do corpo: %s", msg.tipo)
                log.debug("<- %s seq=%d", msg.tipo, msg.seq)
                if msg.tipo == "ola":
                    await self.enviar("ola_ok", {
                        "versao_cerebro": self.versao_cerebro,
                        "intervalo_percepcao_ms": self.intervalo_percepcao_ms,
                    })
                await self._despachar(msg)
        except (ConnectionError, OSError) as e:
            log.warning("conexão caiu: %s", e)
        finally:
            pinger.cancel()
            self._conexao = None
            self.conectado.clear()
            w.close()
            with contextlib.suppress(Exception):
                await w.wait_closed()
            log.info("corpo desconectado: %s", peer)
            await self._despachar(Mensagem(tipo="_desconectado"))

    async def _despachar(self, msg: Mensagem) -> None:
        for t in self._tratadores:
            try:
                r = t(msg)
                if asyncio.iscoroutine(r):
                    await r
            except Exception:  # um tratador quebrado não derruba a ponte
                log.exception("erro no tratador de %s", msg.tipo)

    async def _pingar(self) -> None:
        while True:
            await asyncio.sleep(self.ping_s)
            self._ping_id += 1
            await self.enviar("ping", {"id": self._ping_id})
