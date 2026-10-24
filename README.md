# Waybill

A logistics idle game for iPad, built with Swift, SwiftUI and RealityKit.
Design decisions and research are in [`../Research.md`](../Research.md).

**Status: complete game (v1.0).** Five regions, each a hand-built 3D diorama with its own vehicles and twist:

| # | Region | Vehicles | What's new | Goal to move on |
|---|---|---|---|---|
| 1 | Riverside | Box trucks | The four-step chain, managers, contracts, research | $50M earned |
| 2 | Harbour City | Container trucks, ships, quay cranes | Ships berth in windows; cranes only unload while a ship is in | $2.5B |
| 3 | Granite Pass | Freight trains | Big loads, long trips through tunnels and over a bridge | $60B |
| 4 | Metro | Electric vans (later drones, an air taxi) | Many small trips through drive-through bays | $320B |
| 5 | Orbit | Rockets | Rollout, fuelling, launch, booster landings | $380B → finale, then endless |

A full playthrough takes about two and a half weeks of normal play (three short sessions a day, idle in between),
simulated with `balance.py`.

## Run it

1. Open `Waybill.xcodeproj` in Xcode 27.
2. At the top of the Xcode window, pick your iPad (or an iPad simulator) as the run destination.
3. Press **⌘R**.

First time on a real iPad: unlock it, keep it connected, and if iPadOS asks, trust the developer under
*Settings › General › VPN & Device Management*. With a free Apple ID the app stops launching after 7 days; press ⌘R again to reinstall.

The project file is generated from `project.yml`. If you add or rename files and Xcode doesn't see them, run `xcodegen generate` in this folder.

## How to play

- **Units flow through four stages**: receiving → storage → loading → the fleet. The slowest stage is the *bottleneck* (amber). Upgrade it.
- **Shipment Tracking** (bottom left): every vehicle's trip, step by step: Picked → Loading → In transit → Delivered, with real clock times.
  Swipe or use the arrows to flip through vehicles; tap › to follow one with the camera. When a vehicle is full, its **Dispatch** button is right there.
- **Warehouse** (Riverside): trucks can only load at a free bay. You start with one; when trucks queue up the Warehouse
  row turns amber ("Bays full"). Build the next stage: *Three bays* fits out bays 1 and 3, then *East wing*, *Long hall*
  and *Distribution centre* each add a 12 m hall section with its own bay, more storage and faster put-away (six bays in all).
  Every stage takes a few real minutes and is built in front of you: site fence, slab, steel frames, a crane, cladding.
- **Managers** automate a stage. The fleet manager (Dispatcher, Station master, Flight director…) sends vehicles for you, also while the app is closed.
- **Contracts** (unlock with the Dispatcher): timed jobs from clients. Accept one, your fleet ships to the client first, finish in time for cash and ★ reputation.
- **Research** (unlocks after the first contract or $15K): one project at a time, real time. Every project changes the world (solar roofs, cranes, drones…). Tap **Show** to fly there.
- **Rush** doubles everything for 20 seconds.
- **Expand**: when a region's goal is reached, move the company on. Money, levels, managers and research start over;
  ★ reputation (+1% income each) and the network (+50% income per finished region) stay.
- **Offline**: up to 8 hours (12 with the canteen-type research) are simulated when you come back.

## Controls

| Gesture | Does |
|---|---|
| One finger drag | Move around (flick for momentum) |
| Pinch | Zoom towards your fingers |
| Two-finger twist | Rotate |
| Trackpad scroll | Zoom |
| Buttons on the right | Zoom, rotate 45°, home |
| Tap the site name | Your network: every region and its progress |
| Tap the clock | Studio: preview any time of day, sound, rendering, frame rate |

## Sound

Everything you hear is generated in code (`Audio/Synth.swift`): wind, traffic, water, birds, crickets at night, gulls and ship horns in
the harbour, train horns in the mountains, a city hum in Metro, plus short effects for dispatches, upgrades, contracts and research.
Turn it off in the Studio.

## How the code is organised

