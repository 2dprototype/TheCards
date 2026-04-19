# TheCards

**TheCards** is a fast-paced, competitive implementation of classic card games including **Call Bridge**, **Poker**, **Black Jack**, and **Old Maid**, equipped with full real-time multiplayer support, local AI bots, and a dynamic graphical interface built in the [LÖVE](https://love2d.org) framework.

## Project Structure

This repository is split into distinct components that decouple the game engine, networking, and server logic:

* **`client/`**: The frontend game client powered by LÖVE (Lua). Contains all rendering logic, game state calculation, and UI.
* **`server/`**: The remote Node.js secure WebSocket server (WSS). Handles room creation, broadcasting game state, and client tracking.
* **`proxy_go/` & `launcher/`**: A native local proxy and command-line launcher built to tunnel unencrypted WS traffic from the LÖVE client to the secure WSS remote server seamlessly.
* **`build/`**: Automated output directory for Windows executables containing the bundled `.love` game and proxy binaries.

## Game Modes

### 1. Call Bridge

The core logic of TheCards is derived from traditional Call Bridge mechanics (with Spades serving as the permanent trump suit).

**Game Flow:**
1. **Dealing:** A standard 52-card deck is shuffled and dealt equally to 4 players (13 cards each).
2. **Calling Phase:** Starting with the first player, everyone must "Call" the number of tricks they believe they can win (typically 1-8).
3. **Playing Phase:** The player who initiated the calling leads the first trick.

**Trick Mechanics:**
- **Following Suit:** Players *must* follow the lead suit if they have it. If not, they may play any card.
- **Trumps (Spades ♠):** Spades are permanent trump cards. Cannot follow suit? Play a Spade to win the trick.
- **Winning:** Highest Spade wins. If no Spades, highest card of the lead suit wins. Rank values: 2 (lowest) to Ace (highest).

**Scoring:**
- **Successful Call:** Tricks ≥ Call → Points = Call + (over-tricks × 0.1)
- **Failed Call:** Tricks < Call → Points = -Call

### 2. Poker (Texas Hold'em)

A complete Texas Hold'em implementation with intelligent AI opponents.

**Features:**
- Standard 52-card deck with multiple deck shoes
- Pre-flop, Flop, Turn, and River betting rounds
- Blinds system (Small Blind: $10, Big Blind: $20)
- AI with personalities: Aggressive, Conservative, Normal
- Hand rankings from High Card to Straight Flush
- Chip animations and visual pot display
- Dealer button positioning

**Hand Rankings (Highest to Lowest):**
1. Straight Flush
2. Four of a Kind
3. Full House
4. Flush
5. Straight
6. Three of a Kind
7. Two Pair
8. One Pair
9. High Card

**AI Decision Making:**
- Evaluates hand strength (pre-flop and post-flop)
- Considers pot odds and position advantage
- Tracks player tendencies for adaptive play
- Includes bluffing mechanics (aggressive players bluff more)

### 3. Black Jack

Classic casino Black Jack against a house dealer.

**Features:**
- 4-deck shoe (208 cards)
- Betting system with chips
- Natural Blackjack pays 3:2
- Dealer stands on 17, hits on 16 or less
- Player actions: HIT, STAND, BET, ALL-IN
- Bust detection and automatic payout resolution

**Game Flow:**
1. **Betting Phase:** Players place bets
2. **Dealing:** Two cards to each player, two to dealer (one face down)
3. **Player Turns:** Hit or stand
4. **Dealer Turn:** Reveals hole card, hits until 17+
5. **Payouts:** Winners paid according to standard Blackjack rules

### 4. Old Maid

A strategic card-matching game where the player left with the Joker loses.

**Features:**
- Joker acts as the "Old Maid"
- Players take turns picking cards from opponents
- Automatic pair matching and discarding
- Hover-to-select mechanic with visual feedback
- Shuffle button to rearrange your hand
- Finish order tracking (1st through 4th place)

**Game Flow:**
1. **Dealing:** 51 standard cards + 1 Joker distributed among 4 players
2. **Initial Pairs:** Players discard any matching pairs from their hand
3. **Picking Phase:** Draw a card from the player to your left
4. **Discarding:** If the picked card matches one in your hand, discard the pair
5. **Finish Order:** Players exit when their hand is empty
6. **Loser:** The player holding the Joker when no cards remain

## How to Run

### Prerequisites
- [LÖVE](https://love2d.org) 11.0 or higher installed

### Offline Play (Single Player vs Bots)
```bash
# Windows (drag client folder onto love.exe)
love client/

# Linux/Mac
love client/
```

### Online Multiplayer

**Hosting a Game:**
1. Run the game and enter your username
2. Click "Host Online"
3. Configure game settings (mode, rounds, turn timer)
4. Share the room code with friends
5. Click "Start Game"

**Joining a Game:**
1. Run the game and enter your username
2. Click "Join Online"
3. Enter the host's room code
4. Wait for the host to start

### Network Configuration

Edit `network_config.json` to change the server URI:
```json
{
    "username": "YourName",
    "server_uri": "ws://localhost:8080"
}
```

Default server URIs:
- Development: `ws://localhost:8080`

## Controls

| Action | Input |
|--------|-------|
| Button | Left Click |
| Shuffle hand (Old Maid) | Click SHUFFLE button |
| Toggle scoreboard | Tab |
| Pause menu | Escape |
| Fullscreen toggle | Escape → Toggle Fullscreen |

## Game Settings

### Global Settings
- **Username:** Your display name
- **Server URI:** WebSocket server address
- **Window Size:** Normal, Large, or Fullscreen

### Match Settings (Host only)
- **Game Mode:** Call Bridge / Poker / Black Jack / Old Maid
- **Rounds:** 1-1000 (Call Bridge only)
- **Turn Timer:** 5-60 seconds
- **Deck Pack:** Visual card style (4 options)

## Technical Architecture

### Client (`client/`)
- **main.lua:** Application entry point, state management, UI routing
- **game_logic.lua:** Core game engine, state synchronization, rendering
- **network.lua:** WebSocket client for multiplayer communication
- **ui.lua:** Immediate-mode UI framework for menus and overlays
- **modes/:** Game-specific logic modules
  - `call_bridge.lua` - Trick-taking game logic
  - `poker.lua` - Texas Hold'em with AI personalities
  - `black_jack.lua` - Casino Black Jack
  - `old_maid.lua` - Pair-matching game

### State Synchronization
- Host acts as the authoritative server for game logic
- State updates broadcast to all clients via WebSocket
- Guest clients render received state and send player actions
- Visual animations interpolate between states for smooth gameplay

### AI Implementation
- Call Bridge: Card-counting and probabilistic calling
- Poker: Hand strength evaluation, position awareness, bluffing
- Black Jack: Basic strategy (hit on <17)
- Old Maid: Random selection with strategic pair avoidance