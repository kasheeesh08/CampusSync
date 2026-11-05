"""Builds CampusSync seed data from the reference documents.

Every record below was transcribed by hand from the files in `important doc/`
and `floor wise college layout/`. Values that are ambiguous in the source carry a
`reviewFlags` entry instead of a guess. Run:

    python -I tools/build_seed.py

Output: app/assets/seed/*.json (consumed by the app, the admin dashboard and
firebase/seed_firestore.js).
"""
import datetime
import json
import pathlib
import re
import sys

# Works under `python -I` (isolated mode drops the script directory from sys.path).
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import exam_source as ES  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "assets" / "seed"
SCHEMA_VERSION = 1

SRC_DIV_B = "important doc/Timetable B. Tech Computer Sem. V DIv. B 2026-27 w.e.f 13.7.2026.pdf"
SRC_DIV_C = "important doc/Timetable B. Tech Computer Sem. V DIv. C 2026-27 w.e.f 13.7.2026.pdf"
SRC_OE = "important doc/OE 1  OE2 Timetable   B.Tech MBA.Tech BTI MCA.pdf"
SRC_CAL = "important doc/Academic Calendar - All Programs_Second Year to Six Year_AY 2026-27.pdf"
SRC_FLOORS = "floor wise college layout/"
SRC_EXAMS = "final exam timetable/MPSTME_ODD_Semester_Final_Exam_Time_Table_2026_2027_4ycvxuhivW.pdf"
# Source screenshot for each floor (provenance).
FLOOR_IMAGES = {
    "LG": "WhatsApp Image 2026-10-20 at 5.12.07 PM.jpeg",
    "G": "WhatsApp Image 2026-10-20 at 5.12.06 PM.jpeg",
    "1": "WhatsApp Image 2026-10-20 at 5.12.09 PM (2).jpeg",
    "2": "WhatsApp Image 2026-10-20 at 7.05.13 PM.jpeg",
    "3": "WhatsApp Image 2026-10-20 at 5.12.09 PM (1).jpeg",
    "4": "WhatsApp Image 2026-10-20 at 5.12.09 PM.jpeg",
    "5": "WhatsApp Image 2026-10-20 at 5.12.08 PM (2).jpeg",
    "6": "WhatsApp Image 2026-10-20 at 5.12.08 PM (1).jpeg",
    "7": "WhatsApp Image 2026-10-20 at 5.12.08 PM.jpeg",
    "8": "WhatsApp Image 2026-10-20 at 5.12.07 PM (1).jpeg",
}

INSTITUTION_ID = "nmims-mpstme-mumbai"
DEPT_ID = "dept-computer-engg"
PROGRAM_ID = "prog-btech-computer"
YEAR_ID = "ay-2026-27"
GROUP_B = "btech-computer-2026-27-sem5-div-b"
GROUP_C = "btech-computer-2026-27-sem5-div-c"
GROUP_OE1 = "oe1-2026-27-odd"
GROUP_OE2 = "oe2-2026-27-odd"


def room_id(code: str) -> str:
    """'E. CR 402' / 'CR-402' / 'Cr. 402' -> 'CR-402'."""
    c = code.strip().upper().replace("E.", "").replace(".", " ").strip()
    c = re.sub(r"\s+", " ", c)
    m = re.fullmatch(r"(CR|CL|CC|TR) ?-? ?(LG ?\d+|G\d+|\d+)", c)
    if m:
        return f"{m.group(1)}-{m.group(2).replace(' ', '')}"
    return "LAB-" + re.sub(r"[^A-Z0-9]+", "-", c).strip("-")


# ---------------------------------------------------------------- floors ----
# Pixel rectangles (x1, y1, x2, y2) measured on the 738x1600 screenshots. The
# drawing frame spans x 60..678, y 370..1290 on every image; coordinates are
# normalised to that frame so the app can scale them to any screen.
FX0, FY0, FW, FH = 60, 370, 618, 920
TOP = (382, 498)
BOTTOM = (1160, 1277)
LIFT_TOP = (266, 572, 472, 608)
LIFT_BOTTOM = (266, 1042, 472, 1078)
CORE = (266, 750, 472, 906)
IN_TL, IN_TR = (266, 621, 362, 738), (375, 621, 471, 738)
IN_BL, IN_BR = (266, 918, 362, 1030), (375, 918, 471, 1030)

# kind: classroom | lab | tutorial | facility | office | washroom | exit | lift | stairs | core | utility
F = {}


def r(label, rect, kind, code=None):
    return {"label": label, "rect": rect, "kind": kind, "code": code}


def std_top(n):
    return [
        r(f"Faculty Area {n}02", (70, *TOP[:1], 275, TOP[1]), "office"),
        r("Washroom", (287, TOP[0], 363, TOP[1]), "washroom"),
        r("Emergency exit", (375, TOP[0], 451, TOP[1]), "exit"),
        r(f"Faculty Area {n}01", (463, TOP[0], 668, TOP[1]), "office"),
    ]


def lifts():
    return [r("Lift (Bhagubhai entrance)", LIFT_TOP, "lift"), r("Lift (Cooper entrance)", LIFT_BOTTOM, "lift")]


def cr(label, rect):
    kind = "classroom"
    if label.startswith("CL") or label.startswith("CC"):
        kind = "lab"
    elif label.startswith("TR"):
        kind = "tutorial"
    return r(label, rect, kind, room_id(label))


