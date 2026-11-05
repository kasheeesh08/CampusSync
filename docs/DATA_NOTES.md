# Reference data: extraction notes and review flags

Source data is hand-transcribed in `tools/build_seed.py`, which regenerates `app/assets/seed/*.json`
(`python -I tools/build_seed.py`). The original reference files are unchanged.

## Inputs (status as of 2026-10-20 evening)
| Item | Status |
|---|---|
| `final exam timetable/MPSTME_ODD_Semester_Final_Exam_Time_Table_2026_2027_4ycvxuhivW.pdf` | **Imported.** 40 scanned pages with no text layer, issued 1 Oct 2026. Pages 19–24 (B.Tech Year III, Sem V) were transcribed in `tools/exam_source.py`: 88 stream exam rows across 15 streams plus 36 open-elective rows. Details in `docs/IMPORT_REPORT.md`. |
| Floor 2 layout (`WhatsApp Image 2026-10-20 at 7.05.13 PM.jpeg`) | **Imported.** 13 rooms (TR 201–203, CR 201–204, CR 206–209, CC 201, Physics Lab) with no ID collisions. The blue highlight on CR 201 in the source image is a selection in the source app, not data. |
| Announcement details | Only the three titles are known. They're stored as drafts with no dates or links, and students don't see them. |
| "Other subject report" front page | Not in the workspace. |

## Exam timetable flags
- **No final exam is listed for Mobile Application Development** in the Computer Engineering column (pages 19–20). None was invented.
- **Data Analytics** (OE-I) has no exam on page 24. It also has no room, faculty or time in the OE sheet.
- Exams are listed per **stream**, not per division, so Computer Engineering exams apply to both Div B and Div C.
- No exam rooms appear anywhere in the source.
- Times: the page default for Sem V is 10:00–13:00. Times printed in a cell override it, and `timeSource` records which applies.
- The exam sheet spells the elective "Wireless Communication for Everybody", while the OE timetable says "Wireless Communications for Everybody". They're matched through a reviewed alias, with a review flag on the record. Other OE names differ only in case.
- Streams without CampusSync groups (AI, AI&DS, Civil, CS, CSBS, IT, Mechanical, EXTC and others) are imported but unlinked, so no student sees them until an admin assigns a group.
- Pages 1–18 and 25–40 (other programmes and semesters) were not imported.

## Timetable flags
- The Div B header says "A.Y 2025-26" but the sheet is effective 13 July 2026. The Div C header says 2026-27.
- Div B and Div C both list **OR [VGW] CR-402 Mon 15:00-16:00** and **OR [VGW] CR-405 Thu 12:00-13:00**. These are probably combined lectures, but the sheets don't mark them as combined, so the admin validator reports them as cross-group overlaps.
- Wed 10-12 MAD (B2+C2, CL-503) and OR (B1+C1, CL-401) are marked as combined on both sheets and are stored as shared sessions.
- Div B Wed 08-10 lists MAD only for batch B1.
- Div C Mon 14-15 AI is in CR-609 (6th floor); please confirm.
- Faculty initials VAR (Div B) and VAN (Div C) both refer to Prof. Aishwarinandini Bishnu. "Porf. Shabnam Ansari" is normalised to "Prof.".
- Empty source slots (for example Div B Thu 08-12) are stored as *no entry*, not as free periods.
- `effectiveTo` = 5 Nov 2026, the end of term in the academic calendar. The timetables themselves give only "w.e.f."

## Open elective sheet flags
- The title says "Semester VI", but the slot rows say "BTech V".
- OE-II is Thu 4-6 and Fri 4-5 on the OE sheet, while the division sheets block Fri 4-6.
- Smart Cities has an extra "Tue(5-6) & Wed (2-6)" note that is unclear, so it isn't scheduled. The 3D Printing lab (8th floor) isn't on the Floor 8 plan. The Elements of Automation lab spans several rooms. Data Analytics has no room, faculty or time.

## Floor plans
Room regions are normalised (0..1) against the drawing frame of the screenshots, which comes from the MPSTME OnTrack app by the Developers Club. Both Floor 1 and Floor 8 contain an unlabelled "NA" room.
