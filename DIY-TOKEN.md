# DIY signing token — spec (shouzhong safety island)

A home-built hardware signing token for the shouzhong owner key. It holds the
owner's Ed25519 private key in a **secure element**, signs a control law only
after a **physical touch**, and speaks a **line protocol over USB-serial** so
Rusty drives it as a device file. It is the physical upgrade from the flash-drive
key on wee, and the same "small trusted device gating an operation behind a
physical check" pattern the safety island's on-robot MCU ultimately needs.

Status: **plan** — nothing built yet. This is what to order and build.

---

## Design invariants (do not violate)

1. **The robot never changes.** It only ever runs `ed25519-verify OWNER-PUBLIC
   (format "~s" LAW) sig`. The token is used ONCE at commission, off-robot, on
   the owner's laptop. The token never touches the robot.
2. **We do not reinvent two things:** the OS USB stack (a kernel service) and the
   Ed25519 curve math (vetted crypto — the secure element does it in hardware).
   "Our own" = our own **protocol** and our own **verifier**, both already
   zero-dep and robot-side.
3. **Non-extractability comes from the secure element, not from being homemade.**
   A bare MCU with the key in flash is *rehearsal-grade* — say so.
4. **Every claim stays narrow.** "Signed by a key that never left the chip and
   required a physical touch" — never "unhackable".

---

## Bill of materials

| Part | Role | Notes |
|------|------|-------|
| **Secure element** | holds the private key, signs Ed25519 | must do **Ed25519 (EdDSA)**. See choices below. |
| **Host MCU** | USB-CDC serial, talks I2C/SPI to the SE, enforces the touch gate | RP2040 (Pi Pico, ~$4) is plenty. RP2350/Pico 2 if you want the MCU itself hardened (TrustZone/OTP). |
| **Momentary button** | the "touch" | any push-button. |
| **LED** | "waiting for touch" indicator | any. |
| **OLED (optional, recommended)** | show a hash of what's being signed | SSD1306 128×64 (~$3). Upgrades *presence* to *content-confirmation* (see security). |
| Enclosure | optional | keep the button reachable. |

### Secure-element choice (the load-bearing decision)

- **NXP SE050** — mature, widely available, I2C, supports Ed25519. Breakouts
  exist (Arduino shields, Mikroe/SparkFun-class boards). Safe default.
- **Tropic Square TROPIC01** — **open and auditable** secure element, Ed25519,
  SPI. Aligns best with the "no security through obscurity" ethos; newer, check
  dev-kit availability and host-library maturity.
- **AVOID for this design: Microchip ATECC608** — it does ECC **P-256 only, not
  Ed25519**, so its signatures will not verify with our `ed25519-verify`. (Good
  reminder that "has a crypto chip" ≠ "does our curve".)