F["LG"] = {
    "name": "Lower Ground", "order": 0,
    "note": "Canteen level with some classes.",
    "regions": [
        r("Fire fighting output at ceiling level", (70, 382, 551, 498), "utility"),
        r("Fire fighting output at ceiling level", (551, 382, 668, 772), "utility"),
        r("AHU", (70, 508, 186, 588), "utility"),
        r("Mini Auditorium", (70, 601, 186, 888), "facility", "LAB-MINI-AUDITORIUM"),
        cr("CR LG1", (70, 901, 186, 1023)),
        r("Washroom", (70, 1036, 186, 1106), "washroom"),
        r("Emergency exit", (70, 1119, 186, 1148), "exit"),
        *lifts(),
        r("Cafeteria", (266, 620, 472, 906), "facility", "LAB-CAFETERIA"),
        r("Cafeteria (AC)", (266, 918, 394, 1030), "facility", "LAB-CAFETERIA-AC"),
        r("Faculty Dining", (406, 918, 472, 1030), "facility"),
        r("Pantry", (551, 786, 668, 911), "facility"),
        r("Emergency exit", (551, 925, 668, 952), "exit"),
        r("Washroom", (551, 965, 668, 1018), "washroom"),
        r("Emergency exit", (551, 1031, 668, 1058), "exit"),
        r("Services", (70, 1160, 199, 1277), "utility"),
        r("Emergency exit", (211, 1160, 241, 1277), "exit"),
        r("Electrical Panel Room", (253, 1160, 425, 1277), "utility"),
        r("Emergency exit", (437, 1160, 467, 1277), "exit"),
        r("Washroom", (478, 1160, 525, 1277), "washroom"),
        r("Maintenance Room", (537, 1160, 668, 1277), "utility"),
    ],
}
F["G"] = {
    "name": "Ground", "order": 1,
    "note": "Administrative areas and examination classrooms.",
    "regions": [
        r("AMU Room 1", (70, 382, 186, 498), "office"),
        r("Emergency exit", (335, 382, 411, 498), "exit"),
        r("Exam 2", (423, 382, 539, 498), "facility", "LAB-EXAM-2"),
        r("Exam 3", (551, 382, 667, 498), "facility", "LAB-EXAM-3"),
        *lifts(),
        cr("CR G4", IN_TL), cr("CR G5", IN_TR),
        cr("CR G3", (549, 575, 666, 743)),
        r("Exam 1", (70, 698, 187, 778), "facility", "LAB-EXAM-1"),
        cr("CR G2", (70, 791, 187, 871)),
        cr("CR G1", (70, 884, 187, 964)),
        r("Washroom", (70, 977, 187, 1036), "washroom"),
        r("Emergency exit", (70, 1048, 187, 1077), "exit"),
        r("Admin Department", IN_BL, "office"),
        r("Conference Room", IN_BR, "office"),
        r("Emergency exit", (551, 818, 668, 848), "exit"),
        r("Staircase", (551, 981, 668, 1039), "stairs"),
        r("Staircase to Lower Ground", (551, 1093, 668, 1151), "stairs"),
        r("Server Room", (70, 1160, 185, 1277), "utility"),
        r("IBMS Room", (197, 1160, 313, 1277), "utility"),
    ],
}
F["1"] = {
    "name": "Floor 1", "order": 2, "note": None,
    "regions": [
        *std_top(1), *lifts(),
        cr("CR 103", (70, 575, 187, 655)), cr("CR 102", (70, 668, 187, 748)), cr("CR 101", (70, 762, 187, 842)),
        r("Washroom", (70, 855, 187, 913), "washroom"),
        cr("CL 102", (70, 926, 187, 975)), cr("CL 101", (70, 988, 187, 1037)),
        r("Emergency exit", (70, 1050, 187, 1079), "exit"),
        cr("CR 107", IN_TL), cr("CR 108", IN_TR), cr("CR 106", IN_BL), cr("CR 105", IN_BR),
        cr("CR 104", (551, 573, 668, 791)),
        r("Emergency exit", (551, 805, 668, 833), "exit"),
        r("NA (unlabelled in source)", (551, 846, 668, 1037), "utility"),
        r("Emergency exit", (551, 1050, 668, 1079), "exit"),
        r("Hardware Lab 3", (70, 1160, 185, 1277), "lab", "LAB-HARDWARE-LAB-3"),
        r("Hardware Lab 2", (197, 1160, 313, 1277), "lab", "LAB-HARDWARE-LAB-2"),
        r("Hardware Lab 1", (423, 1160, 539, 1277), "lab", "LAB-HARDWARE-LAB-1"),
        r("Dean Office", (551, 1160, 667, 1277), "office"),
    ],
}
F["2"] = {
    "name": "Floor 2", "order": 3, "note": None,
    "regions": [
        *std_top(2), *lifts(),
        cr("TR 203", (70, 575, 187, 697)), cr("TR 202", (70, 709, 187, 831)), cr("TR 201", (70, 844, 187, 966)),
        r("Washroom", (70, 979, 187, 1037), "washroom"),
        r("Emergency exit", (70, 1050, 187, 1079), "exit"),
        cr("CR 208", IN_TL), cr("CR 209", IN_TR), cr("CR 207", IN_BL), cr("CR 206", IN_BR),
        cr("CR 203", (551, 573, 668, 791)),
        r("Emergency exit", (551, 803, 668, 832), "exit"),
        cr("CR 204", (551, 844, 668, 1033)),
        r("Emergency exit", (551, 1046, 668, 1076), "exit"),
        cr("CR 202", (70, 1160, 185, 1277)), cr("CR 201", (197, 1160, 313, 1277)),
        cr("CC 201", (423, 1160, 539, 1277)),
        r("Physics Lab", (551, 1160, 667, 1277), "lab", "LAB-PHYSICS-LAB"),
    ],
}
F["3"] = {
    "name": "Floor 3", "order": 4, "note": None,
    "regions": [
        *std_top(3), *lifts(),
        cr("CR 303", (70, 585, 187, 665)), cr("TR 302", (70, 678, 187, 759)), cr("TR 301", (70, 772, 187, 852)),
        r("Girls Common Room", (70, 865, 187, 966), "facility"),
        r("Washroom", (70, 979, 187, 1037), "washroom"),
        r("Emergency exit", (70, 1050, 187, 1079), "exit"),
        cr("CR 309", IN_TL), cr("CR 310", IN_TR), cr("CR 308", IN_BL), cr("CR 307", IN_BR),
        cr("CR 304", (551, 577, 668, 726)),
        r("Emergency exit", (551, 739, 668, 767), "exit"),
        cr("CR 305", (551, 780, 668, 902)), cr("CR 306", (551, 915, 668, 1037)),
        r("Emergency exit", (551, 1050, 668, 1079), "exit"),
        cr("CR 302", (70, 1160, 185, 1277)), cr("CR 301", (197, 1160, 313, 1277)),
        cr("CC 301", (423, 1160, 539, 1277)), cr("TR 303", (551, 1160, 667, 1277)),
    ],
}
F["4"] = {
    "name": "Floor 4", "order": 5, "note": "Main Computer Engineering department floor.",
    "regions": [
        *std_top(4), *lifts(),
        cr("CL 406", (70, 573, 187, 628)), cr("CL 405", (70, 641, 187, 695)), cr("CL 404", (70, 708, 187, 762)),
        cr("CL 403", (70, 775, 187, 830)), cr("CL 402", (70, 843, 187, 897)), cr("CL 401", (70, 910, 187, 965)),
        r("Washroom", (70, 977, 187, 1037), "washroom"),
        r("Emergency exit", (70, 1050, 187, 1079), "exit"),
        cr("CR 407", IN_TL), cr("CR 408", IN_TR), cr("CR 406", IN_BL), cr("CR 405", IN_BR),
        r("ES Lab", (551, 573, 668, 655), "lab", "LAB-ES-LAB"),
        r("DE Lab", (551, 668, 668, 750), "lab", "LAB-DE-LAB"),
        r("Emergency exit", (551, 763, 668, 792), "exit"),
        cr("CR 403", (551, 806, 668, 914)), cr("CR 404", (551, 927, 668, 1035)),
        r("Emergency exit", (551, 1050, 668, 1079), "exit"),
        cr("CR 402", (70, 1160, 185, 1277)), cr("CR 401", (197, 1160, 313, 1277)),
        cr("CL 408", (430, 1160, 501, 1277)), cr("CL 407", (513, 1160, 584, 1277)), cr("TR 401", (596, 1160, 667, 1277)),
    ],
}
F["5"] = {
    "name": "Floor 5", "order": 6, "note": None,
    "regions": [
        *std_top(5), *lifts(),
        cr("CR 503", (70, 578, 187, 678)), cr("CL 501", (70, 693, 187, 762)), cr("TR 501", (70, 778, 187, 847)),
        r("Boys Common Room", (70, 862, 187, 956), "facility"),
        r("Washroom", (70, 971, 187, 1030), "washroom"),
        r("Emergency exit", (70, 1046, 187, 1077), "exit"),
        cr("CR 508", IN_TL), cr("CR 509", IN_TR), cr("CR 507", IN_BL), cr("CR 506", IN_BR),
        cr("CL 502", (551, 571, 668, 654)), cr("CL 503", (551, 666, 668, 748)),
        r("Emergency exit", (551, 761, 668, 791), "exit"),
        cr("CR 504", (551, 804, 668, 912)), cr("CR 505", (551, 925, 668, 1033)),
        r("Emergency exit", (551, 1048, 668, 1076), "exit"),
        cr("CR 502", (70, 1160, 185, 1277)), cr("CR 501", (197, 1160, 313, 1277)),
        cr("CL 506", (430, 1160, 501, 1277)), cr("CL 505", (513, 1160, 584, 1277)), cr("CL 504", (596, 1160, 667, 1277)),
    ],
}
F["6"] = {
    "name": "Floor 6", "order": 7, "note": None,
    "regions": [
        *std_top(6), *lifts(),
        cr("CR 604", (71, 577, 189, 675)), cr("CL 601", (71, 690, 189, 759)), cr("TR 601", (71, 775, 189, 844)),
        cr("CR 603", (71, 860, 189, 952)),
        r("Washroom", (71, 968, 189, 1027), "washroom"),
        r("Emergency exit", (71, 1042, 189, 1074), "exit"),
        cr("CR 608", IN_TL), cr("CR 609", IN_TR), cr("CR 607", IN_BL), cr("CR 606", IN_BR),
        r("Advance Communication Lab", (551, 567, 668, 645), "lab", "LAB-ADVANCE-COMMUNICATION-LAB"),
        r("Basic Communication Lab", (551, 657, 668, 735), "lab", "LAB-BASIC-COMMUNICATION-LAB"),
        r("Emergency exit", (551, 747, 668, 778), "exit"),
        cr("CL 602", (551, 791, 668, 859)), cr("CL 603", (551, 872, 668, 940)), cr("CR 605", (551, 953, 668, 1035)),
        r("Emergency exit", (551, 1048, 668, 1079), "exit"),
        cr("CR 602", (70, 1160, 185, 1277)), cr("CR 601", (197, 1160, 313, 1277)),
        r("AI Lab", (423, 1160, 539, 1277), "lab", "LAB-AI-LAB"),
        r("Robotics Lab", (551, 1160, 667, 1277), "lab", "LAB-ROBOTICS-LAB"),
    ],
}
F["7"] = {
    "name": "Floor 7", "order": 8, "note": None,
    "regions": [
        r("Library", (75, 383, 192, 962), "facility", "LAB-LIBRARY"),
        r("Washroom", (75, 975, 192, 1034), "washroom"),
        r("Emergency exit", (75, 1046, 192, 1075), "exit"),
        r("Washroom", (209, 383, 310, 500), "washroom"),
        r("Emergency exit", (323, 383, 424, 500), "exit"),
        r("Faculty Area 701", (461, 383, 667, 500), "office"),
        *lifts(),
        cr("CL 706", IN_TL), cr("CC 702", IN_TR), cr("CR 704", IN_BL), cr("CR 703", IN_BR),
        cr("CR 702", (551, 574, 668, 691)),
        r("Emergency exit", (551, 704, 668, 732), "exit"),
        cr("CL 701", (551, 745, 668, 810)), cr("CL 702", (551, 822, 668, 884)),
        cr("CL 703", (551, 897, 668, 960)), cr("CL 704", (551, 972, 668, 1036)),
        r("Emergency exit", (551, 1048, 668, 1078), "exit"),
        cr("CC 701", (70, 1160, 185, 1277)), cr("CR 701", (197, 1160, 313, 1277)),
        r("AR/VR Lab", (423, 1160, 539, 1277), "lab", "LAB-AR-VR-LAB"),
        cr("CL 705", (551, 1160, 667, 1277)),
    ],
}
F["8"] = {
    "name": "Floor 8", "order": 9, "note": None,
    "regions": [
        r("Faculty Area 802", (70, 382, 249, 498), "office"),
        r("Washroom", (261, 382, 313, 498), "washroom"),
        r("Emergency exit", (325, 382, 377, 498), "exit"),
        r("Additive Manufacturing Lab", (389, 382, 482, 498), "lab", "LAB-ADDITIVE-MANUFACTURING-LAB"),
        r("Faculty Area 801", (494, 382, 668, 498), "office"),
        *lifts(),
        r("Sensor IOT Lab", (70, 581, 187, 648), "lab", "LAB-SENSOR-IOT-LAB"),
        r("Pneumatic Lab", (70, 661, 187, 729), "lab", "LAB-PNEUMATIC-LAB"),
        r("Automation Lab", (70, 742, 187, 812), "lab", "LAB-AUTOMATION-LAB"),
        cr("CL 801", (70, 826, 187, 893)),
        r("Hydraulics Lab", (70, 906, 187, 971), "lab", "LAB-HYDRAULICS-LAB"),
        r("Washroom", (70, 984, 187, 1043), "washroom"),
        r("Emergency exit", (70, 1055, 187, 1084), "exit"),
        r("V.C. Room 1", IN_TL, "office"), r("V.C. Room 2", IN_TR, "office"),
        cr("CC 803", IN_BL), cr("CC 802", IN_BR),
        cr("CC 801", (551, 573, 668, 706)),
        r("Emergency exit", (551, 718, 668, 748), "exit"),
        cr("CL 802", (551, 761, 668, 826)), cr("CL 803", (551, 839, 668, 901)),
        r("NA (unlabelled in source)", (551, 913, 668, 1035), "utility"),
        r("Emergency exit", (551, 1048, 668, 1078), "exit"),
        r("Placement Office 1 and 2", (70, 1160, 261, 1277), "office"),
        r("Placement Office 3", (290, 1180, 422, 1260), "office"),
        cr("CL 804", (423, 1160, 539, 1277)), cr("CR 801", (551, 1160, 667, 1277)),
    ],
}

