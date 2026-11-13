# Tanks

A tank battle for phones and computers, played in the browser.

- **1 Player:** you drive the red tank against a computer-controlled blue
  tank. Pick Easy, Normal or Hard. Hard also bounces shots off walls to
  reach you when you hide.
- **2 Players:** share one phone, upright between you (Red plays from the
  bottom, Blue from the top), or share one keyboard on a computer.
- **Two devices:** one player taps **Host** and gets a 4-digit code; the
  other taps **Join** and enters it. Each player sees their own tank at the
  bottom of their screen.

Choose a mode in the menu, then a map before every round: **Classic**,
**Pillars**, **Zigzag**, **Bunkers** or **Crossroads**, or **Random**. Every
map looks the same from both sides, so neither player has an advantage. After
a round, **Play again** starts another round straight away, on the same map
or, if the map came from Random, a new random one; **New map** brings the map
choice back. Online, the players take turns choosing: the host picks the first
map, then after each round it's the other player's turn to either play again
or pick a new map.

**Play:** https://digiey-tech.github.io/tanks/

## Power-ups

Turn them on or off with the **Power-ups** switch in the menu (it applies to
every mode; online games use the host's setting). Now and then one appears on
a random open spot; drive over it to collect it. Only one is out at a time.
After a timed one is collected, the next can't appear until its effect has
run out plus a short pause (after Repair, just the pause). One nobody takes
blinks and vanishes after 15 seconds.

| Power-up | Effect |
|---|---|
| Repair | Heals one hit straight away |
| Power shot | Each hit counts double, for 8 seconds. A power shot also punches through one enemy shell, then is back to normal |
| Speed | Drive 50% faster, for 8 seconds |
| Rapid fire | Reload twice as fast, for 8 seconds |
| Ricochet | Shells bounce twice, for 8 seconds |
| Ice shot | For 8 seconds, hits slow the enemy's driving and turret for a moment |

Active power-ups show as a colored ring around the tank and icons next to its
health bar; both flash for the last 2 seconds before the effect runs out. The Easy CPU doesn't go for them on purpose; Normal and Hard
detour for ones nearby (Hard from farther away).

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

Each hit takes 20 health. Shells bounce once off walls and the arena edge,
then end at the next one (a shell that has bounced has a dimmer center). A
tank's own shells never hurt it, even after bouncing. When shells from the
two tanks meet, they destroy each other. The first tank to lose all 100 loses.

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
