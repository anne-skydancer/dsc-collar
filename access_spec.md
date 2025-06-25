# “Access” Plugin – Functional & Interaction Specification

_Last updated: 26 Jun 2025_

---

## 1  Purpose & Scope
“Access” is the authority‑management module for the Dynamic RP Collar. It exposes every operation that changes who may control the collar and under what conditions, while ensuring agency safeguards and audit hygiene. The plugin appears as a single **“Access”** button in the collar’s main menu; pressing it leads to a context‑aware submenu whose items reflect both the current Access‑Control‑List (ACL) and the role of the person interacting.

---

## 2  Visible Menu Actions
| Action label   | Shown to…                                                    | Preconditions         | Short description                                                                                 |
|----------  ----|--------------------------------------------------------------|-----------------------|---------------------------------------------------------------------------------------------------|
| **AddOwner**   | Wearer **(ACL 2)** *only if* no owner exists                 | No owner on record    | Starts a dual‑consent flow to promote a candidate to owner (ACL 4).                               |
| **ReleaseSub** | Owner **(ACL 4)** | Owner exists                             | Owner willingly relinquishes control; wearer must also confirm. Logs by this owner are purged.                            |
| **AddTrust**   | • Wearer (if no owner) **or** Owner (if owner exists)        | <4 trustees currently | Adds a trustee (ACL 3) via wearer/owner confirmation plus candidate acceptance.                   |
| **RevokeTru**  | Same as *AddTrust* visibility | At least one trustee exists  | Removes selected trustee; wearer (or owner) confirms; trustee’s logs are purged.                                          |
| **Blacklist**  | Any avatar with **ACL ≥ 2**                                  |—                      | Immediately adds chosen avatar to blacklist (ACL –1).                                             |
| **Unblacklst** | Same as *Blacklist* | Avatar must already be blacklisted     | Requires single confirmation by acting user; removes from blacklist.                                                      |
| **Runaway**    | Wearer **(ACL 2)** when an owner exists                      | Owner must be present | Wearer unilaterally expels owner without owner’s approval; confirmation dialog prevents misclick. |
| **BACK**       | Everyone                                                     | —                     | Returns to collar’s main menu.                                                                    |

*All button captions are ≤ 12 characters to respect LSL dialog limits.*

---

## 3  Process Flows
### 3.1  Add Owner (Dual‑Consent)
1. **Wearer** selects **AddOwner**.  
2. Collar asks wearer to input or select the candidate’s UUID → confirmation dialog “Confirm promote?”.  
3. On wearer confirmation, a dialog is sent to **candidate** asking to *accept ownership* (60‑second timeout).  
4. If accepted, `dsc_auth` records candidate as owner → collar issues **soft‑reboot** so every script refreshes ACL state.  
5. Failure (timeout or decline) aborts with no change.

### 3.2  Release Sub (Owner‑initiated voluntary removal)
1. **Owner** chooses **ReleaseSub**.  
2. Owner receives confirm dialog.  
3. If confirmed, **wearer** must also confirm.  
4. Upon wearer approval, owner is removed, all logs referencing that owner are purged, and collar soft‑reboots.  
5. Decline by either party cancels.

### 3.3  Add / Revoke Trustee
*Add* mirrors “Add Owner” (dual consent between acting avatar and candidate) but target role is ACL 3 and no logs are purged on addition.  
*Revoke* mirrors “Release Sub” but affects a trustee; acting avatar (wearer/owner) starts, wearer (or owner when present) confirms, trustee does **not** confirm. Logs are purged upon removal.

### 3.4  Blacklist & Unblacklist
* **Blacklist** takes effect immediately—no consent needed, no dialogs to the target avatar.
* **Unblacklst** shows a confirm dialog to acting user; on confirm the avatar is removed from the blacklist.

### 3.5  Runaway (Wearer‑only emergency)
1. Wearer presses **Runaway**.  
2. Collar warns: “This will remove your owner. Proceed?”  
3. On confirmation, owner is purged, associated logs cleared, collar soft‑reboots. Owner is **not** consulted.

---

## 4  Link‑Message API Usage
| Command sent by Access | Target script | Purpose                                                   |
|------------------------|---------------|-----------------------------------------------------------|
| `AUTH|ADD|4|<uuid>`    | `dsc_auth`    | Promote avatar to owner                                   |
| `AUTH|DEL|<uuid>`      | `dsc_auth`    | Remove owner / trustee / blacklist                        |
| `AUTH|ADD|3|<uuid>`    | `dsc_auth`    | Add trustee                                               |
| `AUTH|ADD|-1|<uuid>`   | `dsc_auth`    | Add to blacklist                                          |
| `ACLSTAT|REQ`          | `dsc_auth`    | Retrieve current owner/trustee/blacklist snapshot         |
| `SOFTREBOOT`           | `dsc_core`    | Instruct Core to broadcast `CORE|RELOAD` cycle            |
| `CLEARLOGS|<uuid>`     | All plugins   | Let feature plugins erase data tied to the removed avatar |

Dialogs and confirmations are delivered on the plugin’s private chat channel (negative, object‑unique), guaranteeing no cross‑talk with other Access instances.

---

## 5  State & Timeout Behaviour
* **Pending transactions** are tracked in‑memory per avatar with a 60‑second timeout; expiry reverts to the Access submenu.  
* Plugin survives soft‑reboot because Core triggers `CORE|RELOAD` only *after* it persists ACL changes via `dsc_settings`.

---

## 6  Security & Edge‑Case Rules
* A trustee cannot add another trustee—only the current owner or a wearer without owner can.  
* The wearer cannot remove the owner through **Revoke Trustee**; they must use **Runaway**.  
* If the maximum of four trustees is reached, **AddTrust** is hidden.  
* If no trustees exist, **RevokeTru** is hidden.  
* If the acting avatar loses permission mid‑flow (e.g., owner removes themselves before confirmation), the transaction aborts and prompts the avatar to re‑open the Access menu.

---

## 7  Implementation Notes (for developers)
* Confirmation dialogs reuse the collar’s existing per‑avatar session logic—Access stores `[avatar, step, target]` in a lightweight list.  
* UUID entry can leverage Second Life’s chat‑history capture or be swapped for a fancier avatar picker; this does not affect flow logic.  
* Log‑purge broadcasts are advisory; only plugins that record per‑avatar history need to act on `CLEARLOGS`.  
* After every ACL mutation, **always** call `SOFTREBOOT` so Core refreshes link‑message routing tables and plugin visibility.

---

_This document defines behaviour and interaction contracts only; LSL source will be produced once these flows are signed‑off._