ROOM_KINDS = {"classroom", "lab", "tutorial", "facility"}


def build_floors_and_rooms():
    floors, rooms = [], {}
    for fid, f in F.items():
        regs = []
        for i, reg in enumerate(f["regions"]):
            x1, y1, x2, y2 = reg["rect"]
            regs.append({
                "id": f"{fid}-{i}",
                "label": reg["label"],
                "kind": reg["kind"],
                "roomId": reg["code"],
                "x": round((x1 - FX0) / FW, 4), "y": round((y1 - FY0) / FH, 4),
                "w": round((x2 - x1) / FW, 4), "h": round((y2 - y1) / FH, 4),
            })
            if reg["code"]:
                if reg["code"] in rooms:
                    raise SystemExit(f"Duplicate room id {reg['code']} on floor {fid}")
                rooms[reg["code"]] = {
                    "id": reg["code"],
                    "code": reg["code"].replace("LAB-", "") if not reg["code"].startswith("LAB-") else reg["label"],
                    "name": reg["label"] if reg["code"].startswith("LAB-") else reg["code"].replace("-", " "),
                    "type": reg["kind"],
                    "floorId": fid,
                    "capacity": None,
                    "active": True,
                    "bookable": reg["kind"] in {"classroom", "lab", "tutorial"},
                    "aliases": [],
                    "source": SRC_FLOORS + FLOOR_IMAGES[fid],
                }
        floors.append({
            "id": fid, "name": f["name"], "order": f["order"], "note": f["note"],
            "aspectRatio": round(FW / FH, 4), "regions": regs, "source": SRC_FLOORS + FLOOR_IMAGES[fid],
        })
    floors.sort(key=lambda x: x["order"])
    # Timetable spellings that differ from the floor plan labels.
    rooms["LAB-BASIC-COMMUNICATION-LAB"]["aliases"] = ["BC Lab", "CL-BCL"]
    rooms["LAB-DE-LAB"]["aliases"] = ["Digital Electronics lab"]
    rooms["LAB-AR-VR-LAB"]["aliases"] = ["ARVR LAb"]
    return floors, rooms


