"""Generate the Chen-notation ER diagram (SVG) for Task 1 (revised)."""
import sys
from html import escape

W, H = 1700, 1230
FONT = 13
CW = 7.4                      # approx char width at 13px
ER, EH = 180, 56              # entity box
DW, DH = 78, 44               # diamond half sizes

out = []
lines = []                    # drawn first (under shapes)
shapes = []
labels = []


def line(x1, y1, x2, y2):
    lines.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="ln"/>')


def entity(name, cx, cy):
    shapes.append(f'<rect x="{cx-ER/2}" y="{cy-EH/2}" width="{ER}" height="{EH}" class="ent"/>'
                  f'<text x="{cx}" y="{cy+5}" class="et">{escape(name)}</text>')
    return (cx, cy)


def rel(name, cx, cy, derived=False):
    pts = f"{cx},{cy-DH} {cx+DW},{cy} {cx},{cy+DH} {cx-DW},{cy}"
    cls = "rel der" if derived else "rel"
    shapes.append(f'<polygon points="{pts}" class="{cls}"/>'
                  f'<text x="{cx}" y="{cy+5}" class="rt">{escape(name)}</text>')
    return (cx, cy)


def attr(name, cx, cy, owner, key=False):
    rx = max(38, len(name) * CW / 2 + 14)
    line(cx, cy, *owner)
    deco = ' text-decoration="underline"' if key else ""
    shapes.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="19" class="att"/>'
                  f'<text x="{cx}" y="{cy+4.5}" class="at"{deco}>{escape(name)}</text>')


def card(text, x, y, anchor="start"):
    labels.append(f'<text x="{x}" y="{y}" class="cd" text-anchor="{anchor}">{text}</text>')


# ---- entities and relationships -------------------------------------------
town = entity("Town", 170, 330)
bld = entity("HDBBuilding", 700, 330)
flat = entity("HDBFlat", 1330, 330)
tx = entity("ResaleTransaction", 1330, 800)
hc = entity("HawkerCentre", 700, 800)
lvl = entity("ProximityLevel", 150, 640)

contains = rel("Contains", 435, 330)
has = rel("HasProfile", 1015, 330)
records = rel("Records", 1330, 565)
prox = rel("Proximity", 700, 565)
cls = rel("ClassifiedAs", 390, 640, derived=True)

# relationship lines
line(*town, *contains); line(*contains, *bld)
line(*bld, *has); line(*has, *flat)
line(*flat, *records); line(*records, *tx)
line(*bld, *prox); line(*prox, *hc)
line(*lvl, *cls); line(cls[0] + DW, 640, 545, 640)       # to the aggregation border

# aggregation box (Proximity relationship treated as a higher-level entity)
AG = (545, 280, 905, 852)
agg = (f'<rect x="{AG[0]}" y="{AG[1]}" width="{AG[2]-AG[0]}" height="{AG[3]-AG[1]}" class="agg"/>'
       f'<text x="715" y="690" class="ag">aggregation of</text>'
       f'<text x="715" y="706" class="ag">HDBBuilding–Proximity–</text>'
       f'<text x="715" y="722" class="ag">HawkerCentre</text>')

# cardinalities: placed next to the entity end of each line
card("(0,*)", 268, 320)              # Town in Contains
card("(1,1)", 600, 320, "end")       # HDBBuilding in Contains
card("(0,*)", 798, 320)              # HDBBuilding in HasProfile
card("(1,1)", 1232, 320, "end")      # HDBFlat in HasProfile
card("(0,*)", 1340, 380)             # HDBFlat in Records
card("(1,1)", 1340, 764)             # ResaleTransaction in Records
card("(0,*)", 710, 380)              # HDBBuilding in Proximity
card("(0,*)", 710, 764)              # HawkerCentre in Proximity
card("(0,*)", 248, 630)              # ProximityLevel in ClassifiedAs
card("(1,1)", 538, 630, "end")       # aggregate (pair) in ClassifiedAs

# ---- attributes --------------------------------------------------------------
attr("town_id", 100, 200, town, key=True)
attr("town_name", 250, 200, town)

