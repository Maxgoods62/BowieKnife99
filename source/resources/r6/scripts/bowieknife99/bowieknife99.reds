// BowieKnife — while you drive, on a random timer an existing traffic car turns hostile,
// aggressively rams your car, then is reliably called off. (Forza "bowieknife999" meme.)
//
// All names below are VERIFIED against the REDmod script dump
// (tools/redmod/scripts/core/ai/aiCommand.script + core/components/aiComponent.script):
//   AIVehicleChaseCommand : target, distanceMin, distanceMax, forcedStartSpeed,
//                           aggressiveRamming, ignoreChaseVehiclesLimit, boostDrivingStats
//   AIVehiclePanicCommand : tryDriveAwayFromPlayer, ignoreTickets, disableStuckDetection,
//                           allowSimplifiedMovement, useSpeedBasedLookupRange
//   AIComponent (on the vehicle's AIVehicleAgent):
//     SendCommand(cmd):Bool, CancelCommand(cmd):Bool, CancelCommandById(id, optional doNotRepeat):Bool,
//     CancelOrInterruptCommand(name, useInheritance, success):Bool,
//     GetEnqueuedOrExecutingCommand(name, useInheritance):AICommand,  AICommand.id : Uint32
//
// STOP STRATEGY (the recurring "won't stop chasing" bug): a forceful by-name INTERRUPT
//   CancelOrInterruptCommand(n"AIVehicleChaseCommand", true, true)
// is the primary kill (no id needed); we also CancelCommand(handle) + CancelCommandById(live.id)
// as belt-and-suspenders, then send a panic so it drives off.

module BowieKnife

// Codeware (transitive dep via Audioware) — used only to read the player's voice language so the ram
// taunt can pick the matching localized clip (see RamSoundEvent).
import Codeware.Localization.*
// Audioware's EmitterSettings — needed so AudioSystemExt.RegisterEmitter's optional `ref<EmitterSettings>`
// parameter type resolves (overload resolution checks the full signature even though we omit that arg).
import Audioware.EmitterSettings

public class BowieKnifeSystem extends ScriptableSystem {
  private let m_gi: GameInstance;
  private let m_player: wref<PlayerPuppet>;

  private let m_attacker: wref<VehicleObject>;
  private let m_lastAttacker: wref<VehicleObject>;   // don't immediately re-target the car that just rammed us
  private let m_chaseCmd: ref<AIVehicleChaseCommand>; // held handle (for CancelCommand)
  private let m_attackActive: Bool;
  private let m_smsSent: Bool;          // one SMS per ram, fired only on a real collision
  private let m_lunged: Bool;           // close-range bump surge fired this approach (hysteresis re-arm)
  private let m_watchElapsed: Float;    // seconds the current pursuit has run (timeout accumulator)
  private let m_pickTotal: Int32;       // last selection: eligible cars seen (>=18m, not last attacker)
  private let m_pickRear: Int32;        // last selection: how many of those were behind us
  private let m_pickWasRear: Bool;      // last selection: was the chosen attacker a rear car?
  private let m_cooldownFires: Int32;
  private let m_running: Bool;
  private let m_settings: ref<BowieKnifeSettings>;   // live config from the Mod Settings UI (Nexus 4885)