# ---------------------------------------------------------------- people ----
FACULTY = [
    ("fac-prashasti-kanikar", "Dr. Prashasti Kanikar", ["PRK"]),
    ("fac-archana-nanade", "Dr. Archana Nanade", ["ANA"]),
    ("fac-hiral-modi", "Prof. Hiral Modi", ["HMO"]),
    ("fac-supriya-agarwal", "Dr. Supriya Agarwal", ["SAG"]),
    ("fac-aishwarinandini-bishnu", "Prof. Aishwarinandini Bishnu", ["VAR", "VAN"]),
    ("fac-govind-wakure", "Prof. Govind Wakure", ["VGW"]),
    ("fac-shabnam-ansari", "Prof. Shabnam Ansari", ["SAN"]),
    ("fac-ravita-mishra", "Dr. Ravita Mishra", ["RMI"]),
    ("fac-avani-bhuva", "Prof. Avani Bhuva", ["AVB"]),
    ("fac-ishani-saha", "Prof. Ishani Saha", ["ISA"]),
]
INITIAL = {i: fid for fid, _, inits in FACULTY for i in inits}

SUBJECTS = [
    ("SE", "Software Engineering"), ("AI", "Artificial Intelligence"),
    ("IVP", "Image and Video Processing"), ("OS", "Operating Systems"),
    ("MAD", "Mobile Application Development"), ("OR", "Operations Research"),
    ("OE-1", "Open Elective I"), ("OE-2", "Open Elective II"),
]

# --------------------------------------------------------------- timetable --
DAYS = {"Mon": 1, "Tue": 2, "Wed": 3, "Thu": 4, "Fri": 5}


def e(day, start, end, kind, subj=None, fac=None, room=None, batch=None, shared=None, flags=None):
    return dict(day=day, start=start, end=end, kind=kind, subj=subj, fac=fac, room=room,
                batch=batch, shared=shared, flags=flags or [])


L, P, BRK, LIB, OE = "lecture", "lab", "break", "library", "elective"
SHARED_MAD = "Combined lab B2+C2 (listed on both division timetables)"
SHARED_OR = "Combined lab B1+C1 (listed on both division timetables)"

DIV_B = [
    e("Mon", "08:00", "10:00", P, "SE", "PRK", "CL 401", "B1"),
    e("Mon", "08:00", "10:00", P, "IVP", "SAG", "CL 503", "B2"),
    e("Mon", "10:00", "11:00", L, "SE", "PRK", "CR 402"),
    e("Mon", "11:00", "12:00", L, "IVP", "SAG", "CR 402"),
    e("Mon", "12:00", "13:00", BRK), e("Mon", "13:00", "14:00", LIB),
    e("Mon", "14:00", "15:00", L, "AI", "ANA", "CR 402"),
    e("Mon", "15:00", "16:00", L, "OR", "VGW", "CR 402"),
    e("Mon", "16:00", "18:00", OE, "OE-1"),
    e("Tue", "08:00", "10:00", P, "SE", "PRK", "CL 503", "B2"),
    e("Tue", "08:00", "10:00", P, "IVP", "SAG", "BC Lab", "B1"),
    e("Tue", "10:00", "12:00", P, "AI", "ANA", "CL 503", "B1"),
    e("Tue", "10:00", "12:00", P, "OS", "HMO", "BC Lab", "B2"),
    e("Tue", "12:00", "13:00", BRK), e("Tue", "13:00", "14:00", LIB),
    e("Tue", "14:00", "15:00", L, "OS", "HMO", "CR 402"),
    e("Tue", "15:00", "16:00", BRK),
    e("Tue", "16:00", "18:00", OE, "OE-1"),
    e("Wed", "08:00", "10:00", P, "MAD", "VAR", "CC 702", "B1",
      flags=["Only batch B1 is listed for this slot; no B2 entry appears in the source."]),
    e("Wed", "10:00", "12:00", P, "MAD", "VAR", "CL 503", "B2", shared=SHARED_MAD),
    e("Wed", "10:00", "12:00", P, "OR", "SAN", "CL 401", "B1", shared=SHARED_OR),
    e("Wed", "12:00", "13:00", BRK),
    e("Wed", "13:00", "14:00", L, "SE", "PRK", "CR 402"),
    e("Wed", "14:00", "15:00", L, "OS", "HMO", "CR 402"),
    e("Wed", "15:00", "16:00", BRK),
    e("Wed", "16:00", "18:00", OE, "OE-1"),
    e("Thu", "12:00", "13:00", L, "OR", "VGW", "CR 405"),
    e("Thu", "13:00", "14:00", L, "IVP", "SAG", "CR 402"),
    e("Thu", "14:00", "15:00", BRK),
    e("Thu", "15:00", "16:00", L, "AI", "ANA", "CR 401"),
    e("Thu", "16:00", "18:00", OE, "OE-2"),
    e("Fri", "10:00", "11:00", L, "MAD", "VAR", "CR 404"),
    e("Fri", "11:00", "12:00", L, "MAD", "VAR", "CR 406"),
    e("Fri", "12:00", "14:00", P, "OS", "HMO", "CL 503", "B1"),
    e("Fri", "12:00", "14:00", P, "AI", "ANA", "CL 802", "B2"),
    e("Fri", "14:00", "15:00", LIB), e("Fri", "15:00", "16:00", BRK),
    e("Fri", "16:00", "18:00", OE, "OE-2"),
]