attr("block", 495, 215, bld)
attr("building_id", 585, 145, bld, key=True)
attr("street_name", 705, 100, bld)
attr("latitude?", 825, 150, bld)
attr("longitude?", 900, 250, bld)
attr("coordinate_source", 1000, 130, bld)

attr("distance_m", 840, 490, prox)

attr("flat_id", 1170, 205, flat, key=True)
attr("flat_type", 1250, 130, flat)
attr("flat_model", 1380, 80, flat)
attr("floor_area_sqm", 1525, 135, flat)
attr("storey_lower", 1590, 225, flat)
attr("storey_upper", 1600, 320, flat)
attr("lease_commence_year", 1560, 420, flat)

attr("transaction_id", 1195, 920, tx, key=True)
attr("transaction_month", 1360, 965, tx)
attr("resale_price", 1540, 900, tx)
attr("reported_remaining_lease_months?", 1520, 690, tx)

attr("hawker_id", 440, 790, hc, key=True)
attr("centre_name", 400, 880, hc)
attr("address?", 445, 970, hc)
attr("centre_type?", 565, 1040, hc)
attr("latitude?", 695, 1082, hc)
attr("longitude?", 830, 1060, hc)
attr("total_stalls?", 960, 1005, hc)
attr("cooked_food_stalls?", 1015, 930, hc)
attr("market_produce_stalls?", 1025, 852, hc)
attr("data_source", 975, 772, hc)

attr("level_id", 70, 525, lvl, key=True)
attr("label", 215, 515, lvl)
attr("min_dist_m", 75, 770, lvl)
attr("max_dist_m", 225, 790, lvl)

legend = """
<g transform="translate(30,1105)">
  <rect x="0" y="0" width="640" height="108" class="leg"/>
  <text x="12" y="20" class="lt"><tspan font-weight="bold">Notation (Chen)</tspan></text>
  <text x="12" y="40" class="lt">Rectangle = entity · Diamond = relationship · Oval = attribute · <tspan text-decoration="underline">underlined</tspan> = key</text>
  <text x="12" y="58" class="lt">? = may be NULL · (min,max) next to an entity = how often each of its instances takes part</text>
  <text x="12" y="76" class="lt">Dashed box = aggregation (the Proximity pair treated as one object)</text>
  <text x="12" y="94" class="lt">Dashed diamond = derived relationship: the level whose [min_dist_m, max_dist_m) contains distance_m</text>
</g>"""

style = f"""
<style>
  .ln  {{ stroke:#333; stroke-width:1.3; }}
  .ent {{ fill:#fff; stroke:#111; stroke-width:2; }}
  .rel {{ fill:#fff; stroke:#111; stroke-width:1.8; }}
  .der {{ stroke-dasharray:6 4; }}
  .att {{ fill:#fff; stroke:#444; stroke-width:1.2; }}
  .agg {{ fill:none; stroke:#555; stroke-width:1.5; stroke-dasharray:9 6; }}
  text {{ font-family:Helvetica, Arial, sans-serif; }}
  .et  {{ font-size:15px; font-weight:bold; text-anchor:middle; }}
  .rt  {{ font-size:{FONT}px; font-weight:bold; text-anchor:middle; }}
  .at  {{ font-size:{FONT}px; text-anchor:middle; }}
  .cd  {{ font-size:14px; font-weight:bold; fill:#b00020; }}
  .ag  {{ font-size:12px; fill:#555; font-style:italic; }}
  .leg {{ fill:#fafafa; stroke:#999; }}
  .lt  {{ font-size:12.5px; }}
  .tt  {{ font-size:22px; font-weight:bold; }}
</style>"""

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
       f'{style}<rect width="{W}" height="{H}" fill="#fff"/>'
       f'<text x="30" y="40" class="tt">Task 1: Conceptual ER model (revised)</text>'
       + "".join(lines) + agg + "".join(shapes) + "".join(labels) + legend + "</svg>")
open(sys.argv[1], "w").write(svg)
print("wrote", sys.argv[1])
