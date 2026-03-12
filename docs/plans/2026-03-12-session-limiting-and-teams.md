# Session Limiting + Teams Tier Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add concurrent session limiting (one active device per account) and a Teams Tier with 3-seat and 5-seat subscription plans.

**Architecture:** Session limiting uses a `device_sessions` table + two edge functions (register-device, check-device-session) + a Flutter DeviceSessionService. Teams use `teams`/`team_members` tables + `has_team_access` RPC + invite-team-member edge function + TeamScreen UI.

**Tech Stack:** Flutter/Dart, Supabase Edge Functions (Deno/TypeScript), Supabase Postgres, `device_info_plus`, `in_app_purchase`

---

## SECTION 1: Concurrent Session Limiting

### Task 1.1: Device session migration

**Files:**
- Create: `supabase/migrations/20260312000000_add_session_device_tracking.sql`

Create the migration with device_sessions table + RLS policy.

### Task 1.2: register-device edge function

**Files:**
- Create: `supabase/functions/register-device/index.ts`

Upserts (user_id, device_id) in device_sessions, setting last_seen = now(). Returns `{ ok: true, device_id }`.

### Task 1.3: check-device-session edge function

**Files:**
- Create: `supabase/functions/check-device-session/index.ts`

Queries most-recent device for user (ORDER BY last_seen DESC LIMIT 1). Returns `{ valid: true }` if device_id matches, `{ valid: false }` otherwise.

### Task 1.4: DeviceSessionService + pubspec

**Files:**
- Modify: `pubspec.yaml` (add device_info_plus: ^10.1.2)
- Create: `lib/core/services/device_session_service.dart`

Gets stable iOS device ID via `device_info_plus`, registers and checks sessions against edge functions.

### Task 1.5: App lifecycle integration

**Files:**
- Modify: `lib/app.dart`

Add `WidgetsBindingObserver` to `_AppRouterState`. Call `registerDevice()` in `_determineInitialRoute` after valid session. On `AppLifecycleState.resumed`, call `isSessionValid()` with 3s timeout; sign out + show snackbar if false.

---

## SECTION 2: Teams Tier

### Task 2.1: IapService team constants

**Files:**
- Modify: `lib/core/services/iap_service.dart`

Add `kSubscriptionTeam3`, `kSubscriptionTeam5` constants, add to `_productIds`, add `buyTeam3Subscription()` and `buyTeam5Subscription()` methods.

### Task 2.2: Teams migration

**Files:**
- Create: `supabase/migrations/20260312000001_add_teams.sql`

Creates `teams`, `team_members` tables; adds `team_id`, `team_role` columns to `profiles`; creates RLS policies; creates `has_team_access(uid UUID)` SECURITY DEFINER function; creates `auto_join_team_on_signup` trigger.

### Task 2.3: Entitlements model update

**Files:**
- Modify: `lib/core/models/entitlements.dart`

Add `hasTeamAccess` bool field. Update `fromUserProfile` and `fromProfile` factories. Update `canGenerateEstimate` to also allow team access.

### Task 2.4: UserProfile model update

**Files:**
- Modify: `lib/core/models/user_profile.dart`

Add `hasTeamAccess` bool, `teamId` String?, `teamRole` String? fields. Update `fromJson`, `toJson`, `copyWith`.

### Task 2.5: SupabaseService.getProfile() RPC call

**Files:**
- Modify: `lib/core/services/supabase_service.dart`

After fetching profile row, call `client.rpc('has_team_access', params: {'uid': userId})` and inject into the response map before parsing UserProfile.

### Task 2.6: TeamScreen + InviteBottomSheet

**Files:**
- Create: `lib/features/team/team_screen.dart`
- Create: `lib/features/team/invite_member_bottom_sheet.dart`

TeamScreen: FutureBuilder loading team + members from Supabase. Shows seat usage, member list with role badges, "Invite Member" button (owner only). InviteBottomSheet: email input + Send Invite button → calls SupabaseService.inviteTeamMember().

### Task 2.7: invite-team-member edge function

**Files:**
- Create: `supabase/functions/invite-team-member/index.ts`

Auth required. Validates caller is team owner. Inserts pending team_member row. Sends invitation email via Resend with deep link `tradeestimateai://team/join?team_id=XXX&email=YYY`. Returns `{ ok: true }`.

### Task 2.8: Auto-join trigger

Included in Task 2.2 migration.

### Task 2.9: Paywall team cards

**Files:**
- Modify: `lib/features/paywall/paywall_screen.dart`

Add `_buildTeam3Card()` and `_buildTeam5Card()` methods. Add "TEAM PLANS" section between subscription card and "OR buy credits" divider. Blue accent border (`AppColors.accent`). Add team error sources + buy methods.

### Task 2.10: Settings + routes updates

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/app.dart`

Settings: Add "Team Management" ListTile in ACCOUNT section (only shown if `hasTeamAccess`). Update Privacy/Terms URLs to `tradeestimateai.com`. App.dart: Add `/team` route + TeamScreen import.

---

## Section 4: Deploy commands

After both sections pass `flutter analyze`:
```bash
supabase functions deploy register-device
supabase functions deploy check-device-session
supabase functions deploy invite-team-member
supabase db push
flutter analyze
```