DIV_C = [
    e("Mon", "08:00", "09:00", L, "MAD", "VAN", "CR 407"),
    e("Mon", "09:00", "10:00", L, "MAD", "VAN", "CR 401"),
    e("Mon", "10:00", "12:00", P, "MAD", "VAN", "CL 503", "C1"),
    e("Mon", "12:00", "13:00", L, "OS", "ISA", "CR 401"),
    e("Mon", "13:00", "14:00", BRK),
    e("Mon", "14:00", "15:00", L, "AI", "RMI", "CR 609",
      flags=["Room printed as CR-609 (6th floor) while other Div C lectures are on the 4th floor; confirm."]),
    e("Mon", "15:00", "16:00", L, "OR", "VGW", "CR 402"),
    e("Mon", "16:00", "18:00", OE, "OE-1"),
    e("Tue", "10:00", "11:00", L, "SE", "PRK", "CR 401"),
    e("Tue", "11:00", "12:00", L, "IVP", "AVB", "CR 401"),
    e("Tue", "12:00", "13:00", L, "AI", "RMI", "CR 401"),
    e("Tue", "13:00", "14:00", BRK),
    e("Tue", "14:00", "16:00", P, "OS", "ISA", "CL 401", "C1"),
    e("Tue", "16:00", "18:00", OE, "OE-1"),
    e("Wed", "08:00", "10:00", P, "AI", "RMI", "CL 503", "C2"),
    e("Wed", "10:00", "12:00", P, "MAD", "VAN", "CL 503", "C2", shared=SHARED_MAD),
    e("Wed", "10:00", "12:00", P, "OR", "SAN", "CL 401", "C1", shared=SHARED_OR),
    e("Wed", "12:00", "13:00", LIB), e("Wed", "13:00", "14:00", BRK),
    e("Wed", "14:00", "16:00", P, "SE", "PRK", "CL 401", "C1"),
    e("Wed", "14:00", "16:00", P, "OS", "ISA", "CC 803", "C2"),
    e("Wed", "16:00", "18:00", OE, "OE-1"),
    e("Thu", "10:00", "11:00", L, "IVP", "AVB", "CR 401"),
    e("Thu", "11:00", "12:00", L, "OS", "ISA", "CR 401"),
    e("Thu", "12:00", "13:00", L, "OR", "VGW", "CR 405"),
    e("Thu", "13:00", "14:00", BRK),
    e("Thu", "14:00", "16:00", P, "IVP", "AVB", "CL 503", "C1"),
    e("Thu", "16:00", "18:00", OE, "OE-2"),
    e("Fri", "10:00", "12:00", P, "AI", "RMI", "CL 401", "C1"),
    e("Fri", "10:00", "12:00", P, "IVP", "AVB", "CL-BCL", "C2"),
    e("Fri", "12:00", "13:00", BRK),
    e("Fri", "13:00", "14:00", L, "SE", "PRK", "CR 401"),
    e("Fri", "14:00", "16:00", P, "SE", "PRK", "CL 704", "C2"),
    e("Fri", "16:00", "18:00", OE, "OE-2"),
]

# OE offerings: (code, name, dept, rooms, labRoom, faculty, sessions, flags)
# sessions: list of (day, start, end, kind)
TH_MON = ("Mon", "16:00", "18:00", L)
TH_TUE1 = ("Tue", "16:00", "17:00", L)
LAB_TUE = ("Tue", "16:00", "18:00", P)
LAB_WED = ("Wed", "16:00", "18:00", P)
OE2_THU = ("Thu", "16:00", "18:00", L)
OE2_FRI = ("Fri", "16:00", "17:00", L)
TH_ONLY = [TH_MON, TH_TUE1]
WITH_LAB = [TH_MON, LAB_TUE, LAB_WED]
OE2 = [OE2_THU, OE2_FRI]

OE1_LIST = [
    ("Drone Technology", "EXTC", ["CR 504"], "Advance Communication Lab", "Prof. Pavankumar Borra", WITH_LAB, []),
    ("5G for Everyone", "EXTC", ["TR 501"], "Basic Communication Lab", "Dr. Sonal Parmar", WITH_LAB, []),
    ("Wireless Communications for Everybody", "EXTC", ["TR 601"], "DE Lab", "Dr. Archana Bomnale", WITH_LAB,
     ["Lab listed as 'Digital Electronics lab'; mapped to DE Lab on Floor 4."]),
    ("Fundamentals of Climate Change", "Civil", ["CR 602"], None, "Prof. Apurva Mehta", TH_ONLY, []),
    ("Disaster Management", "Civil", ["CR 603"], None, "Prof. Deoyani Joshi", TH_ONLY, []),
    ("Interior Design", "Civil", ["CR 506"], None, "Dr. Manoj Anakokar", TH_ONLY, []),
    ("Research Methodology", "Civil", ["CR 503"], None, "Dr. Meenal Mategaonkar", TH_ONLY, []),
    ("Introduction to GIS", "Civil", ["CR 404"], "CL 803", "Dr. Sunayana Sarkar", TH_ONLY,
     ["Lab CL-803 is listed although the module has 0 practical hours; lab schedule not stated."]),
    ("Smart Cities", "Civil", ["CR 501"], None, "Prof. Darshana Lade", TH_ONLY,
     ["Source also lists 'Tue(5-6) & Wed (2-6)'; meaning unclear, not scheduled."]),
    ("Renewable Energy Sources", "Mechanical", ["CR 508", "CR 509"], None, "Abhishek Priyam, Nilesh Balki", TH_ONLY, []),
    ("3D Printing", "Mechanical", ["CR 604"], None, "Dr. Samadhan Deshmukh", [TH_MON],
     ["Lab '3D Printing Lab, 8th floor' does not appear on the Floor 8 plan; lab sessions not mapped to a room."]),
    ("Industrial Ergonomics", "Mechanical", ["CR 507"], None, "Dr. Ravi Terkar", TH_ONLY, []),
    ("Engineering Materials for Daily Life", "Mechanical", ["CR 502"], None, "Dr. Adam Khan", TH_ONLY, []),
    ("Electric Vehicle Technology", "Mechanical", ["CR 407"], None, "Dr. Rojo Kurian Daniel", TH_ONLY, []),
    ("Elements of Automation", "MXTC", ["CR 702"], None, "Prof. Nirmal Thakur", [TH_MON],
     ["Lab listed as 'IOT and Sensorics, Hydraulics, Pneumatics and Robotics' (several rooms); lab sessions not mapped."]),
    ("Supervisory Control and Data Acquisition", "MXTC", ["CC 801"], "CL 801", "Dr. Dattatray Sawant", WITH_LAB, []),
    ("Introduction to Virtual Reality and Augmented Reality", "MXTC", ["CC 702"], "AR/VR Lab", "Dr. Sunny Nanade", WITH_LAB, []),
    ("Data Analytics", "DS", [], None, None, [],
     ["Row has credits only (2-2-0-3); room, faculty and timing are blank in the source."]),
    ("Basic Decision Making with Spreadsheet", "DS", ["CC 803"], "CL 706", "Rushabh Sir (VF)", WITH_LAB,
     ["Faculty given only as 'RUSHABH SIR'."]),
    ("Game Design", "IT", ["CR 605"], None, "Pratidnya Hedge Partil", TH_ONLY, ["Source spells the module 'Game Desing'."]),
    ("Sustainable Energy Technologies", "BSH", ["CR 606"], None, "Dr. Abhinaba Gupta", TH_ONLY, []),
]
OE2_LIST = [
    ("Modelling and Simulation", "BSH", ["CR 401"], None, "Dr. Mahesh Naik", OE2, []),
    ("Introduction to Forensic Science", "BSH", ["CR 605", "CR 606"], None, "Dr. Sanket Gudekar, Dr. Ketakee Durve", OE2, []),
    ("Quantum Computing and Technologies", "BSH", ["TR 601"], None, "Dr. Sreemoyee Sarkar", OE2, []),
    ("Environment Management", "BSH", ["TR 401"], None, "Dr. Chandan Maitrani", OE2, []),
    ("Life Skills", "BSH", ["CR 602"], None, "Dr. Priyal Panchal", OE2, []),
    ("Creativity and Ethics in Marketing", "TM", ["CR 608", "CR 609"], None, "Prof. Saloni Rajawat / Prof. Shobha Mathew", OE2, []),
    ("Leading through Life Skills", "TM", ["CR 701", "CR 702"], None, "Prof. Neerja Kalluri, Dr. Shyamlee D Solanki", OE2, []),
    ("Technology and Innovation for Marketing", "TM", ["CR 607"], None, "Prof. Sandeep Mallya", OE2, []),
    ("Financial Derivatives", "TM", ["CR 407", "CR 408"], None, "Prof Sampat K, Prof CA Shiv Pathak", OE2, []),
    ("Financial Institutions, Markets, Instruments and Services", "TM", ["CR 503", "CR 504"], None, "Prof Vishwanath Acharya, Prof CA Jasmin bid", OE2, []),
    ("Management Through Movies", "TM", ["CR 604", "CR 703"], None, "Dr. Dasika, Prof. Anand Desai", OE2, []),
    ("Advertising and Public Relations", "Civil", ["CR 506"], None, "Dr. Manoj Anakokar", OE2, []),
    ("Waste Management", "Civil", ["TR 501"], None, "Prof. Deoyani Joshi", OE2, []),
    ("Production Management", "Mechanical", ["CR 508"], None, "Abira Mukherjee", OE2, []),
    ("Elements of Project Management", "Mechanical", ["CR 509"], None, "Dr. Rajesh Patil", OE2, []),
    ("Operations and Supply Chain Management", "Mechanical", ["CR 601"], None, "Dr. Ashish Deshmukh", OE2, []),
]