  // --- tunables: read live from the settings object, falling back to the shipping default until
  //     OnPlayerAttach creates it (see BowieKnifeSettings at the bottom of this file) ---
  private final func Debug()          -> Bool  { return IsDefined(this.m_settings) && this.m_settings.showDebug; }
  private final func SchedPeriod()    -> Float { return IsDefined(this.m_settings) ? this.m_settings.schedPeriod    : 90.0; }
  private final func SpawnChance()    -> Float { return IsDefined(this.m_settings) ? this.m_settings.spawnChance    : 0.05; }
  private final func CooldownFires()  -> Int32 { return IsDefined(this.m_settings) ? this.m_settings.cooldownFires  : 20; }
  private final func PursuitTimeout() -> Float { return IsDefined(this.m_settings) ? this.m_settings.pursuitTimeout : 30.0; }
  private final func MaxDistance()    -> Float { return IsDefined(this.m_settings) ? this.m_settings.maxDistance    : 50.0; }
  private final func MaxHeightDelta() -> Float { return IsDefined(this.m_settings) ? this.m_settings.maxHeightDelta : 6.0; }
  private final func BumpBoost()      -> Float { return IsDefined(this.m_settings) ? this.m_settings.bumpBoost      : 15.0; }
  private final func RearOnly()       -> Bool  { return IsDefined(this.m_settings) ? this.m_settings.rearOnly       : false; }
  private final func RamSoundOn()     -> Bool  { return IsDefined(this.m_settings) ? this.m_settings.ramSound      : true; }
  // The sound played on a confirmed ram: a CUSTOM Audioware (Nexus 12001) clip, NOT a vanilla game event
  // (vanilla VO isn't reachable by name in free-roam — its bank isn't loaded). We register one clip per
  // language as `sfx` IDs in r6/audioware/BowieKnife99/bowieknife99.yml and pick here by the player's
  // VOICE language: French voice -> the French clip, every other language -> the English clip (default).
  // Probe a clip live: `Game.GetAudioSystemExt():Play("bowieknife99_beep")` / `...:Play("bowieknife99_beep_fr")`.
  private final func RamSoundEvent()  -> CName  {
    let loc: ref<LocalizationSystem> = LocalizationSystem.GetInstance(this.m_gi);
    if IsDefined(loc) {
      let lang: CName = loc.GetVoiceLanguage();
      if Equals(lang, n"fr-fr") { return n"bowieknife99_beep_fr"; }
      if Equals(lang, n"de-de") { return n"bowieknife99_beep_de"; }
      if Equals(lang, n"es-es") { return n"bowieknife99_beep_es"; }
      if Equals(lang, n"es-mx") { return n"bowieknife99_beep_es"; }  
      if Equals(lang, n"pl-pl") { return n"bowieknife99_beep_pl"; }
      if Equals(lang, n"it-it") { return n"bowieknife99_beep_it"; }
      if Equals(lang, n"ru-ru") { return n"bowieknife99_beep_ru"; }
      if Equals(lang, n"zh-cn") { return n"bowieknife99_beep_zh"; }   // Simplified Chinese
      if Equals(lang, n"jp-jp") { return n"bowieknife99_beep_ja"; }   // game voice code is jp-jp (not ja-jp)
      if Equals(lang, n"kr-kr") { return n"bowieknife99_beep_ko"; }   // game voice code is kr-kr (not ko-kr)
    }
    return n"bowieknife99_beep";   // English fallback for every other voice language
  }
  private final func MsgCount()       -> Int32 { return 100; }  // AUTO-MANAGED by tools/gen_bowie_sms.py (= len(TAUNTS)); do not hand-edit

