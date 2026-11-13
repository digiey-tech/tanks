# Tanks

A tank battle for phones and computers, played in the browser.

- **1 Player:** you drive the red tank against a computer-controlled blue
  tank. Pick Easy, Normal or Hard.
- **2 Players:** share one phone, upright between you (Red plays from the
  bottom, Blue from the top), or share one keyboard on a computer.
- **Two devices:** one player taps **Host** and gets a 4-digit code; the
  other taps **Join** and enters it. Each player sees their own tank at the
  bottom of their screen.

**Play:** https://digiey-tech.github.io/tanks/

## Controls

Each player has their own panel:

- **Thumbstick** – drive in any direction.
- **Rotate buttons** – turn the gun. This only changes where you shoot, not
  how you move.
- **FIRE** – shoot. Hold to keep firing.

In single player you can also **tap or drag in the arena** to aim: the gun
turns toward that spot at its normal speed. **Double tap** to shoot there: the
gun turns to face the spot and fires as soon as it's lined up and reloaded.

### On a computer

Single player: **WASD or arrow keys** to drive, **mouse** to aim (the gun turns
toward the cursor at its normal speed), **left click** in the arena to fire.
**Q/E** and **Space** also work.

Two players share the keyboard (the mouse is off so neither player gets an
edge):

| | Move | Turn gun | Fire |
|---|---|---|---|
| Red | W A S D | Q / E | Space |
| Blue | Arrow keys | , / . | / or Enter |

Each hit takes 20 health. When shells from the two tanks meet, they destroy
each other. The first tank to lose all 100 loses.

## Online play

Devices first try to link directly: they find each other through the free
public [PeerJS](https://peerjs.com) server using the code, then connect
with WebRTC, so on permissive networks the game traffic goes straight
between them. PeerJS 1.5.5 is bundled in `web/` (MIT license) and only
loads when someone picks online play.

Some networks, such as campus Wi-Fi, block direct links. If the joining
device hasn't connected directly within 4 seconds, it also tries the relay
in `relay/`: a small Cloudflare Worker that passes messages between the two
devices over a normal secure WebSocket. Whichever route connects first is
used, and the game bar shows "Online · relay" when it's the relay.

The relay runs on Cloudflare's free Workers plan, where going over a daily
limit makes requests fail instead of costing money; limits reset at
00:00 UTC. To keep within them, the host sends at most 30 updates a second
and both sides skip messages when nothing has changed. To deploy changes to
the relay:

```sh
cd relay
npm install
npx wrangler deploy
```

The host runs the game and sends its state to the guest; the guest sends
its controls back and smooths movement between updates. To check the real
connection in a browser (needs internet), see the steps at the top of
`tool/peer_check/peer_check.dart`.

## Running locally

```sh
flutter run -d chrome
```

To play on a phone on the same Wi-Fi:

```sh
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 8080
```

Then open `http://<your computer's IP>:8080` on the phone.

## Deployment

Every push to `main` runs the tests, builds the web app and publishes it to
GitHub Pages (see `.github/workflows/deploy.yml`).