ALIAS = {"BC LAB": "LAB-BASIC-COMMUNICATION-LAB", "CL-BCL": "LAB-BASIC-COMMUNICATION-LAB",
         "ADVANCE COMMUNICATION LAB": "LAB-ADVANCE-COMMUNICATION-LAB",
         "BASIC COMMUNICATION LAB": "LAB-BASIC-COMMUNICATION-LAB",
         "DE LAB": "LAB-DE-LAB", "AR/VR LAB": "LAB-AR-VR-LAB"}


def resolve_room(code, rooms):
    if code is None:
        return None
    rid = ALIAS.get(code.upper(), room_id(code))
    if rid not in rooms:
        raise SystemExit(f"Unknown room '{code}' -> {rid}")
    return rid


def build_entries(rows, prefix, rooms):
    out = []
    for i, x in enumerate(rows):
        out.append({
            "id": f"{prefix}-{i:02d}",
            "weekday": DAYS[x["day"]],
            "start": x["start"], "end": x["end"],
            "kind": x["kind"],
            "subjectCode": x["subj"],
            "facultyId": INITIAL[x["fac"]] if x["fac"] else None,
            "facultyInitials": x["fac"],
            "roomId": resolve_room(x["room"], rooms),
            "roomLabel": x["room"],
            "batch": x["batch"],
            "sharedNote": x["shared"],
            "reviewFlags": x["flags"],
        })
    return out


def build_oe(rows, slot, prefix, rooms):
    offerings, entries = [], []
    for i, (name, dept, crs, lab, fac, sessions, flags) in enumerate(rows):
        oid = f"{prefix}-{i:02d}"
        offerings.append({
            "id": oid, "slot": slot, "name": name, "offeringDepartment": dept,
            "roomIds": [resolve_room(c, rooms) for c in crs],
            "labRoomId": resolve_room(lab, rooms) if lab else None,
            "faculty": fac, "reviewFlags": flags,
            "sessions": [{"weekday": DAYS[d], "start": s, "end": t, "kind": k} for d, s, t, k in sessions],
        })
        for j, (d, s, t, k) in enumerate(sessions):
            targets = [resolve_room(lab, rooms)] if (k == P and lab) else [resolve_room(c, rooms) for c in crs]
            for rid in targets:
                entries.append({
                    "id": f"{oid}-{j}-{rid}", "weekday": DAYS[d], "start": s, "end": t, "kind": k,
                    "subjectCode": slot, "subjectName": name, "facultyId": None, "facultyInitials": None,
                    "facultyName": fac, "roomId": rid, "roomLabel": rid, "batch": None,
                    "sharedNote": None, "electiveOfferingId": oid, "reviewFlags": [],
                })
    return offerings, entries


TEE_WINDOW = ("2026-11-16", "2026-12-03")  # academic calendar, odd semester Term End Exam
STREAM_GROUPS = {"Computer Engineering": [GROUP_B, GROUP_C]}


def _slug(v):
    return re.sub(r"[^a-z0-9]+", "-", v.lower()).strip("-")


def _norm(v):
    return re.sub(r"[^a-z0-9]", "", v.lower())


