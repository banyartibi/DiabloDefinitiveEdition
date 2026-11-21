# AAA Cathedral Architectural Kit Specification

## 1. Mathematical Grid Invariants (Diablo 1 $\to$ Godot 4.7)

All modular pieces in the AAA Cathedral Kit must strictly adhere to the project's isometric coordinate system:

* **Tile Diagonal (Step Length):**
  $$L = \sqrt{0.75^2 + 0.75^2} \approx 1.06066017\text{ m}$$
* **Wall Height:**
  $$H = 2.40\text{ m} \quad (\text{matching 4 vertical rows of 32px at } \text{TILE\_SCALE} = 0.75)$$
* **Grid Orientation:**
  $$\text{Rotation } Y = -45^\circ \quad (\text{Local X runs along NS wall, Local Z runs along EW wall})$$
* **Wall Thickness:**
  $$T = 0.40\text{ m} \quad (\text{Total structural core with stone relief})$$
* **Base Pivot Origin:**
  $$\vec{P}_0 = (0.0, 0.0, 0.0) \quad \text{positioned exactly at the floor diamond center}$$

---

## 2. Modular Pieces Taxonomy

| Piece ID | Asset Name | Description | Dimensions ($W \times H \times D$) |
| :--- | :--- | :--- | :--- |
| **WALL_NS** | `wall_ns_gothic.glb` | North-South wall segment running along Local X | $1.06066\text{ m} \times 2.40\text{ m} \times 0.40\text{ m}$ |
| **WALL_EW** | `wall_ew_gothic.glb` | East-West wall segment running along Local Z | $0.40\text{ m} \times 2.40\text{ m} \times 1.06066\text{ m}$ |
| **WALL_CORNER** | `wall_corner_gothic.glb`| Outer & inner corner joining NS and EW walls | $1.06066\text{ m} \times 2.40\text{ m} \times 1.06066\text{ m}$ |
| **PILLAR** | `pillar_gothic.glb` | Octagonal freestanding pillar with base & capital | $0.52\text{ m} \times 2.40\text{ m} \times 0.52\text{ m}$ |
| **ARCH_DOOR** | `arch_door_gothic.glb` | Pointed Gothic archway with stone tracery | $1.06066\text{ m} \times 2.40\text{ m} \times 0.44\text{ m}$ |

---

## 3. PBR Texture & Shader Specifications

* **Albedo:** High-resolution dark gothic ashlar limestone, soot staining, blood spatters near base.
* **Normal Map:** Tangent-space OpenGL (+Y Up) baked from high-poly sculpt ($>100\text{k}$ poly source).
* **Roughness:** Dynamic distribution ($0.85$ weathered stone, $0.60$ worn edges, $0.45$ damp floor joints).
* **Ambient Occlusion:** Pre-baked deep occlusion for deep mortar crevices ($3\text{ cm}$ depth).
* **Light Leak Prevention:** All bottom and edge vertices feature $0.05\text{ m}$ subterranean skirt overlap to guarantee zero light bleeding under dynamic `OmniLight3D` PointLights.
