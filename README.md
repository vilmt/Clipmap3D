# Clipmap3D
An infinite procedural terrain system for Godot 4.5+

## Overview
* Written in GDScript, GLSL, and GDShader.
* Terrain is procedurally generated and textured in real time by a customizable compute shader
* Over 30x30km render distance with configurable levels of detail (LODs)
* Real-time toroidal LOD shifting as the player moves
* Supports blending up to 32 albedo + normal textures
* Supports concave collision with physics bodies

## WIP Disclaimer
This project is heavily work-in-progress and is subject to sweeping changes.
If you are interested in Clipmap3D, please try out the demo and report bugs.

## Roadmap (Priority order)
* Texture projection
* Foliage instancing
* Floating-point origin shifting
* Cheap overlay normals in fragment for low-spec setups

TODO: fix collisions, clean up double res, strip updating
after this, its done
Toroidal updating
