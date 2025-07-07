## NAG Changelog

#### v0.7 (2025-07-07)

Features
- Move the cleu logic to init.lua instead of exec.lua
- Move pre- and post-decision logic to init.lua

#### v0.6 (2025-07-07)

Features
- Make NAG code as a mixin, currently for MoP's Destruction Warlock only
- Move the target update logic to init.lua instead of exec.lua

#### v0.5 (2025-07-07)

Features
- First implementation of Destruction Warlock for Mists of Pandaria

#### v0.4 (2025-06-30)

Features
- Added option to include Corruption in the rotation
- Cleaned up Warlock code, now that Mage code is here

The temporary code was kept in case Mage code was needed sometime
But since Mage code is in the repository now, it can be cleaned up

#### v0.3 (2025-06-30)

Features
- Set the NAG group as a separate WeakAuras, without class-specific NAGs
- Added Cataclysm Mage NAGs for posterity
- Moved Immolation as higher priority than Shadow and Flame
- Added Corruption to the Warlock rotation

#### v0.2 (2025-06-30)

The project now has its own Git repository

Features
- Simple rotation for the Destruction Warlock (Cataclysm)
- Added WeakAuras group with a GCD indicator

Bug Fixes
- Ongoing casts captured success and fails of other units than player

#### v0.1 (2025-06-29)

Initial fork from the Mage NAG for Cataclysm
- The new project has been almost compltely rewritten
- While the old project worked very well, it was very hard to re-use it
- The main focus is now the ability to specify auras, cooldowns, etc. freely
- The class is now focused on the Destruction Warlock for Cataclysm
- Many of the old Mage code has been left commented for historic purposes
- Eventually, when the new code is stable, all old code shall be cleaned up