```
Waybill/
├─ App/            WaybillApp (creates the game and the world once), GameScreen (world + interface + overlays)
├─ Game/           the rules, no graphics
│  ├─ Region.swift       the five regions: stages, fleet, goals, names
│  ├─ Economy.swift      formulas (costs, rates, milestones), number formatting
│  ├─ GameModel.swift    state, simulation, vehicles (queue → dock → load → road), contracts, research, saving, offline
│  ├─ Fleet.swift        vehicles and shipments (what the tracker shows)
│  ├─ Contracts.swift    contract generator and clients
│  └─ Research.swift     all research projects and their effects
├─ Audio/          Synth (sound maths) and SoundEngine (ambience + effects)
├─ Theme/          Palette (every colour), Brand (the Route W mark)
├─ UI/             HUD, ShipmentTracker, OpsPanel (tabs), Contracts/Research views, status chips, expansion card, finale
└─ World/
   ├─ WorldController.swift   the 3D view, frame loop, labels, day/night, camera commands
   ├─ CameraRig.swift         smooth camera (goals + gliding), per-region home view
   ├─ FleetVisual.swift       what the world controller needs from any fleet display (trucks, trains, vans, rockets)
   ├─ GameVisuals.swift       stock you can see (pallets, containers, crates, cages, canisters), money popups
   ├─ ResearchVisuals.swift   research that grows into the world
   ├─ Studio.swift            renders vehicle thumbnails on a green screen
   ├─ Core/                   Kit (one detailed object = one merged entity), Scenery (static world merged per
   │                          material), MeshBuilder (boxes, lathe-turned shapes…), materials, textures, maths
   ├─ Build/                  props, vehicles, trains, rockets, harbour machines, shared city/road pieces,
   │                          Warehouse (the hall in 12 m sections, bays, doors, construction), DockWork (pallet trucks)
   ├─ Motion/                 paths, speed plans (MotionPlan), scripted animators,
   │                          YardTraffic (Riverside, Harbour, Metro: vehicles that queue, claim space and never drive
   │                          through each other or the passing traffic)
   ├─ Regions/                one world builder + one research file per region
   └─ Render/                 post-processing: ambient occlusion, colour grade, night glow, FXAA edge smoothing
```

## Brand

`Design/brand-board.png` is the identity sheet: the Route W mark and how it's built, colours, type, a shipping label,
the five regions and the interface pieces. `Design/brand-board.swift` renders it (pass it a folder with the screenshots).
The mark itself lives in `Theme/Brand.swift`.

## Graphics

- **Models** are built in code from rounded boxes and *lathe-turned* shapes (tyres, rims, tanks, rockets, trees).
  Every vehicle is one merged model (`Kit`) with separate entities only for what moves or lights up
  (wheels, forks, headlights), so a detailed truck costs a handful of entities instead of fifty.
- **Materials**: clear-coated glossy paint on vehicles, chrome, aluminium, rubber, tinted glass, glowing light lenses.
- **Post-processing** (`World/Render`): ambient occlusion (angle-based, no banding on flat ground), colour grade,
  night glow and FXAA edge smoothing. RealityKit's own frame has hard, jagged edges; FXAA is what makes it look clean.
- The interface is always light (Dark Mode would turn the glass panels grey).

## Yard traffic (Riverside, Harbour, Metro)

Trucks drive with real speed along paths and look ahead every frame; they brake for any truck in the way. Backing into
a bay or pulling out and driving to the exit first *claims* the whole area the manoeuvre sweeps (a 1 m grid); the claim
is granted only when that area is empty and is released bit by bit as the truck moves. Trucks without a claim keep out
of claimed and requested space. The trucks in the waiting line look identical, so if two arrive in the "wrong" order
they quietly trade places (only their labels swap). `-yardDebug YES` prints the state of every truck every 5 s.

**Driving like a real truck.** Every route is followed by the truck's rear axle and the truck faces along it, so the back
follows the line and the cab swings wide, as with a real rigid truck (no sliding sideways). The routes are built from
straight runs and arcs no tighter than the truck can steer (`Routes.swift`: Dubins curves and "turtle" routes) and were
checked against the fence, the gate, the exit and the trucks in the other bays with a small design tool. In through the
gate on an S-bend, along the yard lane past the bay, cab swung out towards the fence, one smooth reverse arc that
straightens out over the last 12 m onto the bumpers; out: straight out of the bay, a wide right turn onto the lane, out
through the west exit on an S-bend (bay 1, beside the forklifts, pulls out past their corner and sweeps across to the exit).
Drivers signal: right indicator towards the bay, hazard lights while backing onto the dock, right indicator pulling out.

