The Next Action Guide is a WeakAuras project for World of Warcraft Classic that suggests the next action (spell or ability) to cast.
## Directory Structure
- `wa` - List of fully packaged WeakAuras exported strings
- `src` - Source code of Lua scripts used in the WeakAuras
## How to import a NAG
### Fire and forget
The most basic way to import a NAG WeakAuras is to go to the `wa` folder, select the appropriate NAG for the flavor / class / spec, then import it to the addon.
### NAG Group
A slightly more advanced way is to:
1. import `nag._group.wa` located in `wa`; it will create a group with the GCD indicator
2. set the position of this group to whichever location is best, for example above the `PlayerFrame`
3. select the appropriate class-specific NAG in `wa`, and import it as child of the group imported in step 1.

Step 3 can be repeated as many times as necessary to import NAGs for different classes or specializations.

With this group, not only there's no need to reposition the NAG every time a NAG is updated, but it also packs all NAGs nicely in a single, well-organized place.