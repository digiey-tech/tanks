// Relay for Tanks online battles.
//
// The game first tries to link two devices directly. Some networks (like
// campus Wi-Fi) block that, so both devices can instead connect here over a
// normal secure WebSocket and this server passes their messages along.
//
// Each 4-digit game code gets its own room (a Durable Object). The host
// connects with ?role=host and waits; the guest connects with ?role=guest.
// Game messages are forwarded untouched. The server's own messages start
// with {"t":"_ so the game can tell them apart:
//   {"t":"_ok"}    you're in the room
//   {"t":"_left"}  the other device left
// A refused connection is closed with code 4404 (no game with that code) or
// 4409 (code already in use, or the game is full).
//
// Runs on Cloudflare's free Workers plan, where going over a daily limit
// makes requests fail rather than costing money.

import { DurableObject } from 'cloudflare:workers';

// Pages allowed to connect. Browsers send this with every WebSocket request;
// it stops other websites from using your daily allowance.
const ALLOWED_ORIGINS = ['https://digiey-tech.github.io'];

// Also allow the game when run from this computer or the local network.
const LOCAL_ORIGIN =
  /^http:\/\/(localhost|127\.0\.0\.1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+)(:\d+)?$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/room\/(\d{4})$/);
    if (!match) return new Response('Tanks relay', { status: 404 });

    const origin = request.headers.get('Origin') ?? '';
    if (!ALLOWED_ORIGINS.includes(origin) && !LOCAL_ORIGIN.test(origin)) {
      return new Response('Forbidden', { status: 403 });
    }
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected a WebSocket', { status: 426 });
    }
    const role = url.searchParams.get('role');
    if (role !== 'host' && role !== 'guest') {
      return new Response('Unknown role', { status: 400 });
    }

    const room = env.ROOMS.get(env.ROOMS.idFromName(match[1]));
    return room.fetch(request);
  },
};

export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    // Keepalive pings are answered without waking the room, so a host
    // waiting for an opponent costs almost nothing.
    ctx.setWebSocketAutoResponse(
      new WebSocketRequestResponsePair('ping', 'pong'),
    );
  }

  async fetch(request) {
    const role = new URL(request.url).searchParams.get('role');
    const host = this.#open('host');
    const guest = this.#open('guest');

    let refusal = null;
    if (role === 'host' && host) refusal = [4409, 'Code in use'];
    if (role === 'guest' && !host) refusal = [4404, 'No game'];
    if (role === 'guest' && guest) refusal = [4409, 'Game full'];

    const [client, server] = Object.values(new WebSocketPair());
    // Uses the hibernation API: the room sleeps between messages.
    this.ctx.acceptWebSocket(server, [refusal ? 'refused' : role]);
    if (refusal) {
      server.close(...refusal);
    } else {
      server.send('{"t":"_ok"}');
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, message) {
    const role = this.ctx.getTags(ws)[0];
    if (role === 'refused') return;
    this.#open(role === 'host' ? 'guest' : 'host')?.send(message);
  }

  webSocketClose(ws, code, reason) {
    this.#left(ws);
  }

  webSocketError(ws, error) {
    this.#left(ws);
  }

  #left(ws) {
    const role = this.ctx.getTags(ws)[0];
    if (role !== 'refused') {
      try {
        this.#open(role === 'host' ? 'guest' : 'host')?.send('{"t":"_left"}');
      } catch {}
    }
    try {
      ws.close(1000, 'Left');
    } catch {}
  }

  /** The connected socket for [role], ignoring any that are closing. */
  #open(role) {
    return this.ctx
      .getWebSockets(role)
      .find((ws) => ws.readyState === WebSocket.OPEN);
  }
}
