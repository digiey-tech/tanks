# Tanks

A tank battle for phones and computers, played in the browser.

- **1 Player:** you drive the red tank against a computer-controlled blue
  tank. Pick Easy, Normal or Hard.
- **2 Players:** share one phone, upright between you (Red plays from the
  bottom, Blue from the top), or share one keyboard on a computer.

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

Each hit takes 20 health. The first tank to lose all 100 loses.

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
