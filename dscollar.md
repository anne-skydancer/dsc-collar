#DS Collar -- Dynamic RP Collar – Functional & Architectural Narrative

_Last updated: 25 Jun 2025_

---

## Overview
The Dynamic RP Collar is an attachment‑friendly control system designed for role‑play scenarios in Second Life. It emphasises **extensibility**, **maintainability**, and **robust security** while adhering strictly to LSL limitations. All logic resides inside a single prim, keeping inventory management simple for both creators and end‑users.

Four **core scripts** form the backbone of the collar:
1. **Core** – the communications switchboard that listens for touches, routes internal messages, and restarts scripts safely.
2. **Auth** – the identity manager that tracks wearers, owners, trustees, public users, and blacklisted avatars, enforcing consent rules.
3. **Settings** – the persistence layer that remembers every option and access list across resets or reattachments.
4. **Menu** – the user‑interface layer that builds a one‑layer, paginated dialog based on who is touching and which plugins are installed.

Everything beyond these four scripts is treated as an optional **plugin** and can be added or removed without editing the core.

---

## Access‑Control Model
The collar recognises six clearance levels:
* **Blacklisted (‑1)** – no access whatsoever.
* **Backend (0)** – reserved for script‑to‑script chatter.
* **Public (1)** – minimal interaction, typically innocuous fun.
* **Wearer (2)** – the avatar currently wearing the collar when a higher‑level owner exists.
* **Trustee (3)** – a delegated helper with moderate control; up to four can exist.
* **Owner (4)** – full control; limited to one avatar, or the wearer themselves if no owner is set.

Changing these roles requires explicit consent:
* Adding a **trustee** needs approval from the candidate.
* Adding an **owner** requires confirmation from both the prospective owner and the wearer.
* Removing an **owner** (self‑removal) or **trustee** must be acknowledged by the wearer.
* Blacklisting can be done unilaterally for safety.

---

## Interaction Flow
1. **Touch** – An avatar clicks the collar.
2. **Range Check** –
   * If the collar is rezzed on the ground, touches beyond three metres are ignored.
   * If worn as an attachment, the collar ignores touches beyond ten metres.
3. **Identity Check** – The Auth script determines the avatar’s clearance level.
4. **Menu Build** – The Menu script compiles a list of installed plugins the avatar is allowed to see and presents a dialog with up to nine buttons per page and navigation controls along the bottom row.
5. **Command Execution** – Selecting a button notifies the chosen plugin, which performs its task and may open follow‑up dialogs for fine control.

Because only the Menu script produces dialogs for the main screen, users always receive a single, predictable window rather than overlapping pop‑ups.

---

## Plugins at a Glance
Plugins are drop‑in scripts that add discreet features such as poses, restrictive RLV options, or specialty role‑play actions. Each plugin:
* Registers itself with Core when it starts.
* Declares the minimum and maximum clearance levels it serves.
* Speaks on its own private link‑message channel so it never collides with other plugins.
* Delegates root‑menu dialog creation to the Menu script, keeping a consistent look‑and‑feel.

---

## Security & Robustness
* **Private Channels** – Every collar instance derives its internal channels from its unique object key, preventing cross‑talk among different collars.
* **Remote Script Access Disabled** – The collar rejects any attempt to insert or link foreign scripts unless explicitly permitted.
* **Timed‑out Dialogs** – If a user fails to answer within a minute, pending operations are cancelled automatically.
* **Soft Reboot** – Any inventory change triggers a controlled reset cycle that preserves all saved data, reloads plugins, and restores the collar to a ready state without losing owners, trustees, blacklist entries, or lock status.

---

## Compliance with LSL Limitations
* All helper functions sit at the top of each script, preceding the default state.
* Reserved words (such as *key* or *vector*) are never reused as variable names.
* Conditional logic is expressed with traditional `if‑else` chains, as LSL lacks a ternary operator.
* Dialog button labels are kept to twelve characters or fewer.
* Memory usage is monitored, and the wearer receives warnings if free script memory falls below two kilobytes.

---

## Operational Scenarios
| Scenario                                        | Outcome                                                                                                                    |
|-------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| **Public user clicks** while the collar is worn | Sees menu page containing only public‑level plugins.                                                                       |
| **Trustee tries to add another trustee**        | Candidate receives a confirmation dialog; operation completes only if accepted.                                            |
| **Owner self‑removes**                          | Owner must confirm **and** wearer must approve; if either declines, ownership remains.                                     |
| **Collar contents updated** (worn or rezzed)    | Scripts save their state, reset, reload, and anyone nearby experiences only a brief pause before normal operation resumes. |
| **Blacklisted avatar touches**                  | Nothing happens; the collar remains silent.                                                                                |

---

## Development Roadmap
1. **Implement** the four core scripts based on this narrative and the detailed spec.
2. **Create** at least one reference plugin to validate the communication and menu system.
3. **Stress‑test** attachment and rez scenarios with multiple users interacting rapidly.
4. **Draft** user‑facing instructions and support material, keeping technical jargon minimal.

---

## Change Log
* **25 Jun 2025** – Initial narrative drafted in line with the authoritative specification.

---

_This document serves as a high‑level, code‑free overview suitable for designers, testers, and stakeholders who prefer prose over source listings. The accompanying technical specification remains the single source of truth for developers._