Docking works like a real yard: once the truck is on the bumpers the dock door rolls up and the leveller lip drops onto
the truck bed; the bay's pallet truck loads it. When it's full the pallet truck goes back inside, the lip folds up, the
door comes down, the light turns green, and the truck pulls out. A dock marshal on the platform walks to the bay a truck
is backing into, waves it back and signals stop as it reaches the bumpers.

The economy knows the yard too: a truck needs time to drive from the waiting line to its bay (further along the hall = longer),
backing in takes about 10 s, and a bay needs time to close up. While the app is open the 3D yard keeps the economy in step:
a truck only counts as docked once it's on the bumpers of its own bay and as back once it has come in through the gate, and
a bay goes to the next truck only after the last one has pulled out (capped at 40 s, never used for the time the app was
closed). After the app has been away, the yard is placed afresh from the economy (nothing half-finished from before is
left standing). Every combination of "where the economy has a truck" and "where the yard shows it" has a defined
outcome (a truck still parked at a bay it no longer has leaves; a bay reservation the economy dropped is cancelled).

**Forklifts and pallet trucks** steer with their rear wheels, so their front axle follows the path and the counterweight
swings round. The two forklifts share their corner of the dock: one drives, the other waits.

**People** have jointed legs, arms and heads (`PersonAnimator`): a walk cycle driven by how far they actually move,
standing still they look around now and then; gestures (waving a truck back, stop) for the marshal.

**Harbour** uses the same yard with articulated haulers: the trailer is pulled along behind the fifth wheel (it cuts
inside the turns), and every route was checked with the trailer's real sweep. In on the westbound road and one right turn
through the gate (the canopy is cantilevered on that side), into lane A or B; out north, round and down the exit road.
Only the next hauler waits inside the gate, the rest off the map. Passing road traffic joins the yard as guests: it keeps its
distance, stops for haulers turning in and pulling out, and the haulers brake for it.