  // proven HUD pattern (from adding_my_mod_dialogue.reds: UI_Notifications.WarningMessage)
  private final func Notify(text: String) -> Void {
    if !this.Debug() {
      return;
    }
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = 3.0;
    msg.message = text;
    let bb: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.m_gi)
      .Get(GetAllBlackboardDefs().UI_Notifications);
    if IsDefined(bb) {
      bb.SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(msg), true);
    }
  }

  private final func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    // No pre-game guard needed: there is no PlayerPuppet in the main menu (the cast below
    // returns null and we bail), and during character creation the mod is inert since it only
    // acts while driving. (GameInstance has no GetSystemRequestsHandler()/IsPreGame() — that
    // lives on inkISystemRequestsHandler, reachable only from UI controllers, not a system.)
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) {
      return;
    }
    this.m_player = player;
    this.m_gi = player.GetGame();
    this.m_attackActive = false;
    this.m_cooldownFires = 0;
    if !IsDefined(this.m_settings) {
      this.m_settings = new BowieKnifeSettings();
      ModSettings.RegisterListenerToClass(this.m_settings);
    }
    if !this.m_running {
      this.m_running = true;
      this.ScheduleTick();
    }
  }

  private final func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.CallOff();
    if IsDefined(this.m_settings) {
      ModSettings.UnregisterListenerToClass(this.m_settings);
    }
    this.m_running = false;
  }

  private final func GetPlayerVehicle() -> ref<VehicleObject> {
    let player: wref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return null;
    }
    let mf = GameInstance.GetMountingFacility(this.m_gi);
    if !IsDefined(mf) {
      return null;
    }
    let info: MountingInfo = mf.GetMountingInfoSingleWithObjects(player);
    let ent: ref<Entity> = GameInstance.FindEntityByID(this.m_gi, info.parentId);
    return ent as VehicleObject;
  }

  // Pick a car with RUNWAY to build speed: at least ~18m away (so it can accelerate into a real hit
  // instead of a slow nudge), within a configurable radius (default 50m), AND within a height window
  // (default 6m) so a car on a bridge/overpass above or a road below is skipped. Skip the previous attacker.
  // Every car that clears those gates is buffered, then ONE is chosen at RANDOM (not the nearest) so the
  // same spot doesn't always produce the same attacker. DIRECTION is mode-controlled by RearOnly():
  //   - ON : only a moving traffic car BEHIND us is eligible, so it chases up from the rear with no
  //          U-turn in front (natural-looking).
  //   - OFF (default): any direction is eligible — oncoming/side traffic can attack too (more chaos).
  // If no candidate this cycle, return null and retry next scheduler period.
  //
  // KEY: TSQ_ALL() leaves testedSet = TargetingSet.Visible (the view frustum), which is why earlier
  // attempts saw cars=N rear=0 — the query never surfaced anything behind us. TargetingSet.Complete
  // returns candidates regardless of view (same trick GameObject.GetEntitiesAroundObject uses) — required
  // for rear-only mode and still correct for all-directions mode.
  private final func FindAttackerVehicle(playerVeh: ref<VehicleObject>) -> ref<VehicleObject> {
    let q: TargetSearchQuery = TSQ_ALL();
    q.maxDistance = this.MaxDistance();    // configurable search radius (replaces hardcoded 90m)
    q.testedSet = TargetingSet.Complete;   // include cars OUTSIDE the view frustum (i.e. behind us)
    q.filterObjectByDistance = true;       // honor maxDistance, matching GetEntitiesAroundObject
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(this.m_gi).GetTargetParts(this.m_player, q, parts);

    let pp: Vector4 = playerVeh.GetWorldPosition();
    let fwd: Vector4 = playerVeh.GetWorldForward();   // car heading; <0 dot = the car is behind us
    let pid: EntityID = playerVeh.GetEntityID();

    let candidates: array<ref<VehicleObject>>;   // every eligible car this cycle (random pick below)
    let candIsRear: array<Bool>;                 // parallel: was candidate[i] behind us? (for the HUD)
    let total: Int32 = 0;
    let rear: Int32 = 0;

    let i: Int32 = 0;
    while i < ArraySize(parts) {
      let comp: ref<IComponent> = TS_TargetPartInfo.GetComponent(parts[i]);
      if IsDefined(comp) {
        let veh: ref<VehicleObject> = comp.GetEntity() as VehicleObject;
        // only a live traffic car can give chase — skip player, parked, and non-crowd vehicles
        if IsDefined(veh) && veh.GetEntityID() != pid && veh.IsCrowdVehicle() && !veh.IsVehicleParked() {
          let isLast: Bool = IsDefined(this.m_lastAttacker) && veh.GetEntityID() == this.m_lastAttacker.GetEntityID();
          if !isLast {
            let cpos: Vector4 = veh.GetWorldPosition();
            let d: Float = Vector4.Distance(cpos, pp);
            let dz: Float = AbsF(cpos.Z - pp.Z);   // vertical gap: rejects bridge-above / road-below cars
            if d >= 18.0 && d <= this.MaxDistance() && dz <= this.MaxHeightDelta() {
              total += 1;
              // 2D dot of our forward with (car - player); <0 = behind. Z handled by the dz gate above.
              let behind: Float = fwd.X * (cpos.X - pp.X) + fwd.Y * (cpos.Y - pp.Y);
              let isRear: Bool = behind < 0.0;
              if isRear {
                rear += 1;
              };
              // rear-only mode keeps just the behind-us cars; all-directions keeps everything eligible
              if !this.RearOnly() || isRear {
                ArrayPush(candidates, veh);
                ArrayPush(candIsRear, isRear);
              };
            };
          };
        };
      };
      i += 1;
    };

    // pick one eligible car at RANDOM (not the nearest) — same RandRange idiom as the SMS picker
    let chosen: ref<VehicleObject> = null;
    let n: Int32 = ArraySize(candidates);
    if n > 0 {
      let idx: Int32 = RandRange(0, n);   // 0..n-1, uniform
      chosen = candidates[idx];
      this.m_pickWasRear = candIsRear[idx];
    } else {
      this.m_pickWasRear = false;
    };

    // stash for the (single-slot) HUD message in LaunchAttack — printing here gets clobbered
    // by the ram message in the same frame, so we ride those counts on that surviving message.
    this.m_pickTotal = total;
    this.m_pickRear = rear;

    return chosen;   // a random eligible attacker (rear-only or any direction), or null this cycle
  }

  // ---- scheduler ----
  private final func ScheduleTick() -> Void {
    let cb: ref<BKSchedCallback> = new BKSchedCallback();
    cb.system = this;
    GameInstance.GetDelaySystem(this.m_gi).DelayCallback(cb, this.SchedPeriod(), false);
  }

  public final func OnSchedTick() -> Void {
    if !this.m_running {
      return;
    }
    // master on/off from the Mod Settings UI — keep rescheduling so re-enabling resumes without a reload
    if IsDefined(this.m_settings) && !this.m_settings.enabled {
      this.ScheduleTick();
      return;
    }
    if this.m_cooldownFires > 0 {
      this.m_cooldownFires -= 1;
    } else {
      if !this.m_attackActive {
        let veh: ref<VehicleObject> = this.GetPlayerVehicle();
        if IsDefined(veh) {
          if RandF() < this.SpawnChance() {
            this.LaunchAttack(veh);
          };
        };
      };
    };
    this.ScheduleTick();
  }

  // ---- hijack nearest traffic car + send aggressive ram ----
  private final func LaunchAttack(playerVeh: ref<VehicleObject>) -> Void {
    let attacker: ref<VehicleObject> = this.FindAttackerVehicle(playerVeh);
    if !IsDefined(attacker) {
      this.Notify("BK: no target (cars=" + IntToString(this.m_pickTotal) + " rear=" + IntToString(this.m_pickRear) + ")");
      return;
    }
    this.m_attacker = attacker;
    this.m_attackActive = true;
    this.m_watchElapsed = 0.0;
    this.m_smsSent = false;
    this.m_lunged = false;

    attacker.TurnEngineOn(true);
    let agent = attacker.GetAIComponent();
    if !IsDefined(agent) {
      this.m_attackActive = false;
      return;
    }

    let cmd: ref<AIVehicleChaseCommand> = new AIVehicleChaseCommand();
    cmd.target = playerVeh;
    cmd.distanceMin = 0.0;
    cmd.distanceMax = 0.0;             // 0 = drive all the way in (no follow band) = harder hit
    cmd.aggressiveRamming = true;
    cmd.boostDrivingStats = true;
    cmd.ignoreChaseVehiclesLimit = true;
    // NB: no forcedStartSpeed — he starts at natural traffic speed (no unnatural jump at selection).
    // The acceleration now happens on close approach as a physics surge (see MaybeBump in Watch()).
    this.m_chaseCmd = cmd;
    agent.SendCommand(cmd);

    let dir: String = this.m_pickWasRear ? "REAR" : "FRONT";
    this.Notify("BK RAM [" + dir + "] cars=" + IntToString(this.m_pickTotal) + " rear=" + IntToString(this.m_pickRear));
    this.Watch();
  }

  // watchdog: SMS + flee fire on a REAL collision (OnVehicleGridHit). This watchdog is only the
  // "he missed" safety timeout (PursuitTimeout, default 30s) so the chase always ends with no contact.
  public final func Watch() -> Void {
    if !this.m_attackActive {
      return;
    }
    let attacker: ref<VehicleObject> = this.m_attacker;
    let veh: ref<VehicleObject> = this.GetPlayerVehicle();
    if !IsDefined(attacker) || !IsDefined(veh) {
      this.StopAttacker();
      this.EndAttack(false);   // aborted (lost the cars) — no hit, no cooldown
      return;
    }
    this.MaybeBump(attacker, veh);   // surge forward to bump when he closes in
    if this.m_watchElapsed >= this.PursuitTimeout() {   // configurable give-up; give a far car time to close
      this.StopAttacker();
      this.EndAttack(false);   // timed out without a hit — failed attempt, no cooldown
      return;
    }
    this.m_watchElapsed += 0.6;   // matches the 0.6s reschedule below (no Int/Float cast needed)
    let cb: ref<BKWatchCallback> = new BKWatchCallback();
    cb.system = this;
    GameInstance.GetDelaySystem(this.m_gi).DelayCallback(cb, 0.6, false);
  }

  // Close-range BUMP surge: when Bowie gets within ~16m, give him one forward physics impulse aimed
  // at the player so he lunges in for the hit (replacing the old forcedStartSpeed jump-at-selection).
  // A PhysicalImpulseEvent's worldImpulse = mass * deltaV, so BumpBoost() is literally the m/s gained.
  // Hysteresis (re-arm only after he falls back beyond 30m) keeps it to one surge per approach.
  private final func MaybeBump(attacker: ref<VehicleObject>, playerVeh: ref<VehicleObject>) -> Void {
    let boost: Float = this.BumpBoost();
    if boost <= 0.0 {
      return;   // surge disabled
    }
    let ap: Vector4 = attacker.GetWorldPosition();
    let pp: Vector4 = playerVeh.GetWorldPosition();
    let dx: Float = pp.X - ap.X;
    let dy: Float = pp.Y - ap.Y;
    let len: Float = SqrtF(dx * dx + dy * dy);   // horizontal distance to the player
    if this.m_lunged {
      if len > 30.0 {
        this.m_lunged = false;   // fell back — re-arm for the next approach
      }
      return;
    }
    if len > 16.0 || len < 0.1 {
      return;   // not close enough yet (or degenerate)
    }
    this.m_lunged = true;
    let mag: Float = attacker.GetTotalMass() * boost;   // impulse magnitude -> +boost m/s toward player
    let imp: ref<PhysicalImpulseEvent> = new PhysicalImpulseEvent();
    imp.radius = 1.0;
    imp.worldPosition.X = ap.X;
    imp.worldPosition.Y = ap.Y;
    imp.worldPosition.Z = ap.Z + 0.3;
    imp.worldImpulse.X = (dx / len) * mag;
    imp.worldImpulse.Y = (dy / len) * mag;
    imp.worldImpulse.Z = 0.0;   // horizontal only — don't launch him into the air
    attacker.QueueEvent(imp);
    this.Notify("BK: BUMP surge");
  }

  // Reliable stop: a forceful by-name INTERRUPT (primary), plus cancel-by-handle and cancel-by-id
  // as backups, then a panic so the car drives away.
  private final func StopAttacker() -> Void {
    let attacker: ref<VehicleObject> = this.m_attacker;
    if !IsDefined(attacker) {
      return;
    }
    let agent = attacker.GetAIComponent();
    if !IsDefined(agent) {
      return;
    }

    // 1) primary: forcibly interrupt the executing chase by name (no id needed)
    agent.CancelOrInterruptCommand(n"AIVehicleChaseCommand", true, true);
    // 2) backup: cancel the exact command object we hold
    if IsDefined(this.m_chaseCmd) {
      agent.CancelCommand(this.m_chaseCmd);
    }
    // 3) backup: cancel by the live command's id
    let live: ref<AICommand> = agent.GetEnqueuedOrExecutingCommand(n"AIVehicleChaseCommand", true);
    if IsDefined(live) {
      agent.CancelCommandById(live.id, true);
    }

    // send it off
    let panic: ref<AIVehiclePanicCommand> = new AIVehiclePanicCommand();
    panic.tryDriveAwayFromPlayer = true;
    panic.ignoreTickets = true;
    panic.disableStuckDetection = true;
    agent.SendCommand(panic);

    this.Notify("BowieKnife: called off (fleeing)");
  }

  // landed = did Bowie actually ram us? The cooldown is the "rest" after a SUCCESSFUL hit; a failed
  // attempt (timeout / aborted) must NOT burn the cooldown, so the next check can roll again normally.
  public final func EndAttack(landed: Bool) -> Void {
    this.m_lastAttacker = this.m_attacker;   // remember it so we don't re-chase it next time
    this.m_attacker = null;
    this.m_chaseCmd = null;
    this.m_attackActive = false;
    if landed {
      this.m_cooldownFires = this.CooldownFires();
    }
    // miss: leave m_cooldownFires at 0 — a failed tentative isn't penalized with a cooldown
  }

  // Called from the @wrapMethod collision hook for EVERY vehicle grid-destruction in the world.
  // We only act if it's our active attacker physically hitting the player's vehicle.
  public final func OnVehicleGridHit(victim: wref<VehicleObject>, other: wref<VehicleObject>) -> Void {
    if !this.m_attackActive || this.m_smsSent {
      return;
    }
    if !IsDefined(victim) || !IsDefined(other) {
      return;
    }
    let att: ref<VehicleObject> = this.m_attacker;
    let pv: ref<VehicleObject> = this.GetPlayerVehicle();
    if !IsDefined(att) || !IsDefined(pv) {
      return;
    }
    let attID: EntityID = att.GetEntityID();
    let pvID: EntityID = pv.GetEntityID();
    let vID: EntityID = victim.GetEntityID();
    let oID: EntityID = other.GetEntityID();
    // collision between our attacker and the player's vehicle, either direction
    let isHit: Bool = (vID == pvID && oID == attID) || (vID == attID && oID == pvID);
    if isHit {
      this.m_smsSent = true;
      this.PlayRamSound(att);       // taunt audio on impact, emitted from Bowie's car (feature-flagged)
      this.SendBowieSMS();          // Notifies the exact SMS-stage result (found / sent / failed)
      this.StopAttacker();
      this.EndAttack(true);         // real hit landed — apply the cooldown rest
      return;
    }
    // diagnostic: a collision involving our attacker OR our car, but the pair didn't match.
    // Tells us "collision events DO fire during the ram" vs the SMS never being attempted.
    if this.Debug() && (vID == pvID || vID == attID || oID == pvID || oID == attID) {
      this.Notify("BK: contact, no pair match");
    }
  }

  // Deliver a random authored phone SMS from the "BowieKnife999" contact. Reset Inactive -> Active
  // so the same line can re-fire on a later hit (recycles the pool).
  private final func SendBowieSMS() -> Void {
    let k: Int32 = RandRange(1, this.MsgCount() + 1);   // 1..MsgCount
    let path: String = "contacts/bowie/taunts/msg" + IntToString(k);
    let jm = GameInstance.GetJournalManager(this.m_gi);
    if !IsDefined(jm) {
      this.Notify("BK SMS: no journal mgr");
      return;
    }
    // Resolve first so we can SEE whether the merged journal path is valid (the one thing that
    // can't be checked offline). If this is null, the archive path/format is the bug, not the code.
    let entry: wref<JournalEntry> = jm.GetEntryByString(path, "gameJournalPhoneMessage");
    if !IsDefined(entry) {
      this.Notify("BK SMS: entry NOT found -> " + path);
      return;
    }
    // recycle so the same line can re-fire on a later hit: Inactive(silent) -> Active(notify)
    jm.ChangeEntryState(path, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
    let ok: Bool = jm.ChangeEntryState(path, "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    if ok {
      this.Notify("BK SMS sent #" + IntToString(k));
    } else {
      this.Notify("BK SMS: ChangeEntryState FAILED #" + IntToString(k));
    }
  }

  // Play the taunt on a confirmed ram, via Audioware (HARD dependency — Nexus 12001). The clip is
  // SPATIALIZED: emitted from the attacker car so the taunt comes from Bowie's vehicle (panned and
  // distance-attenuated around the player, who is automatically the listener). The attacker is a
  // VehicleObject (a GameObject), which is a valid Audioware emitter; Audioware auto-unregisters the
  // emitter when the car despawns, so there's no cleanup to do. Falls back to flat 2D if we have no
  // valid emitter. Gated by the ramSound flag.
  private final func PlayRamSound(source: wref<VehicleObject>) -> Void {
    if !this.RamSoundOn() {
      return;
    }
    let audio: ref<AudioSystemExt> = GameInstance.GetAudioSystemExt(this.m_gi);
    let sound: CName = this.RamSoundEvent();
    if IsDefined(source) {
      let id: EntityID = source.GetEntityID();
      let tag: CName = n"bowieknife99_ram";   // Audioware's internal handle for this emitter
      if !audio.IsRegisteredEmitter(id, tag) {
        audio.RegisterEmitter(id, tag);
      }
      if audio.IsRegisteredEmitter(id, tag) {
        audio.PlayOnEmitter(sound, id, tag);   // emitterID + tag must both be valid & non-default
        this.Notify("BK: ram sound (spatial)");
        return;
      }
    }
    audio.Play(sound);   // fallback: flat 2D if the attacker isn't a usable emitter
    this.Notify("BK: ram sound (2D)");
  }

  private final func CallOff() -> Void {
    this.StopAttacker();
    this.m_attacker = null;
    this.m_chaseCmd = null;
    this.m_attackActive = false;
  }
}