def build_exams(offerings, meta):
    """Maps transcribed exam rows to groups/electives and validates them."""
    errors, warnings, records = [], [], []
    seen = {}
    for page, date, stream, subject, code, explicit in ES.CORE:
        start, end = explicit or ES.DEFAULT_TIME
        key = (stream, code, date)
        if key in seen:
            errors.append(f"Duplicate row {key} on pages {seen[key]} and {page}")
            continue
        seen[key] = page
        groups = STREAM_GROUPS.get(stream, [])
        local = ES.STREAM_SUBJECT_CODES.get(stream, {}).get(code)
        flags = []
        if groups and not local:
            flags.append(f"Official code {code} is not mapped to a CampusSync subject.")
        records.append({
            "id": f"exam-{_slug(stream)}-{code.lower()}-{date}",
            "groupIds": groups, "electiveOfferingIds": [],
            "stream": stream, "programYear": 3, "semester": 5,
            "subjectCode": local or code, "officialCode": code, "subjectName": subject,
            "date": date, "startTime": start, "endTime": end,
            "timeSource": "cell" if explicit else "page default",
            "session": None, "room": None, "status": "published",
            "source": f"{SRC_EXAMS}, page {page}, column '{stream.upper()}'",
            "reviewFlags": flags,
        })
    by_name = {_norm(o["name"]): o for o in offerings}
    matched = set()
    for date, (start, end), names in ES.OPEN_ELECTIVES:
        for name in names:
            n = _norm(name)
            flags = []
            if n not in by_name and n in ES.OE_NAME_ALIASES:
                flags.append(f"Exam sheet spells '{name}'; matched to OE timetable "
                             f"'{by_name[ES.OE_NAME_ALIASES[n]]['name']}'.")
                n = ES.OE_NAME_ALIASES[n]
            o = by_name.get(n)
            if o is None:
                errors.append(f"Open elective '{name}' ({date}) not found in the OE timetable")
                continue
            if o["name"] != name and not flags:
                flags.append(f"Exam sheet spells '{name}' (case/punctuation differs).")
            matched.add(o["id"])
            records.append({
                "id": f"exam-{o['id']}-{date}",
                "groupIds": [], "electiveOfferingIds": [o["id"]],
                "stream": "Open Elective (all applicable streams)", "programYear": 3, "semester": 5,
                "subjectCode": o["slot"], "officialCode": None, "subjectName": o["name"],
                "date": date, "startTime": start, "endTime": end, "timeSource": "cell",
                "session": None, "room": None, "status": "published",
                "source": f"{SRC_EXAMS}, page 24, Open Elective table",
                "reviewFlags": flags,
            })
    for o in offerings:
        if o["id"] not in matched:
            warnings.append(f"Open elective '{o['name']}' ({o['slot']}) has no exam on page 24.")
    for r in records:
        if not (TEE_WINDOW[0] <= r["date"] <= TEE_WINDOW[1]):
            warnings.append(f"{r['id']} falls outside the Term End Exam window {TEE_WINDOW}.")
        if r["endTime"] <= r["startTime"]:
            errors.append(f"{r['id']} ends before it starts.")
    core = [r for r in records if not r["electiveOfferingIds"]]
    for i, a in enumerate(core):
        for b in core[i + 1:]:
            if a["stream"] == b["stream"] and a["date"] == b["date"] \
                    and a["startTime"] < b["endTime"] and b["startTime"] < a["endTime"]:
                errors.append(f"Clash in {a['stream']} on {a['date']}: {a['subjectName']} / {b['subjectName']}")
    ce = {r["subjectCode"] for r in records if GROUP_B in r["groupIds"]}
    for code, _ in SUBJECTS:
        if not code.startswith("OE") and code not in ce:
            warnings.append(f"No final exam is listed for Computer Engineering subject {code} on pages 19-20.")
    report = {
        "id": "import-exams-odd-2026-27",
        "kind": "exams",
        "sourceFile": SRC_EXAMS,
        "sourceIssued": "2026-10-01",
        "pagesImported": "19-24 (B.Tech Year III, Semester V)",
        "importedOn": datetime.date.today().isoformat(),
        "method": "Manual transcription from rendered page images (scan has no text layer)",
        "counts": {
            "records": len(records),
            "core": len(core),
            "openElective": len(records) - len(core),
            "linkedToGroups": sum(1 for r in records if r["groupIds"]),
            "streams": len({r["stream"] for r in core}),
        },
        "errors": errors, "warnings": warnings,
        "notImported": "Pages 1-18 and 25-40 (other programmes/semesters): no matching academic groups exist yet.",
    }
    if errors:
        raise SystemExit("Exam import failed validation:\n" + "\n".join(errors))
    return {**meta, "exams": records, "reviewFlags": [
        "Exam rooms are not given in the source.",
        "Rows for streams without CampusSync groups are imported unlinked (no students see them) until an admin maps a group.",
    ]}, report