**Chosen: TROPIC01** — the open, auditable Ed25519 secure element. It matches the
project's "no security through obscurity" spine (you can read what it does rather
than trust a datasheet). Action items its choice implies: confirm dev-kit
availability, the SPI host-library maturity, and that its Ed25519 signing mode
emits a **raw RFC 8032 signature over the message** (the round-trip proof in the
bring-up checklist is where that's verified — do not assume). SE050 stays the
documented fallback if TROPIC01 tooling proves immature.

---

## Architecture

```
  owner's laptop                    the token (never on the robot)
  ┌──────────────┐   USB-CDC   ┌─────────────────────────────────────┐
  │ Rusty signer │◄──serial───►│ MCU (RP2040)                        │
  │ (off-robot)  │ /dev/ttyACM0│   • USB-CDC line protocol           │
  └──────────────┘             │   • touch-gate (button + LED)       │
                               │   • couriers APDUs, holds NO key    │
                               │            │ I2C/SPI                 │
                               │   ┌────────▼─────────┐              │
                               │   │ Secure element   │  key is here │
                               │   │ (SE050/TROPIC01) │  & never     │
                               │   │  Ed25519 sign    │  leaves      │
                               │   └──────────────────┘              │
                               └─────────────────────────────────────┘
```

- The **key is generated on the secure element** and never leaves it. The MCU
  never sees the private key — it forwards a message, the SE returns a signature.
- The **MCU enforces the touch gate**: it will not forward a sign request to the
  SE until the button is pressed (with a timeout).

---

## Line protocol (USB-serial, text, newline-framed, hex payloads)

Text + hex so Rusty's string ops handle it and there's no binary framing to get
wrong. All requests and responses are one line ending in `\n`.

| Request | Response | Meaning |
|---------|----------|---------|
| `PUBKEY\n` | `PUBKEY <64hex>\n` | read the public key (once, at commission) |
| `SIGN <hexmsg>\n` | `SIG <128hex>\n` | sign the raw message bytes (after touch) |
|  | `ERR touch-timeout\n` | no button press within the window |
| `PROVISION\n` *(gated)* | `PUBKEY <64hex>\n` | generate the keypair on the SE — see below |
| any | `ERR <reason>\n` | malformed / SE error |

Notes:
- **Sign the RAW message** (`(format "~s" LAW)` bytes, hex-encoded on the wire) —
  pure RFC 8032 Ed25519, so `ed25519-verify` accepts it unchanged. Do NOT
  pre-hash on the token (that would change what the robot must verify). Control
  laws are small (< 1 KB); no chunking needed. If a message ever exceeds the
  serial buffer, chunk it — still signing the same raw bytes.
- **`PROVISION` must be physically gated** — only honored when a jumper is set or
  the button is held at power-on. Otherwise host malware could silently generate
  a new key it controls. Key generation is a deliberate, rare, physical act.

---

## Firmware (on the MCU)

- Language: **Rust (embassy / rp-hal)** to match the project, or the Pico C SDK.
- Responsibilities: USB-CDC endpoint; parse the line protocol; drive the SE over
  I2C/SPI (via the SE's host library or documented APDUs); enforce the touch gate
  (LED on → wait for button ≤ N s → forward to SE, else `ERR touch-timeout`);
  honor `PROVISION` only when physically gated.
- The firmware implements **no crypto** — the SE does Ed25519. The firmware is a
  courier plus a physical-presence policy.
- (If an OLED is fitted: on `SIGN`, show the first bytes of a hash of the message
  so the human can compare it to the law's hash before touching — see security.)

---

## Host integration (the off-robot Rusty signer)

The signer replaces `sign-law.lisp`'s seed-read with a serial exchange. Honest
detail: a serial device is *almost* a plain file, but two wrinkles —

1. It needs **raw mode** set once: `stty -F /dev/ttyACM0 raw -echo` (via `shell`).
2. `file-read` reads to **EOF**, which a serial stream never sends — so read the
   response **one line with a timeout** instead: `timeout 30 head -n1 /dev/ttyACM0`.

Both use tools already present (`stty`, `head`, `timeout`) on the owner's laptop,
so **Rusty itself needs no change and no new crate**. Sketch:

```lisp
(define PORT "/dev/ttyACM0")
(shell (string-append "stty -F " PORT " raw -echo"))         ; once
(file-write PORT "PUBKEY\n")                                  ; request
(define pub (parse-line (shell (string-append "timeout 5 head -n1 " PORT))))
;; ... later, to sign a law:
(file-write PORT (string-append "SIGN " (hex-of (format "~s" LAW)) "\n"))
(define sig (parse-line (shell (string-append "timeout 30 head -n1 " PORT))))
;; robot side, unchanged:
(ed25519-verify pub (format "~s" LAW) sig)   ; must be #t
```

Coordinating write-then-read has a small race (response could arrive before the
`head` starts); USB-CDC buffers, so a `head` right after the write catches it,
but nail this during bring-up (open the reader first if needed). **Optional
future:** a small native `serial-line` builtin — but it needs termios, i.e. a
crate, so it goes through the crate-decision protocol and is NOT required; the
shell+stty path keeps Rusty untouched, and this is off-robot owner tooling
anyway, never robot-engine code.

---

## Security properties (narrow, honest)

**What it gives you (with a real secure element):**
- **Non-extractable key** — the private key never leaves the SE; there is no file
  to copy. This is the actual upgrade over the wee flash drive.
- **Touch-to-sign** — no signature without a physical button press, so malware on
  the signing laptop cannot sign a law on its own. One touch per law at commission.
- **Physically gated provisioning** — the key can't be silently replaced by
  software.

**What it does NOT give you (say these out loud):**
- **Screenless = presence, not content.** Without the OLED, the touch proves a
  human was there, not that the human approved *this* law — you trust the host to
  send what you think. The OLED (show the law's hash, compare before touching)
  closes this; without it, note the gap.
- **Supply-chain trust in the SE** — you're trusting the chip vendor. An
  **auditable** SE (TROPIC01) narrows this; it never reaches zero.
- **Physical/side-channel attacks on the chip** — out of scope; a determined lab
  with the device is a different threat model.
- **Nothing about sensor integrity** on the robot — still a separate, named
  problem this token does not touch.

**Claim to make:** "the law was signed by a key that never left the secure
element and required a physical touch." Not "unhackable," not "safe."

---

## Bring-up checklist (don't trust until the round-trip passes)

1. Flash firmware; confirm the token enumerates as `/dev/ttyACM0`.
2. Wire the SE; confirm MCU ↔ SE comms.
3. `PROVISION` (physically gated); read `PUBKEY`; record it.
4. **Round-trip proof:** `SIGN` a known message → run `ed25519-verify` in Rusty
   over the same bytes → **must return `#t`**. This is the gate that catches any
   pure-vs-prehash / message-vs-digest mismatch. Same discipline as the YubiKey
   caveat: no trust before this passes on the real device.
5. Wire button + LED; confirm a `SIGN` with no touch → `ERR touch-timeout`.
6. (Optional) OLED shows the message hash; confirm it matches the law's hash.
7. Put the token's public key into the robot's **authorized set** (see below).
8. Point the signer at the serial port instead of the seed file.

---

## Software prerequisite (worth doing before the hardware arrives)

Make the robot verify against a **set** of authorized public keys, not one:

```lisp
(define (island-verify-any datum sig pubkeys)
  (any? (lambda (pk) (ed25519-verify pk (format "~s" datum) sig)) pubkeys))
```

Then the token can be **added** to the authorized set alongside the wee file key
(kept as a locked-away recovery backup), so a lost token doesn't brick the robot.
This is small and golden-pinnable now, independent of the hardware. (Extend to
**M-of-N** later if you want dual control — stronger, needs multiple signatures.)

---

## Open decisions before ordering

1. ~~Secure element~~ **DECIDED: TROPIC01** (auditable). Confirm dev-kit + SPI
   host-library availability; SE050 is the fallback.
2. **Screen:** OLED (content-confirmation) or screenless (presence only).
3. **Firmware language:** Rust (embassy) vs Pico C SDK.
4. ~~Authorized-set now?~~ **DONE:** `island-verify-any` + `AUTHORIZED-KEYS` ship
   in island.lisp (golden-pinned), so adding the token's public key later is a
   config change, not a code change.

Rough cost: ~$15–40 depending on the secure element and whether you add the OLED.