// ---- Mod Settings (Nexus 4885) config holder ----
// The framework reflects over these @runtimeProperty fields to build the in-game Settings page and
// writes them back on this instance whenever the user changes a value (it's registered via
// ModSettings.RegisterListenerToClass in OnPlayerAttach). The system reads the fields live — no
// callback. Defaults below are the shipping tune.
public class BowieKnifeSettings extends IScriptable {
  // enabled + showDebug have no category, so they list at the top of the page, above "Behavior".
  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.displayName", "Enable mod")
  @runtimeProperty("ModSettings.description", "Turn the random ramming attacks on or off.")
  public let enabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.displayName", "Show debug HUD")
  @runtimeProperty("ModSettings.description", "Show on-screen debug lines (ram start, pick counts, SMS status). Off for normal play.")
  public let showDebug: Bool = false;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Attack chance")
  @runtimeProperty("ModSettings.description", "Probability an attack triggers on each check (0 = never, 1 = every check).")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "1.0")
  @runtimeProperty("ModSettings.step", "0.05")
  public let spawnChance: Float = 0.05;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Check interval (s)")
  @runtimeProperty("ModSettings.description", "Seconds between attack checks. Lower = attacks happen more often.")
  @runtimeProperty("ModSettings.min", "10.0")
  @runtimeProperty("ModSettings.max", "600.0")
  @runtimeProperty("ModSettings.step", "5.0")
  public let schedPeriod: Float = 90.0;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Cooldown (checks)")
  @runtimeProperty("ModSettings.description", "How many check intervals to wait after an attack before another can trigger.")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "25")
  @runtimeProperty("ModSettings.step", "1")
  public let cooldownFires: Int32 = 20;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Pursuit timeout (s)")
  @runtimeProperty("ModSettings.description", "How long Bowie chases before giving up if he never lands a hit.")
  @runtimeProperty("ModSettings.min", "10.0")
  @runtimeProperty("ModSettings.max", "120.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let pursuitTimeout: Float = 30.0;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Max attacker distance (m)")
  @runtimeProperty("ModSettings.description", "Only cars within this distance behind you can be chosen (they still need ~18 m of runway).")
  @runtimeProperty("ModSettings.min", "20.0")
  @runtimeProperty("ModSettings.max", "120.0")
  @runtimeProperty("ModSettings.step", "5.0")
  public let maxDistance: Float = 50.0;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Max height difference (m)")
  @runtimeProperty("ModSettings.description", "Skip cars whose elevation differs from yours by more than this — avoids cars on a bridge above or a road below.")
  @runtimeProperty("ModSettings.min", "2.0")
  @runtimeProperty("ModSettings.max", "20.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let maxHeightDelta: Float = 6.0;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Attack from behind only")
  @runtimeProperty("ModSettings.description", "On: only cars behind you are chosen, so the attacker chases up from the rear (natural-looking). Off (default): any nearby car can attack, including oncoming/side traffic.")
  public let rearOnly: Bool = false;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Behavior")
  @runtimeProperty("ModSettings.displayName", "Bump speed boost (m/s)")
  @runtimeProperty("ModSettings.description", "When Bowie gets close he surges forward by this much (m/s) to bump you. 0 = no surge, just aggressive driving.")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "75.0")
  @runtimeProperty("ModSettings.step", "1.0")
  public let bumpBoost: Float = 15.0;

  @runtimeProperty("ModSettings.mod", "Bowie Knife99")
  @runtimeProperty("ModSettings.category", "Audio")
  @runtimeProperty("ModSettings.displayName", "Play taunt sound on ram")
  @runtimeProperty("ModSettings.description", "Play a voice line every time Bowie rams your car.")
  public let ramSound: Bool = true;
}

