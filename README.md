<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/banner-dark.png">
    <img src="docs/banner.png" alt="Careful" width="720">
  </picture>
</p>

<p align="center"><strong>A distraction blocker for iPhone that unlocks with an NFC card.</strong></p>

<p align="center">
  <a href="#the-card">The card</a> ·
  <a href="#build-and-install">Build & install</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#what-ios-wont-let-you-do">What iOS won't let you do</a> ·
  <a href="../careful">Careful for Mac</a>
</p>

---

Careful is built around a physical NFC card. Your apps are blocked; when you genuinely
need one, you open Careful, **tap your card to the phone, pick that one app, and choose how
long.** Five minutes by default. When the time is up it locks again on its own. Everything
else stays blocked the whole time.

That last part is the point. Most blockers let you pause everything to use one thing, and
"one thing" becomes an hour. Careful never unblocks more than one app at a time, and never
for longer than you said.

Deleting a blocker requires the card too. So does changing your mind.

## The card

You need an NFC card. Any of these work:

- A **[Brick](https://getbrick.app)** or a **[Bloom card](https://bloom.inc)** you already
  own. Both are NFC tags sold with their own blocker apps, and both keep working with those
  apps after you enroll them here — see below for why.
- Literally **any old NFC card**: a blank NTAG sticker, a transit card, a hotel key, a
  conference badge. If your phone reads it, Careful can use it.

Careful enrolls a card by reading its **UID** — the factory serial number in read-only
memory — and later matches on that.

**It never writes to the card.** That's a design rule, not a detail. Reading a UID leaves the
tag untouched, so a card you already use with another app keeps working with that app. The
card reader code has no write path at all.

A UID can be cloned with cheap hardware, so this is friction, not security. For a tool whose
only adversary is you at 11pm, friction is exactly the right amount.

## What it does

- **Blocks apps, websites and whole categories** — whatever Apple's picker offers. A blocked
  website is blocked in Safari and inside other apps' browsers too.
- **Unlocks one item at a time**, for a chosen duration, only with the card.
- **Locks it again automatically** when the time runs out, even if you never reopen Careful.
- **Optional daily windows per item** — YouTube blocked 9 to 5, something else on a
  different schedule, overlaps welcome.
- **Shows a block screen in Times New Roman.** Small joke, real font. It's the only slot on
  Apple's shield that accepts custom artwork, so the word "Blocked" is rendered as an image.

## Build and install

You need a paid Apple Developer account (the Family Controls capability isn't available to
free accounts), an iPhone with NFC, iOS 17 or later, and [Tuist](https://tuist.dev).

```bash
git clone https://github.com/alexanderjmontague/careful-ios
cd careful-ios
tuist generate
```

Open `Careful.xcworkspace`, set your team under Signing & Capabilities for each of the three
targets, and run on your phone. The Family Controls *development* entitlement is granted
automatically to paid teams; only App Store distribution needs Apple's approval form.

On first launch, allow Screen Time access. If iOS says another app already has it, that's
the one-app-at-a-time rule for this authorization — remove the other app under
**Settings → Screen Time → Apps With Screen Time Access** and try again.

### Bundle identifiers

The extension targets use the identifiers `…careful.FoqosDeviceMonitor` and
`…careful.FoqosShieldConfig`. Those names are historical: the App IDs already existed with
the right capabilities, and registering new ones needs a signed-in Xcode session. Renaming
them is a one-time step in the Signing pane and changes nothing else.

## How it works

Three processes share one App Group:

| Target | Role |
|---|---|
| `Careful` | The app. UI, NFC, and the only place decisions are made. |
| `CarefulMonitor` | A DeviceActivity extension. Woken by iOS at schedule boundaries; does one thing: recompute everything from shared state. |
| `CarefulShield` | Draws the block screen. |

**One `ManagedSettingsStore` per item.** Apple allows up to 50 named stores, each with its
own shield set, and they union. Giving every blocked item its own store is what makes
unlocking one of them trivial: clear that store, touch nothing else.

**Blocked is the resting state.** Shields persist on their own — through reboots, even
through deleting the app. Careful only ever has to *change* state, never maintain it.

**Reconcile, don't trust callbacks.** iOS's schedule callbacks are genuinely unreliable
(there are open reports of `intervalDidStart` never firing). So Careful recomputes every
item's correct state from scratch whenever the app comes to the foreground and at every
monitor boundary. A missed callback costs seconds, not a day.

**The 15-minute trick.** DeviceActivity refuses any interval shorter than 15 minutes, which
would leave a 5-minute unlock with no re-lock timer at all. Careful back-dates the interval's
start so it always spans 15 minutes while *ending* exactly at expiry. A start in the past
just fires immediately, and reconcile is idempotent, so that's harmless.

## What iOS won't let you do

Worth knowing before you fork this.

- **You can't open your app from the block screen.** Shield buttons can only dismiss or
  defer. So the flow starts in Careful, not on the shield. For a blocker, that friction is
  arguably a feature.
- **App tokens are opaque.** You never see a bundle ID; the user picks through Apple's
  picker and you get anonymous tokens. Careful labels items using `Label(token)`, which
  renders the real name and icon. Tokens have also been reported to change occasionally.
- **50 tokens per store, or it silently shields nothing.** Careful uses one item per store
  and caps at 50 items.
- **Users can revoke Screen Time access.** There's no passcode lock for third-party apps.
  Careful detects it and says so loudly rather than pretending to work.
- **Nothing works in the simulator.** Screen Time authorization is device-only. The app
  skips the request under `targetEnvironment(simulator)` so the UI can still be developed.

## Layout

```
Project.swift            Tuist manifest: three targets, entitlements, Info.plist keys
Shared/                  Model and blocker — compiled into the app and the monitor
Careful/Sources/         App entry, UI, NFC card reader
CarefulMonitor/          DeviceActivity extension (a dozen lines)
CarefulShield/           Shield configuration extension
```

`Xcode` project files are generated and git-ignored; `tuist generate` recreates them.

## Careful for Mac

Same philosophy, different key. On the Mac there's no card, so unlocking one thing means
writing a real reason for it. See [Careful for Mac](../careful).

## Credit

The extension scaffolding was worked out by studying [foqos](https://github.com/awaseem/foqos)
(MIT), an open-source NFC blocker worth knowing about. Careful started as a fork of it and
was rebuilt from scratch once the design settled.

MIT licensed. Copyright © 2026 Alexander Montague.