**Metro**: electric vans through four drive-through bays. In off the avenue through the gap between the planters, along
the yard lane, a right turn into the bay; the van's side door slides open, the bay's hub worker pushes roll cages from the
stack behind the van to the door and rolls them in (at least one per visit; the van waits until they're clear), the door
closes and the van drives on through the hub and left onto the back street. Lights beside each portal show green (free)
or red (in use). The fourth bay (D, west) opens with the hyperloop research; a dock the layout has no bay for always
falls back on a real bay (never a crash). The autonomous truck comes along the back street, stops in the service yard
and reverses onto the side dock in one arc (its routes are for the rear axle too), rolls its shutter up, unloads and
leaves by the side street. Sorter robots (research) run a one-way loop between the stock area and a hatch in the
hub's west wall, keeping their distance and never crossing the vans' lanes.

**Granite and Orbit** have no yard fleet on the road (trains, rockets), so their passing traffic is a `RoadTraffic`:
steady speed, keeping distance, braking for anything on its lane. Their supply trucks (`Common.supplyRun`) turn in,
pull up beside the crate stacks / canister rows, unload and leave, joining the road only in a gap; one at a time.
Curbs drop where vehicles cross them (`Common.curb` driveways) in every region.

## Saving

The game saves every 5 s, right away when research or a warehouse expansion finishes, and when the app goes to the
background (encoding and writing happen off the main thread). Loading reads every field on its own, with a default
when one is missing or changed by a new version, and keeps every list entry that still reads: an update never wipes
the game. A copy of the last good save is kept (refreshed at launch and every two minutes); a save that can't be read
is set aside (`waybill-save-unreadable-….json`) and the backup is used. Launches with developer flags that change the
game, or with `-testSave YES`, use a separate test save, so testing never touches the player's own game.

## Performance notes

- Kit models and the static scenery share palette materials: every plain part of a model uses one material and every
  glossy-paint part another, with each part's colour, roughness and metalness read from a tiny texture
  (`MaterialPalette`). A truck draws in about 3 calls instead of 16; Riverside went from ~1,400 to ~560 draw calls.
- Each vehicle's light lenses are one model with a material slot per kind of lamp, fixed wheels on one axle are one
  model, the logos on both sides of a truck are one model.
- Nothing is rewritten every frame unless it changes (`setPosition`, `setOrientation`, `setScale`, `setEnabled`): every
  write makes RealityKit redo the entity's bounds, shadows and draw data.
- The river's material is reused (only its texture offset changes, 30 times a second). With Xcode's Metal Toolchain
  installed, `Design/pending/Water.metal` moves the flow onto the GPU entirely (copy it to `Waybill/World/Render`).
- Audio volumes are only sent when they change audibly, on a background queue (they used to wait for the audio thread).
- Saving encodes and writes off the main thread. The interface's looping animations run in Core Animation.
- Post-processing: ambient occlusion, colour grade, FXAA and a contrast-adaptive sharpen of everything that isn't an edge.
- The 3D view asks RealityKit for 120 Hz through ARView's underscored `__preferredFrameRate` (semi-private, fine for a personal app).
- Low Power Mode, the accessibility "Limit Frame Rate" setting, and heat cap the iPad at 60 fps. That's normal.
- Ambient occlusion only works on a real device (the simulator gives no depth).

## Developer launch arguments

In Xcode: *Product › Scheme › Edit Scheme › Run › Arguments*.

| Argument | Effect |
|---|---|
| `-skipIntro YES` | Skip the intro animation |
| `-resetSave YES` | Start a fresh game |
| `-region harbour` | Start in a region (`riverside`, `harbour`, `granite`, `metro`, `orbit`) |
| `-cash 100000` | Start with this much money |
| `-lifetime 60000000` | Pretend this much was earned in the region (to test expanding) |
| `-openExpansion yes` | Open the expansion (or finale) card at launch |
| `-unlockAll YES` | Hire the fleet manager and unlock contracts and research |
| `-allResearch YES` | Finish every research project of the region |
| `-researchSpeed 60` | Research runs 60× faster |
| `-previewHour 21.5` | Start in preview mode at 21:30 |
| `-cameraDistance 60 -cameraYaw 30 -cameraX 0 -cameraZ 14` | Start with a specific camera view |
| `-showStats YES` | Show RealityKit statistics |
| `-hideHUD YES` | Clean screenshots without interface |
| `-thumbnail truck` | Render one vehicle on green (`truck`, `hauler`, `train`, `van`, `rocket`, `forklift`, `car`, `person`) |
| `-thumbnail lineup -showroom YES` | Showroom: vehicles on a lit floor, camera can go close (`lineup`, `trainset`, `harbour`, or any of the above) |
| `-snapshot 8` | Save the 3D view to the app's Documents/snap.png after 8 s (for checking a device build) |
| `-noAA YES`, `-noAO YES`, `-noShadows YES` | Turn off edge smoothing, ambient occlusion or shadows (to compare) |
| `-depotTier 3` | Start with the warehouse at this stage (1 = starter depot … 5 = distribution centre) |
| `-levels fleet:13,putaway:10` | Start with these stage levels (`receiving`, `putaway`, `shipping`, `fleet`) |
| `-autoBuild 5 -autoBuildDelay 6 -buildSpeed 6` | Keep building the warehouse up to that stage by itself, 6× faster (for recordings) |
| `-yardDebug YES` | Log every truck's state in the yard every 5 s |
| `-testSave YES` | Use the separate test save (implied by any flag that changes the game) |
| `-awayTest 120` | Every 90 s, act as if the app had been closed this long (tests catching up and the yard) |
| `-closeCamera YES` | Let the camera come close (for checking animations); camera numbers below zero are written `m28` |
| `-spikes YES` | Log every frame whose own work takes over 3 ms, slowest parts first |
| `-census YES` | Log entities and draw calls by kind every 5 s |
| `-thumbnail walk -showroom YES` | Animation check: a worker walking a loop, one waving, one standing |
| `-noPalette YES`, `-noSharpen YES`, `-oldWater YES`, `-stillWater YES` | Compare the old way (one material per part, no sharpening, the per-frame water material, frozen ripples) |
| `-hudOff Tracker,Ops` | Leave interface parts out (`TopBar`, `Chips`, `Tracker`, `Rush`, `Ops`, `Camera`) for performance tests |
