"""Hand transcription of the MPSTME Odd Semester Final Examination Timetable 2026-27.

Source: final exam timetable/MPSTME_ODD_Semester_Final_Exam_Time_Table_2026_2027_4ycvxuhivW.pdf
(40 scanned pages, no text layer; issued "DATE: 1ST OCTOBER, 2026").

Only B.Tech Year III / Semester V (pages 19-24) is transcribed, because that is the
only year/semester with academic groups in CampusSync. Pages for other programmes
and semesters (MBA Tech, MCA, M Tech, Diploma, B.Tech I/II/IV, integrated B.Tech)
are NOT imported; see docs/IMPORT_REPORT.md.

Page default time for B.Tech Sem V: "EXAM TIME: 10:00 AM - 1:00 PM (CHECK THE SUBJECT
EXAM TIME)". A per-subject time printed in the cell overrides it.
"""

DEFAULT_TIME = ("10:00", "13:00")
PM = ("14:00", "17:00")
AM2 = ("10:00", "12:00")

# (page, date, stream, subject, official code, explicit time or None)
CORE = [
    # ---- Page 19 -------------------------------------------------------------
    (19, "2026-11-17", "Artificial Intelligence and Machine Learning", "Robotics: Computational Motion Planning", "702AI0E025", None),
    (19, "2026-11-17", "Civil Engineering", "Hydraulics and Fluid Machinery", "702CI0C040", None),
    (19, "2026-11-17", "Computer Engineering", "Operations Research", "702CO0E034", None),
    (19, "2026-11-17", "Computer Science", "Operations Research", "702CO0E034", None),
    (19, "2026-11-18", "Artificial Intelligence and Data Science", "Iot and Applications", "702CO0E045", None),
    (19, "2026-11-19", "Artificial Intelligence", "Intelligent Systems - II", "702AI0E018", None),
    (19, "2026-11-19", "Artificial Intelligence and Data Science", "Artificial Intelligence (Transition)", "702CO0C076", None),
    (19, "2026-11-19", "Artificial Intelligence and Machine Learning", "Data Wrangling", "702DB0C036", PM),
    (19, "2026-11-19", "Civil Engineering", "Foundation Engineering", "702CI0C041", None),
    (19, "2026-11-19", "Computer Engineering", "Artificial Intelligence", "702CO0C076", None),
    (19, "2026-11-19", "Computer Science", "Compiler Design", "702CS0C008", None),
    (19, "2026-11-21", "Artificial Intelligence", "Computer Networks", "702AI0C023", None),
    (19, "2026-11-21", "Artificial Intelligence and Data Science", "Computer Networks", "702AI0C023", None),
    (19, "2026-11-21", "Artificial Intelligence and Machine Learning", "Computer Networks", "702AI0C023", None),
    (19, "2026-11-23", "Artificial Intelligence and Data Science", "Biometrics", "702CO0E042", PM),
    (19, "2026-11-23", "Computer Engineering", "Software Engineering", "702IT0C041", None),
    (19, "2026-11-23", "Computer Science", "Software Engineering", "702IT0C041", None),
    (19, "2026-11-24", "Civil Engineering", "Green and Intelligent Buildings", "702CI0E020", None),
    (19, "2026-11-25", "Artificial Intelligence", "Deep Learning", "702AI0C036", PM),
    (19, "2026-11-25", "Artificial Intelligence and Machine Learning", "Deep Learning", "702AI0C036", PM),
    (19, "2026-11-25", "Computer Engineering", "Operating Systems", "702CO0C056", None),
    (19, "2026-11-25", "Computer Science", "Operating Systems", "702CO0C056", None),
    (19, "2026-11-26", "Artificial Intelligence and Data Science", "Cryptography and Network Security", "702AI0E015", PM),
    (19, "2026-11-27", "Artificial Intelligence", "Natural Language Processing", "702AI0C037", PM),
    (19, "2026-11-27", "Artificial Intelligence and Machine Learning", "Natural Language Processing", "702AI0C037", PM),
    (19, "2026-11-27", "Civil Engineering", "Design of Reinforced Concrete Structures", "702CI0C039", None),
    (19, "2026-11-27", "Computer Engineering", "Image and Video Processing", "702EX0E020", None),
    (19, "2026-11-27", "Computer Science", "Image and Video Processing", "702EX0E020", None),
    (19, "2026-11-28", "Artificial Intelligence and Data Science", "Blockchain Technology", "702IT0E049", PM),
    # ---- Page 20 -------------------------------------------------------------
    (20, "2026-12-01", "Artificial Intelligence", "Design and Analysis of Algorithms", "702CO0C071", None),
    (20, "2026-12-01", "Artificial Intelligence and Data Science", "Predictive Analysis", "702DB0E019", None),
    (20, "2026-12-01", "Computer Science", "Advanced Database Management Systems", "702IT0E052", PM),
    # ---- Page 21 -------------------------------------------------------------
    (21, "2026-11-17", "Computer Science and Business Systems", "Compiler Design", "702CO0C079", None),
    (21, "2026-11-17", "CSE - Cyber Security", "Cloud Security", "702IT0E046", None),
    (21, "2026-11-17", "CSE - DS (7011)", "Principles of Management", "702TG0C026", None),
    (21, "2026-11-18", "CSE - DS (7057)", "Distributed Computing", "702CO0E041", None),
    (21, "2026-11-18", "EXTC", "Discrete Mathematics", "702BS0C077", PM),
    (21, "2026-11-19", "Computer Science and Business Systems", "Services Science & Service Operational Management", "702CO0C080", None),
    (21, "2026-11-19", "CSE - Cyber Security", "AI and ML for Cybersecurity", "702IT0E047", None),
    (21, "2026-11-19", "CSE - DS (7011)", "Marketing Management", "702TM0C018", None),
    (21, "2026-11-19", "Data Science", "Introduction to Modern Application Development", "702DB0C043", None),
    (21, "2026-11-21", "Computer Science and Business Systems", "Business Strategy", "702TG0C024", AM2),
    (21, "2026-11-21", "CSE - DS (7011)", "Design for Consumers", "702TM0C019", None),
    (21, "2026-11-21", "CSE - DS (7057)", "Computer Networks", "702AI0C023", None),
    (21, "2026-11-21", "Data Science", "Virtualization and Cloud Computing", "702DB0E024", None),
    (21, "2026-11-21", "EXTC", "Digital System Design using HDL", "702EX0E019", None),
    (21, "2026-11-23", "Computer Science and Business Systems", "Software Engineering", "702IT0C041", None),
    (21, "2026-11-23", "CSE - Cyber Security", "Software Engineering", "702IT0C041", None),
    (21, "2026-11-23", "CSE - DS (7057)", "Software Engineering", "702IT0C041", None),
    (21, "2026-11-24", "CSE - DS (7011)", "Machine Learning", "702DB0C049", None),
    (21, "2026-11-24", "EXTC", "Discrete Time Signal Processing", "702EX0C038", None),
    (21, "2026-11-25", "Computer Science and Business Systems", "Machine Learning", "702CO0E036", PM),
    (21, "2026-11-25", "CSE - DS (7057)", "Operating Systems", "702CO0C056", None),
    (21, "2026-11-25", "Data Science", "Applied Artificial Intelligence and Agentic System", "702DB0C044", None),
    (21, "2026-11-25", "EXTC", "Machine Learning", "702CO0E036", PM),
    (21, "2026-11-26", "CSE - Cyber Security", "Cybersecurity Fundamentals", "702IT0C042", None),
    (21, "2026-11-26", "CSE - DS (7057)", "Cryptography and Network Security", "702AI0E015", PM),
    (21, "2026-11-26", "Data Science", "Applied Time Series Analysis", "702DB0E023", PM),
    (21, "2026-11-26", "EXTC", "Computer Communication and Networks", "702EX0C040", None),
    (21, "2026-11-27", "CSE - DS (7011)", "Advanced Modeling for Business Analytics", "702DB0C046", None),
    (21, "2026-11-27", "CSE - DS (7057)", "Data Driven Program Analysis", "702DB0E022", None),
    (21, "2026-11-27", "Data Science", "Data Driven Program Analysis", "702DB0E022", None),
    (21, "2026-11-28", "Computer Science and Business Systems", "Modern Day Robotics and Its Industrial Applications", "702CO0E038", None),
    (21, "2026-11-28", "CSE - Cyber Security", "Network Security", "702IT0C043", None),
    # ---- Page 22 -------------------------------------------------------------
    (22, "2026-11-30", "Data Science", "Foundations of Machine Learning", "702DB0C045", None),
    (22, "2026-12-01", "Computer Science and Business Systems", "Design and Analysis of Algorithms", "702CO0C071", None),
    # ---- Page 23 -------------------------------------------------------------
    (23, "2026-11-17", "Information Technology", "Management Information Systems", "702IT0E040", None),
    (23, "2026-11-17", "Mechanical Engineering", "Manufacturing Processes-II", "702ME0C037", None),
    (23, "2026-11-17", "Mechatronics Engineering", "Manufacturing Processes", "702MH0C032", None),
    (23, "2026-11-19", "Information Technology", "Advanced Data Structures", "702IT0E041", None),
    (23, "2026-11-19", "Mechanical Engineering", "Lean Manufacturing", "702ME0E039", None),
    (23, "2026-11-19", "Mechatronics Engineering", "Industrial Engineering", "702ME0E048", None),
    (23, "2026-11-20", "Mechanical Engineering", "Electric and Hybrid Automotive Technology", "702MH0E026", None),
    (23, "2026-11-21", "Mechanical Engineering", "Industrial Automation and Robotics", "702ME0E041", None),
    (23, "2026-11-21", "Mechatronics Engineering", "Design of Machine Components", "702MH0E029", None),
    (23, "2026-11-23", "Information Technology", "Software Engineering", "702IT0C041", None),
    (23, "2026-11-24", "Mechanical Engineering", "Design of Machine Elements", "702ME0C036", None),
    (23, "2026-11-24", "Mechatronics Engineering", "Classical Control Systems", "702MH0C031", None),
    (23, "2026-11-25", "Information Technology", "Embedded Systems", "702IT0C039", None),
    (23, "2026-11-26", "Mechanical Engineering", "Smart Manufacturing and Internet of Things", "702ME0E038", None),
    (23, "2026-11-26", "Mechatronics Engineering", "Industrial Data Communication", "702MH0E032", None),
    (23, "2026-11-27", "Information Technology", "AI and Robotics", "702IT0E043", None),
    (23, "2026-11-27", "Mechanical Engineering", "Composite Materials", "702ME0E043", None),
    (23, "2026-11-27", "Mechatronics Engineering", "Industrial Drives", "702MH0C030", None),
    (23, "2026-11-28", "Mechanical Engineering", "Additive Manufacturing", "702ME0E045", None),
    (23, "2026-12-01", "Information Technology", "Human Computer Interaction", "702CO0E040", PM),
    (23, "2026-12-01", "Mechanical Engineering", "Fluid Mechanics", "702ME0C038", None),
    (23, "2026-12-01", "Mechatronics Engineering", "Operations Research", "702MH0E028", None),
]

