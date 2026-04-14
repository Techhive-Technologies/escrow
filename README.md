# KRABIT Escrow Plugin

A full escrow system for the KRABIT marketplace on Discourse.

## Features

- 💰 Create escrow transactions between two users (buyer & seller)
- 🔒 Funds held until buyer confirms delivery
- ⚠️ Buyer can raise a dispute before confirming
- 🛡️ Admin resolves disputes (release to seller or refund buyer)
- 📊 Per-user escrow dashboard at `/my/escrows`
- 🔔 In-app notifications for all state changes
- ⚙️ Configurable platform fee % via Admin → Settings

## Supported Payment Methods

| Method | Description |
|--------|-------------|
| USDT | Tether (crypto) |
| USDC | USD Coin (crypto) |
| USD_WIRE | USD Wire Transfer |
| NGN_BANK | Nigerian Bank Transfer |

## Escrow Flow

```
[Buyer creates escrow]
        ↓
   status: pending
        ↓
[Admin confirms payment received]
   status: paid  ←── Seller notified
        ↓
[Seller marks as delivered]
   status: delivering  ←── Buyer notified
        ↓
   ┌────┴────┐
   ↓         ↓
[Buyer     [Buyer raises
confirms]   dispute]
   ↓            ↓
completed   disputed
            ↓
       [Admin resolves]
        ↓         ↓
  resolved_    resolved_
  released     refunded
```

## Installation

1. SSH into your Discourse server
2. `cd /var/discourse`
3. `git clone https://github.com/YOUR_ORG/krabit-escrow.git plugins/krabit-escrow`
4. `./launcher rebuild app`

## Admin Configuration

Go to **Admin → Settings** and search `krabit`:

| Setting | Default | Description |
|---------|---------|-------------|
| `krabit_escrow_enabled` | true | Enable/disable the plugin |
| `krabit_escrow_platform_fee_percent` | 5 | % fee charged on each transaction |
| `krabit_escrow_min_amount_usd` | 10 | Minimum escrow amount |
| `krabit_escrow_max_amount_usd` | 100000 | Maximum escrow amount |
| `krabit_escrow_dispute_window_hours` | 72 | Hours buyer has to dispute after delivery |
| `krabit_escrow_auto_release_days` | 14 | Days before auto-release if buyer doesn't respond |

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/krabit/escrows` | List all escrows for current user |
| POST | `/krabit/escrows` | Create new escrow |
| GET | `/krabit/escrows/:id` | Get escrow details |
| POST | `/krabit/escrows/:id/mark_paid` | Admin: confirm payment received |
| POST | `/krabit/escrows/:id/confirm` | Buyer: confirm delivery |
| POST | `/krabit/escrows/:id/dispute` | Buyer: raise dispute |
| POST | `/krabit/escrows/:id/release` | Admin: release funds to seller |
| POST | `/krabit/escrows/:id/refund` | Admin: refund buyer |

## Coming Next

- Commission system (inviter earns % of platform fee on invitee's first escrow)
- Permanent invite links tied to commission tracking
- Admin escrow management dashboard
