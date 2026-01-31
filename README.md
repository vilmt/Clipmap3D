![Thumbnail](addons/Clipmap3D/plugin_thumbnail.jpg)

# Clipmap3D
A lightweight infinite procedural terrain system for Godot 4.5+

## Overview
* Written in GDScript, GDShader, and GLSL
* Supports Forward+ and Mobile renderers
* Use a compute shader to generate and texture terrain on the GPU
* No manual work to author terrain; everything is done through code
* Over 30x30km render distance with configurable vertex density and levels of detail (LODs)
* Real-time toroidal LOD shifting as the player moves
* Supports blending up to 32 albedo + normal textures

## Limitations
* This project is work-in-progress and is subject to major changes
* Physics interaction is currently limited to player collisions
* Image imports are not yet supported

## Trying the demos
* This repository contains a demo folder with two example scenes
	* High-spec demo
	* Low-spec demo
* After loading a scene, set View -> Settings... -> View Z-Far to 16000
* Zoom out tweak some parameters!

## Roadmap
* Texture projection
* Floating-point origin shifting
* Foliage instancing
* Cheap overlay normals in fragment for low-spec setups
* Heightmap image imports and streaming

TODO: fix collisions
TODO: default normal map should be neutral direction