public class BKSchedCallback extends DelayCallback {
  public let system: wref<BowieKnifeSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnSchedTick();
    }
  }
}

public class BKWatchCallback extends DelayCallback {
  public let system: wref<BowieKnifeSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.Watch();
    }
  }
}

// Real physical vehicle-vehicle collision hook. Fires for EVERY grid-destruction in the world,
// so guard cheaply and hand off to the system, which checks it's our attacker hitting the player.
// evt.otherVehicle = the other party; this.GetVehicle() = the vehicle taking the grid damage.
@wrapMethod(VehicleComponent)
protected cb func OnGridDestruction(evt: ref<VehicleGridDestructionEvent>) -> Bool {
  let r: Bool = wrappedMethod(evt);
  if evt.damageMultiplier > 0.0 && IsDefined(evt.otherVehicle) {
    let self: wref<VehicleObject> = this.GetVehicle();
    if IsDefined(self) {
      let sys: ref<BowieKnifeSystem> = GameInstance.GetScriptableSystemsContainer(self.GetGame())
        .Get(n"BowieKnife.BowieKnifeSystem") as BowieKnifeSystem;
      if IsDefined(sys) {
        sys.OnVehicleGridHit(self, evt.otherVehicle as VehicleObject);
      }
    }
  }
  return r;
}

