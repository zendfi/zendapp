/// Launch gates.
///
/// Everything here is built and (mostly) working, but is hidden for the
/// initial launch because it isn't verified end-to-end. The code is
/// deliberately left in place rather than deleted — flipping a flag back to
/// `true` is a one-line change, whereas re-adding a deleted feature is not.
///
/// Rule applied when deciding what to gate: **if a user can reach it, it has
/// to work.** A button that opens a "coming soon" dialog, toasts an apology,
/// or does nothing at all is worse than no button, because it spends the
/// user's trust to tell them we shipped something unfinished.
///
/// Each flag notes what it hides and what has to be true to turn it on.
library;

abstract final class ZendFeatures {
  /// Pools (shared savings goals) — creation, the pool list, pool chat
  /// (Mission Room), pool rows in Chats, pool search results, pool push
  /// notifications and `zdfi.me/pool/<code>` deep links.
  ///
  /// Excluded from launch scope by decision, not because it's broken — the
  /// pool backend is the most deeply wired surface in the app. Two known
  /// gaps if re-enabling: there is no add-participant endpoint (members can
  /// only be set at creation), and voice-note *recording* in pool chat is
  /// stubbed because the `record` package conflicts with the current Android
  /// Gradle Plugin version.
  ///
  /// Turn on when: the creation flow and Mission Room redesign land and
  /// pool chat has had a device pass.
  static const bool pools = false;

  /// Vibes (cash sent as a sticker) — the master gate.
  ///
  /// Worth knowing: this one was **not** fully off before. The Vibe creator
  /// in the DM composer is genuinely wired end-to-end (sticker catalogue,
  /// prepare/submit, optimistic send, retry-on-failure), so vibes were live
  /// in DMs while the Zend entry sheet simultaneously told users they were
  /// "coming soon". This now switches off every path.
  ///
  /// Turn on when: the feature is ready to be presented consistently
  /// everywhere it appears.
  static const bool vibes = false;

  /// The gift/Vibe button beside Pay in the Zend entry sheet, specifically.
  ///
  /// Separate from [vibes] because this button was never wired to anything
  /// even when vibes worked — it only ever opened a "coming soon" dialog.
  /// So it stays off until that path routes through the real vibe flow,
  /// regardless of [vibes].
  static const bool vibesFromEntrySheet = false;

  /// Drop — proximity transfers over BLE.
  ///
  /// Gating this also stops the app **advertising over Bluetooth at all**:
  /// `DropDiscoverabilityService.init()` is skipped on sign-in, and the
  /// foreground/background hooks are no-ops. That matters beyond the UI —
  /// an unused BLE advertiser costs battery, and the scan/advertise
  /// permissions are something app review asks about.
  ///
  /// Note the Drop *sender* flow was already unreachable before this flag:
  /// `showDropSheet` is only called from `send_screen.dart`, which nothing
  /// navigates to. What this hides is the "Be Discoverable" toggle in
  /// Settings and the receive-side sheet triggered by a `dropConfirmed`
  /// event.
  static const bool drop = false;

  /// Add Cash in currencies other than naira (USD, EUR, GBP, MXN…), which
  /// would run on Bridge.
  ///
  /// Bridge itself is built out — `bridge_api.rs` allows USD/EUR/GBP/BRL/
  /// MXN/COP/NGN and maps rails (ach and wire → USD, sepa → EUR, spei → MXN,
  /// faster_payments → GBP). But the virtual-account endpoints are
  /// **platform-scoped**: `/api/v1/bridge/customers/:customer_id/
  /// virtual-accounts`, keyed on a Bridge customer, and `user_bridge_kyc`
  /// only does KYC status and start. There is no route that hands a Zend
  /// *user* their own funding account.
  ///
  /// Turn on when: a user can be provisioned a virtual account per currency
  /// behind an authenticated route, and the Bridge webhook credits the
  /// balance and emits a funds-arrived event.
  static const bool addCashOtherCurrencies = false;

  /// Savings / Pockets — the Savings row in the Wallet sheet, Pockets,
  /// goals, and the deposit/withdraw flows.
  ///
  /// Also skips `fetchSavingsSnapshot()` on sign-in (one less cold-start
  /// request for a figure nothing renders) and redirects the savings push
  /// notification, which is the only thing that opens the older
  /// `SavingsScreen`.
  static const bool savings = false;

  /// Virtual/physical cards — the "Cards" row in the Wallet sheet.
  ///
  /// There is no card issuance anywhere in the product. The row led to a
  /// sheet whose only action toasted "Cards are coming soon".
  static const bool cards = false;

  /// Blocking a user, from the DM chat overflow menu.
  ///
  /// The most important one on this list: it rendered with destructive
  /// styling and was *not* disabled, so it looked live, but the handler only
  /// showed "Block feature coming soon". A safety control that silently
  /// doesn't work is actively harmful — someone could believe they had
  /// blocked a person who can still message them.
  ///
  /// Turn on when: there's a real block endpoint and the blocked party can
  /// no longer open a room or deliver messages.
  // On: block/report endpoints exist and block is enforced on DM rooms,
  // DM messages (HTTP + WS) and Sui transfers.
  static const bool blockUser = true;

  /// "Search in chat" and "Disappearing messages" in the DM overflow menu.
  /// Both were rendered greyed-out with no-op handlers.
  static const bool dmChatExtras = false;

  /// Voice notes in the DM composer.
  ///
  /// The mic icon was rendered at 60% opacity with an empty `onTap` — no
  /// recording, and no feedback either, so it read as a broken button rather
  /// than an unavailable one.
  static const bool dmVoiceNotes = false;

  /// In-app live chat support, on the Contact support screen.
  ///
  /// Both the "Live chat" row and the screen's primary "Start live chat"
  /// button were empty callbacks. Email support and the help centre link are
  /// real and remain.
  static const bool liveChatSupport = false;
}
