# TheCards

TheCards is a fast-paced, competitive implementation of the classic trick-taking card game **Call Bridge**, equipped with full real-time multiplayer support, local AI bots, and a dynamic graphical interface built in the [LÖVE](https://love2d.org) framework. 

## Project Structure

This repository is split into distinct components that decouple the game engine, networking, and server logic:

* **`client/`**: The frontend game client powered by LÖVE (Lua). This contains all rendering logic, game state calculation, and UI.
* **`server/`**: The remote Node.js secure WebSocket server (WSS). It handles room creation, broadcasting game state, and client tracking.
* **`proxy_go/` & `launcher/`**: A native local proxy and command-line launcher built to tunnel unencrypted WS traffic from the LÖVE client to the secure WSS remote server seamlessly.
* **`build/`**: Automated output directory for Windows executables containing the bundled `.love` game and proxy binaries.

## Game Rules (Call Bridge)

The core logic of TheCards is derived from traditional Call Bridge mechanics (with Spades serving as the permanent trump suit) implemented perfectly in `client/game_logic.lua`. 

### The Flow
1. **Dealing:** A standard 52-card deck is shuffled and dealt equally to 4 players (13 cards each).
2. **Calling Phase:** Starting with the first player, everyone must "Call" the number of tricks they believe they can win in the current round. Calls typically range from 1 to 8. 
3. **Playing Phase:** The player who initiated the calling leads the first trick by dropping a card. 

### Trick Mechanics
* **Following Suit:** Players *must* follow the lead suit if they have it. If you do not have a card of the lead suit, you may play any card.
* **Trumps (Spades ♠):** Spades are permanent trump cards. If you cannot follow the lead suit, you can play a Spade to try and win the trick.
* **Winning the Trick:** The trick is won by the highest Spade played. If no Spades are played, the trick is won by the highest card of the original lead suit. Rank values go from 2 (lowest) to Ace (highest).

### Scoring
At the end of a round (after all 13 tricks are played), scores are calculated:
* **Successful Call:** If a player wins a number of tricks greater than or equal to their call, they receive points equal to their Call. Each additional "over-trick" rewards exactly `0.1` points. 
  *(Example: Calling 3 and winning 4 tricks yields `3.1` points).*
* **Failed Call:** If a player wins fewer tricks than they called, they are penalized. Their score is decreased by the amount they called.
  *(Example: Calling 4 and winning 3 tricks yields `-4.0` points).*

The game spans multiple rounds, and the player with the highest total score at the end is crowned the winner!

## How to Run
To play offline against bots or host a local LAN server:
1. Ensure [LÖVE](https://love2d.org) is installed.
2. Drag the `client/` folder onto the `love` executable, or launch via the provided `.bat` scripts.