// Phone message-list preview fix.
//
// The contact row's preview comes from MessengerUtils.SetTitle: it reads the conversation's
// GetTitle(); if that string IsStringValid (non-empty) it shows the TITLE, otherwise it falls
// through to the last message text (what we want).
//
// A mod-added conversation can NEVER produce an empty title: the localization loader silently
// drops onscreens entries whose value is "", so an unresolved/blank title key comes back as the
// literal "LocKey#<hash>" — a non-empty string that IsStringValid happily accepts, so the broken
// LocKey is rendered as the preview. (That's the "LocKey#1017240113626931080" the row showed.)
//
// An unresolved "LocKey#..." title is always a bug for ANY conversation, so we treat it as
// "no title": after the original runs, if the chosen title is a raw LocKey, force hasValidTitle
// false so the renderer falls back to the last-message preview. No journal/archive change needed.
@wrapMethod(MessengerUtils)
private static func SetTitle(out contactData: ref<ContactData>, conversationEntry: wref<JournalPhoneConversation>) -> Void {
  wrappedMethod(contactData, conversationEntry);
  if contactData.hasValidTitle && StrBeginsWith(contactData.localizedPreview, "LocKey#") {
    contactData.hasValidTitle = false;
    contactData.localizedPreview = "";
  }
}
