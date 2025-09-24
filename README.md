# 📦 StacksFlow Commerce Hub

**Enterprise-Grade Bitcoin Payment Gateway on Stacks**

---

## 📘 Overview

**StacksFlow Commerce Hub** is a robust, enterprise-focused smart contract platform that enables businesses to seamlessly accept sBTC payments on the Stacks blockchain. Built with scalability, security, and flexibility in mind, it empowers merchants to integrate sBTC transactions into their workflows with:

* 🔄 Real-time payment settlement
* 📊 Merchant-level dashboard integration
* ⚖️ Automated platform and business fee distribution
* 🧾 Reference-based payment tracking
* 🔐 Secure, time-locked payments and balance segregation
* 🔁 Built-in refund and withdrawal mechanisms

This contract is ideal for SaaS providers, marketplaces, service platforms, or any business requiring automated and programmable Bitcoin payments on Stacks.

---

## 🏗️ System Overview

### Key Features

| Feature                       | Description                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------------- |
| 🧾 **Payment Invoicing**      | Businesses create invoices with unique reference IDs and expiry windows               |
| ⚙️ **Automated Fee Handling** | Platform and merchant-specific fees (in basis points) are deducted at time of payment |
| 🔄 **Real-Time Settlement**   | Payments are instantly processed and balances updated on-chain                        |
| 🔁 **Refund Support**         | Businesses can refund completed transactions, reverting balance state                 |
| 🔐 **Access Control**         | Only registered businesses can receive funds; only contract owner manages fees        |
| 🌐 **Webhook-Ready Design**   | Payments include reference IDs and metadata suitable for off-chain triggers           |
| 🏦 **Balance Management**     | Businesses accumulate balances and withdraw sBTC on-demand                            |

---

## ⚙️ Contract Architecture

### Constants & Globals

| Name                        | Type        | Purpose                                   |
| --------------------------- | ----------- | ----------------------------------------- |
| `CONTRACT_OWNER`            | `principal` | Owner of the contract, sets platform fees |
| `platform-fee-basis-points` | `uint`      | Platform-level fee (default: 1%)          |
| `fee-collector`             | `principal` | Where platform fees are routed            |

---

### Core Data Structures

#### 1. **Business Registry**

```clarity
(map businesses principal {
  name: string,
  webhook-url: optional string,
  fee-rate: uint,           ;; up to 10%
  is-active: bool,
  total-processed: uint,
  registration-block: uint,
})
```

Each business is registered once, with the ability to update name, fee rate, and webhook URL.

---

#### 2. **Payments**

```clarity
(map payments uint {
  business: principal,
  customer: optional principal,
  amount: uint,
  description: string,
  reference-id: string,
  status: string,           ;; pending, completed, refunded, expired
  created-at: uint,
  expires-at: uint,
  processed-at: optional uint,
  processor: optional principal,
})
```

Each payment has a unique ID and lifecycle managed on-chain. Reference IDs ensure idempotency.

---

#### 3. **References**

```clarity
(map payment-references {
  business: principal,
  reference: string,
} uint)
```

Allows fast lookup of payments using external reference IDs, e.g., invoice numbers.

---

#### 4. **Balances**

```clarity
(map business-balances principal uint)
```

Accumulates the net amount available for business withdrawal after fee deductions.

---

## 🔁 Data Flow

### 1. Register Business

* 📥 Merchant calls `register-business`
* 🗂 Entry created in `businesses` map
* 🔐 Only registered businesses can create payment requests

---

### 2. Create Payment

* 🧾 Business invokes `create-payment`
* 🗂 Entry stored in `payments` map with status `pending`
* 🔁 Reference ID mapped to `payment-id`

---

### 3. Pay Invoice

* 💸 Customer calls `pay-invoice`
* 🔐 Validates expiry, payment status, and business activity
* ⚖️ Transfers sBTC from customer to contract
* 🧾 Net amount goes to business balance
* 💰 Platform fee sent to `fee-collector`
* ✅ Status updated to `completed`

---

### 4. Withdraw Balance

* 🏦 Business calls `withdraw-balance`
* 🔄 Transfers sBTC to business wallet
* 🧮 Deducts from `business-balances`

---

### 5. Refund Payment

* 🔄 Business can refund completed payments
* 💸 Transfers original amount back to customer
* 🔁 Reverts `business-balances`
* 🔄 Status updated to `refunded`

---

### 6. Platform Fee Management

* 🔧 Admin-only functions:

  * `set-platform-fee`
  * `set-fee-collector`

---

## 🛡️ Security Considerations

* All token transfers are wrapped in `try!` and `as-contract` calls to ensure safety and authorization.
* Reference-based duplication is prevented via `payment-references` map.
* Business isolation is enforced through segregated balance tracking.
* Contract owner control is restricted to fee management and does not affect business funds or customer payments.

---

## 📖 Read-Only Functions

| Function                      | Description                                      |
| ----------------------------- | ------------------------------------------------ |
| `get-payment`, `get-business` | Fetch payment or business metadata               |
| `get-payment-by-reference`    | Retrieve payment by reference ID                 |
| `get-business-balance`        | Returns available balance for business           |
| `get-platform-fee`            | Current platform fee in basis points             |
| `calculate-fees`              | Estimates total fees and net payment value       |
| `is-payment-valid`            | Verifies if a payment is pending and not expired |

---

## ✅ Deployment Requirements

* sBTC Token contract must support the standard `transfer` interface.
* `fee-collector` must be a valid principal (non-zero address).
* Deployer (contract owner) must set platform fee and collector address if defaults need adjustment.

---

## 📌 Final Notes

StacksFlow Commerce Hub delivers a **production-ready**, programmable payment interface for **Bitcoin-native applications**. The architecture supports integration with:

* Backend APIs via webhooks
* SaaS platforms with reference-based payments
* dApps needing modular payment processing

The contract is written in **Clarity**, the secure, decidable smart contract language of Stacks. It ensures predictable behavior, upgrade resilience, and transparent execution—critical for financial workflows.
