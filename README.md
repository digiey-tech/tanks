# Tanks

A two-player tank battle for one phone, played in the browser. Hold the phone
upright between you: Red plays from the bottom, Blue from the top.

**Play:** https://digiey-tech.github.io/tanks/

## Controls

Each player has their own panel:

- **Thumbstick** – drive in any direction.
- **Rotate buttons** – turn the gun. This only changes where you shoot, not
  how you move.
- **FIRE** – shoot. Hold to keep firing.

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