# Page 24: open electives ("ALL APPLICABLE STREAMS"), names exactly as printed.
OPEN_ELECTIVES = [
    ("2026-12-02", ("10:00", "13:00"), [
        "3D Printing", "5G for Everyone", "Basic Decision making with Spreadsheet", "Disaster Management",
        "Drone Technology", "Electric Vehicle Technology", "Elements of Automation",
        "Engineering Materials for Daily Life", "Fundamentals of Climate Change", "Game Design",
        "Industrial Ergonomics", "Interior Design", "Renewable Energy Sources"]),
    ("2026-12-02", ("14:00", "17:00"), [
        "Introduction to GIS", "Introduction to Virtual Reality and Augmented Reality", "Research Methodology",
        "Smart Cities", "Supervisory Control and Data Acquisition", "Sustainable Energy Technologies",
        "Wireless Communication for Everybody"]),
    ("2026-12-03", ("10:00", "13:00"), [
        "Advertising and Public Relations", "Creativity and ethics in Marketing", "Elements of Project Management",
        "Environment Management", "Financial Derivatives", "Financial Institutions, Markets, Instruments and Services",
        "Introduction to Forensic Science", "Leading through Life Skills", "Life Skills", "Management Through Movies",
        "Modelling and Simulation", "Operations and Supply Chain Management", "Production Management",
        "Quantum Computing and Technologies", "Technology and Innovation for Marketing", "Waste Management"]),
]

# Exam-sheet names that differ from the OE timetable beyond case/punctuation.
# Each is a reviewed alias, recorded as a review flag on the record.
OE_NAME_ALIASES = {
    "wirelesscommunicationforeverybody": "wirelesscommunicationsforeverybody",
}

# Exam-sheet stream header -> CampusSync subject code, for streams that have groups.
STREAM_SUBJECT_CODES = {
    "Computer Engineering": {
        "702CO0E034": "OR", "702CO0C076": "AI", "702IT0C041": "SE", "702CO0C056": "OS", "702EX0E020": "IVP",
    },
}