def write_report(rep):
    lines = [
        "# Import report (generated by tools/build_seed.py)", "",
        f"## {rep['kind']}: `{rep['sourceFile']}`", "",
        f"- Issued: {rep['sourceIssued']} · Imported: {rep['importedOn']} · Pages: {rep['pagesImported']}",
        f"- Method: {rep['method']}",
        "- Counts: " + ", ".join(f"{k}={v}" for k, v in rep["counts"].items()),
        f"- Not imported: {rep['notImported']}", "",
        "### Errors", *(f"- {e}" for e in rep["errors"] or ["None"]), "",
        "### Warnings / review items", *(f"- {w}" for w in rep["warnings"] or ["None"]), "",
    ]
    (ROOT / "docs" / "IMPORT_REPORT.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    floors, rooms = build_floors_and_rooms()
    meta = {"schemaVersion": SCHEMA_VERSION, "generatedBy": "tools/build_seed.py"}

    academic = {
        **meta,
        "institutions": [{"id": INSTITUTION_ID, "name": "SVKM's NMIMS Mukesh Patel School of Technology Management & Engineering",
                          "shortName": "MPSTME", "campus": "Mumbai"}],
        "departments": [{"id": DEPT_ID, "institutionId": INSTITUTION_ID, "name": "Computer Engineering", "active": True}],
        "programs": [{"id": PROGRAM_ID, "departmentId": DEPT_ID, "name": "B.Tech Computer Engineering", "durationYears": 4, "active": True}],
        "academicYears": [{"id": YEAR_ID, "label": "2026-27", "start": "2026-07-13", "end": "2027-07-11", "active": True}],
        "groups": [
            {"id": GROUP_B, "type": "division", "programId": PROGRAM_ID, "departmentId": DEPT_ID,
             "academicYearId": YEAR_ID, "yearOfStudy": 3, "semester": 5, "division": "B",
             "label": "B.Tech Computer · Sem V · Div B", "active": True, "batches": ["B1", "B2"]},
            {"id": GROUP_C, "type": "division", "programId": PROGRAM_ID, "departmentId": DEPT_ID,
             "academicYearId": YEAR_ID, "yearOfStudy": 3, "semester": 5, "division": "C",
             "label": "B.Tech Computer · Sem V · Div C", "active": True, "batches": ["C1", "C2"]},
            {"id": GROUP_OE1, "type": "electivePool", "programId": None, "departmentId": None,
             "academicYearId": YEAR_ID, "yearOfStudy": None, "semester": 5, "division": None,
             "label": "Open Elective I (Mon–Wed 4–6 pm)", "active": True, "batches": []},
            {"id": GROUP_OE2, "type": "electivePool", "programId": None, "departmentId": None,
             "academicYearId": YEAR_ID, "yearOfStudy": None, "semester": 5, "division": None,
             "label": "Open Elective II (Thu–Fri 4–6 pm)", "active": True, "batches": []},
        ],
        "subjects": [{"code": c, "name": n, "programId": PROGRAM_ID, "semester": 5} for c, n in SUBJECTS],
        "faculty": [{"id": fid, "name": name, "initials": inits} for fid, name, inits in FACULTY],
    }
    oe1_off, oe1_entries = build_oe(OE1_LIST, "OE-1", "oe1", rooms)
    oe2_off, oe2_entries = build_oe(OE2_LIST, "OE-2", "oe2", rooms)

    def version(gid, entries, src, flags):
        return {"id": f"{gid}-v1", "groupId": gid, "version": 1, "status": "published",
                "effectiveFrom": "2026-07-13", "effectiveTo": "2026-11-05",
                "source": src, "createdBy": "seed", "entries": entries, "reviewFlags": flags}

    timetables = {**meta, "versions": [
        version(GROUP_B, build_entries(DIV_B, "b", rooms), SRC_DIV_B, [
            "Header reads 'A.Y 2025-26' although the sheet is effective 13 July 2026 (Div C sheet reads 2026-27).",
            "Thursday 08:00-12:00 and Friday 08:00-10:00 have no entries in the source.",
            "Effective end date taken from the academic calendar (term ends 5 Nov 2026).",
        ]),
        version(GROUP_C, build_entries(DIV_C, "c", rooms), SRC_DIV_C, [
            "Tuesday, Thursday and Friday 08:00-10:00 have no entries in the source.",
            "Faculty initials 'VAN' (Div C) and 'VAR' (Div B) both map to Prof. Aishwarinandini Bishnu.",
            "A Saturday column is printed but empty.",
            "Effective end date taken from the academic calendar (term ends 5 Nov 2026).",
        ]),
        version(GROUP_OE1, oe1_entries, SRC_OE, [
            "Sheet title says 'Semester VI' but the slot rows say 'BTech V'.",
            "OE-I theory-only modules: Mon 4-6 and Tue 4-5; modules with labs: Mon 4-6 theory, Tue and Wed 4-6 lab.",
        ]),
        version(GROUP_OE2, oe2_entries, SRC_OE, [
            "OE sheet gives OE-II as Thu 4-6 pm and Fri 4-5 pm, while both division sheets block Fri 4-6 pm.",
        ]),
    ]}

    cal = []

    def ev(eid, title, cat, start, end, sem, audience):
        # Explicit status: Firestore queries and rules only show "published" events to students.
        cal.append({"id": eid, "title": title, "category": cat, "start": start, "end": end,
                    "term": sem, "audience": audience, "source": SRC_CAL, "status": "published"})

    ALL = "btech-mbatech-year2to6"
    MBA5 = "mbatech-year5"
    rows = [
        ("odd", "Commencement of Term", "term", "2026-07-13", "2026-11-05", "2026-09-07", "2026-12-05"),
        ("odd", "Mid Term Test I", "midterm", "2026-08-17", "2026-08-22", None, None),
        ("odd", "Mid Term Test – Management subjects (as per teaching scheme)", "midterm", "2026-09-07", "2026-09-12", "2026-10-19", "2026-10-24"),
        ("odd", "Mid Term Test II", "midterm", "2026-10-05", "2026-10-10", None, None),
        ("odd", "Term End Exam", "termEndExam", "2026-11-16", "2026-12-03", "2026-12-10", "2026-12-22"),
        ("odd", "TEE Lab Exam", "labExam", "2026-12-05", "2026-12-10", None, None),
        ("odd", "Re-exam", "reExam", "2027-01-28", "2027-02-08", "2027-01-28", "2027-02-08"),
        ("odd", "Diwali Vacation", "vacation", "2026-11-06", "2026-11-12", "2026-11-06", "2026-11-12"),
        ("even", "Commencement of Term", "term", "2027-01-02", "2027-04-23", "2027-01-02", "2027-04-23"),
        ("even", "Mid Term Test I", "midterm", "2027-02-10", "2027-02-16", None, None),
        ("even", "Mid Term Test – Management subjects (as per teaching scheme)", "midterm", "2027-03-01", "2027-03-06", "2027-03-01", "2027-03-06"),
        ("even", "Mid Term Test II", "midterm", "2027-03-15", "2027-03-20", None, None),
        ("even", "TEE Lab Exam", "labExam", "2027-04-24", "2027-04-28", None, None),
        ("even", "Term End Exam", "termEndExam", "2027-04-30", "2027-05-20", "2027-04-30", "2027-05-20"),
        ("even", "Re-exam", "reExam", "2027-06-28", "2027-07-08", "2027-06-28", "2027-07-08"),
        ("even", "Winter Vacation", "vacation", "2026-12-26", "2027-01-01", "2026-12-26", "2027-01-01"),
    ]
    for i, (term, title, cat, s, en, ms, me) in enumerate(rows):
        ev(f"cal-{term}-{i:02d}", title, cat, s, en, term, ALL)
        if ms:
            ev(f"cal-{term}-{i:02d}-mba5", title, cat, ms, me, term, MBA5)
    ev("cal-next-ay", "Commencement of next Academic Year (AY 2027-28)", "term", "2027-07-12", "2027-07-12", "next", ALL)

    calendar = {**meta, "audiences": {
        ALL: {"label": "All programs (Year 2–6), M Tech, MCA (Year 1 and 2)", "programIds": [PROGRAM_ID], "yearsOfStudy": [2, 3, 4, 5, 6]},
        MBA5: {"label": "MBA Tech (year 5 only)", "programIds": [], "yearsOfStudy": [5]},
    }, "events": cal, "notes": ["*Dates are subject to change if required. Please reconfirm the dates before booking any tickets.* (source footnote)"]}

    announcements = {**meta, "announcements": [
        {"id": f"ann-{slug}", "title": t, "status": "draft", "category": cat, "summary": None,
         "description": None, "startDate": None, "endDate": None, "registrationUrl": None,
         "imageUrl": None, "audience": {"scope": "all"}, "source": "Supplied by the project team (details pending)",
         "reviewFlags": ["Dates, description and registration link were not available in the workspace; complete before publishing."]}
        for slug, t, cat in [
            ("isl-winter-internship-2026", "India Space Lab Winter Internship and Technical Training Program 2026–27", "internship"),
            ("icpc-india-regionals-2026", "ICPC India Regional Contests 2026", "competition"),
            ("qiskit-fall-fest-2026", "Qiskit Fall Fest 2026 at MPSTME", "event"),
        ]
    ]}

    exams, import_report = build_exams(oe1_off + oe2_off, meta)

    campus = {**meta, "settings": {
        "institutionId": INSTITUTION_ID, "timezone": "Asia/Kolkata",
        "dayStart": "08:00", "dayEnd": "18:00",
        "coverageDeclaredComplete": False,
        "coverageNote": "Only Computer Engineering Sem V Div B/C and Open Elective I/II timetables are published; "
                        "other departments also use these rooms.",
    }, "floors": floors, "rooms": sorted(rooms.values(), key=lambda x: x["id"])}

    for name, data in [("academic", academic), ("timetables", timetables), ("calendar", calendar),
                       ("announcements", announcements), ("exams", exams), ("campus", campus),
                       ("electives", {**meta, "offerings": oe1_off + oe2_off}),
                       ("imports", {**meta, "jobs": [import_report]})]:
        (OUT / f"{name}.json").write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    write_report(import_report)
    print(f"exams={len(exams['exams'])} ({import_report['counts']['linkedToGroups']} linked) "
          f"errors={len(import_report['errors'])} warnings={len(import_report['warnings'])}")
    print(f"rooms={len(rooms)} floors={len(floors)} B={len(DIV_B)} C={len(DIV_C)} "
          f"OE1={len(oe1_entries)} OE2={len(oe2_entries)} events={len(cal)}")


if __name__ == "__main__":
    main()
